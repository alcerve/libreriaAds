"""AdsClient: cliente ADS bloqueante con soporte de notificaciones."""

import random
import socket
import struct
import threading

from . import constants as C
from . import datatypes
from .ams_addr import AmsAddr
from .ams_netid import AmsNetId
from .errors import AdsError
from .packet import (
    AmsPacket,
    build_tcp_frame,
    encode_ams_packet,
    recv_packet,
    send_all,
)


class SymbolInfo:
    """Información de un símbolo PLC."""

    def __init__(self, index_group, index_offset, size, data_type, flags, name, type_name, comment):
        self.index_group = index_group
        self.index_offset = index_offset
        self.size = size
        self.data_type = data_type
        self.flags = flags
        self.name = name
        self.type_name = type_name
        self.comment = comment

    def __repr__(self):
        return (
            "SymbolInfo(name=%r, type=%r, size=%d, ig=0x%08X, io=0x%08X)"
            % (self.name, self.type_name, self.size, self.index_group, self.index_offset)
        )


class NotificationSample:
    """Muestra entregada por una notificación ADS."""

    def __init__(self, handle, timestamp, data):
        self.handle = handle
        self.timestamp = timestamp  # FILETIME Windows (100 ns desde 1601-01-01)
        self.data = data

    def __repr__(self):
        return "NotificationSample(handle=%d, timestamp=%d, data_len=%d)" % (
            self.handle,
            self.timestamp,
            len(self.data),
        )


class AdsClient:
    """Cliente del protocolo ADS de Beckhoff.

    Parámetros:
        ams_net_id: NetId AMS del destino (por defecto ``127.0.0.1.1.1``).
        ams_port: puerto AMS del destino (por defecto ``851``, PLC runtime).
        ip_address: host donde conecta el socket TCP.
        tcp_port: puerto TCP de AMS/TCP (por defecto ``48898``).
        timeout: timeout de cada transacción, en segundos.
        local_port: puerto AMS local (0 = aleatorio).
    """

    def __init__(
        self,
        ams_net_id="127.0.0.1.1.1",
        ams_port=C.PORT_PLC_TC3,
        ip_address="127.0.0.1",
        tcp_port=C.AMS_TCP_PORT,
        timeout=5.0,
        local_port=0,
    ):
        self.target = AmsAddr(AmsNetId(ams_net_id), ams_port)
        self.ip_address = ip_address
        self.tcp_port = tcp_port
        self.timeout = float(timeout)
        self._local_netid = AmsNetId("127.0.0.1.1.1")
        self._local_ams_port = local_port if local_port > 0 else random.randint(2000, 60000)

        self._sock = None
        self._send_lock = threading.Lock()
        self._invoke_lock = threading.Lock()
        self._invoke_id = 0

        # invoke_id -> [threading.Event, contenedor de respuesta]
        self._pending = {}
        self._pending_lock = threading.Lock()

        # handle -> callable(NotificationSample)
        self._notifications = {}
        self._notif_lock = threading.Lock()

        self._reader = None
        self._stop = threading.Event()
        self._closed = False

    # ------------------------------------------------------------------ ciclo
    def open(self):
        if self._sock is not None:
            return self
        self._sock = socket.create_connection((self.ip_address, self.tcp_port), timeout=self.timeout)
        # El timeout del hilo lector se usa sólo para poder salir en close();
        # con el valor de transacción se evita desincronizar frames parciales.
        self._sock.settimeout(self.timeout)
        self._closed = False
        self._stop.clear()
        self._reader = threading.Thread(target=self._read_loop, name="ads-reader", daemon=True)
        self._reader.start()
        return self

    def close(self):
        if self._sock is None:
            return
        self._stop.set()
        try:
            self._sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        try:
            self._sock.close()
        except OSError:
            pass
        self._sock = None
        self._closed = True
        # despierta a los que esperan respuesta
        with self._pending_lock:
            for event, _holder in list(self._pending.values()):
                event.set()

    def __enter__(self):
        self.open()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()
        return False

    # ------------------------------------------------------------------ lector
    def _read_loop(self):
        while not self._stop.is_set():
            try:
                pkt = recv_packet(self._sock)
            except socket.timeout:
                continue
            except (OSError, ConnectionError, ValueError):
                break
            if pkt.command_id == C.ADS_CMD_DEVICE_NOTIFICATION:
                self._dispatch_notification(pkt)
                continue
            with self._pending_lock:
                entry = self._pending.get(pkt.invoke_id)
            if entry is not None:
                event, holder = entry
                holder["resp"] = pkt
                event.set()

    def _dispatch_notification(self, pkt):
        data = pkt.data
        if len(data) < 4:
            return
        (total,) = struct.unpack("<I", data[:4])
        off = 4
        end = min(off + total, len(data))
        while off + 16 <= end:
            handle, timestamp, sample_size = struct.unpack("<IQI", data[off : off + 16])
            off += 16
            sample = data[off : off + sample_size]
            off += sample_size
            with self._notif_lock:
                callback = self._notifications.get(handle)
            if callback is not None:
                try:
                    callback(NotificationSample(handle, timestamp, sample))
                except Exception:
                    pass

    # ------------------------------------------------------------------ request
    def _next_invoke_id(self):
        with self._invoke_lock:
            self._invoke_id = (self._invoke_id + 1) & 0xFFFFFFFF
            return self._invoke_id

    def _request(self, command_id, data=b""):
        """Envía una petición y espera su respuesta correlacionada por invoke_id.

        Flujo:
          1. Reserva un invoke_id único (contador de 32 bits).
          2. Registra un Event en ``_pending`` para que el hilo lector pueda
             despertarnos cuando llegue la respuesta con ese mismo invoke_id.
          3. Construye la cabecera AMS (comando, ids, flags=0 => solicitud),
             la envuelve en el frame AMS/TCP y la manda por el socket.
          4. Espera ``timeout`` segundos al Event. Si no llega, lanza timeout.
          5. Si el error_code de la respuesta no es 0, lanza AdsError.
        """
        # Sin socket abierto no se puede transaccionar.
        if self._sock is None:
            raise AdsError(0x00000006, "Cliente no conectado (llama a open())")

        # invoke_id: correlaciona petición <-> respuesta (campo de la cabecera AMS).
        invoke_id = self._next_invoke_id()
        event = threading.Event()   # se "setea" cuando el lector recibe la respuesta
        holder = {}                 # contenedor mutable para guardar la respuesta
        with self._pending_lock:
            self._pending[invoke_id] = (event, holder)

        # Cabecera AMS de solicitud: destino = PLC, origen = cliente local.
        pkt = AmsPacket()
        pkt.target_netid = self.target.netid
        pkt.target_port = self.target.port
        pkt.source_netid = self._local_netid
        pkt.source_port = self._local_ams_port
        pkt.command_id = command_id
        pkt.state_flags = 0        # 0 = solicitud (1 = respuesta, 4 = notificación)
        pkt.invoke_id = invoke_id
        pkt.data = data

        # Envía: cabecera AMS (32 B) + datos, todo envuelto en el frame AMS/TCP.
        try:
            with self._send_lock:  # serializa escrituras si varios hilos envían a la vez
                send_all(self._sock, build_tcp_frame(encode_ams_packet(pkt)))
        except OSError as exc:
            self._pending.pop(invoke_id, None)
            raise AdsError(0x0000001B, "Fallo al enviar: %s" % exc)

        # Espera la respuesta (o timeout). El hilo lector hará event.set().
        if not event.wait(self.timeout):
            self._pending.pop(invoke_id, None)
            raise AdsError(0x00000745, "Timeout agotado")

        # Respuesta recibida: quitamos la entrada pendiente y validamos.
        self._pending.pop(invoke_id, None)
        resp = holder.get("resp")
        if resp is None:
            raise AdsError(0x00000001, "Conexión cerrada sin respuesta")
        if resp.error_code != 0:   # el PLC devolvió un código de error ADS
            raise AdsError(resp.error_code)
        return resp.data

    # ------------------------------------------------------------------ info
    def read_device_info(self):
        data = self._request(C.ADS_CMD_READ_DEVICE_INFO)
        if len(data) < 20:
            raise AdsError(0x00000001, "Respuesta de dispositivo inválida")
        major = data[0]
        minor = data[1]
        build = struct.unpack("<H", data[2:4])[0]
        name = data[4:20].split(b"\x00", 1)[0].decode("ascii", "replace")
        return (major, minor, build, name)

    def read_state(self):
        data = self._request(C.ADS_CMD_READ_STATE)
        ads_state, device_state = struct.unpack("<HH", data[:4])
        return (ads_state, device_state)

    def write_control(self, state, device_state=0, data=b""):
        payload = struct.pack("<HHI", state, device_state, len(data)) + data
        self._request(C.ADS_CMD_WRITE_CONTROL, payload)

    # ------------------------------------------------------------------ raw
    def read_index(self, index_group, index_offset, size):
        payload = struct.pack("<III", index_group, index_offset, size)
        return self._request(C.ADS_CMD_READ, payload)

    def write_index(self, index_group, index_offset, data):
        payload = struct.pack("<III", index_group, index_offset, len(data)) + data
        self._request(C.ADS_CMD_WRITE, payload)

    def read_write(self, index_group, index_offset, read_len, write_data):
        payload = (
            struct.pack("<IIII", index_group, index_offset, read_len, len(write_data)) + write_data
        )
        return self._request(C.ADS_CMD_READ_WRITE, payload)

    # ------------------------------------------------------------------ símbolos
    def read_symbol_info(self, name):
        nb = name.encode("utf-8")
        payload = struct.pack("<III", C.INDEXGROUP_SYM_INFOBYNAME, 0, len(nb)) + nb
        data = self._request(C.ADS_CMD_READ, payload)
        return self._parse_symbol_info(data)

    @staticmethod
    def _parse_symbol_info(data):
        if len(data) < 24:
            raise AdsError(0x00000001, "Información de símbolo inválida")
        index_group, index_offset, size, data_type, flags = struct.unpack("<IIIIH", data[:18])
        name_length, type_length, comment_length = struct.unpack("<HHH", data[18:24])
        off = 24
        name = data[off : off + name_length].rstrip(b"\x00").decode("utf-8", "replace")
        off += name_length
        type_name = data[off : off + type_length].rstrip(b"\x00").decode("utf-8", "replace")
        off += type_length
        comment = data[off : off + comment_length].rstrip(b"\x00").decode("utf-8", "replace")
        return SymbolInfo(index_group, index_offset, size, data_type, flags, name, type_name, comment)

    def get_handle(self, name):
        nb = name.encode("utf-8")
        payload = struct.pack("<III", C.INDEXGROUP_SYM_HNDBYNAME, 0, len(nb)) + nb
        data = self._request(C.ADS_CMD_READ, payload)
        if len(data) < 4:
            raise AdsError(0x00000001, "Respuesta de handle inválida")
        return struct.unpack("<I", data[:4])[0]

    def release_handle(self, handle):
        payload = struct.pack("<III", C.INDEXGROUP_SYM_RELEASEHND, handle, 0)
        self._request(C.ADS_CMD_WRITE, payload)

    def read_by_handle(self, handle, size):
        payload = struct.pack("<III", C.INDEXGROUP_SYM_VALBYHND, handle, size)
        return self._request(C.ADS_CMD_READ, payload)

    def write_by_handle(self, handle, data):
        payload = struct.pack("<III", C.INDEXGROUP_SYM_VALBYHND, handle, len(data)) + data
        self._request(C.ADS_CMD_WRITE, payload)

    def read_by_name(self, name, plc_datatype=None):
        """Lee una variable por su nombre (índice de grupo SYM_VALBYNAME).

        Payload de lectura:
          [index_group u32][index_offset u32][longitud_nombre u32][nombre][bytes_a_leer u32]
        """
        # Si no dan tipo, lo resolvemos pidiendo la info del símbolo al PLC.
        if plc_datatype is None:
            size = self.read_symbol_info(name).size
        else:
            size = datatypes.size_of(plc_datatype)
        nb = name.encode("utf-8")
        payload = (
            struct.pack("<III", C.INDEXGROUP_SYM_VALBYNAME, 0, len(nb)) + nb + struct.pack("<I", size)
        )
        data = self._request(C.ADS_CMD_READ, payload)
        # Con tipo: devolvemos el valor ya decodificado; sin tipo: bytes crudos.
        if plc_datatype is not None:
            return datatypes.decode_value(data, plc_datatype)
        return data

    def write_by_name(self, name, value, plc_datatype=None):
        """Escribe una variable por su nombre (índice de grupo SYM_VALBYNAME).

        Payload de escritura:
          [index_group u32][index_offset u32][longitud_nombre u32][nombre][longitud_valor u32][valor]
        """
        nb = name.encode("utf-8")
        # El valor puede venir ya como bytes, o codificarse desde un tipo PLC.
        if plc_datatype is not None:
            data = datatypes.encode_value(value, plc_datatype)
        elif isinstance(value, (bytes, bytearray)):
            data = bytes(value)
        else:
            raise ValueError("Especifica plc_datatype o pasa value como bytes")
        payload = (
            struct.pack("<III", C.INDEXGROUP_SYM_VALBYNAME, 0, len(nb))
            + nb
            + struct.pack("<I", len(data))
            + data
        )
        self._request(C.ADS_CMD_WRITE, payload)

    # ------------------------------------------------------- estructuras
    def read_struct(self, name, struct_def):
        """Lee una estructura completa y devuelve un dict {miembro: valor}.

        Hace una única lectura del bloque de bytes de la estructura (usando el
        tamaño real del símbolo) y descodifica cada miembro según su offset.
        """
        data = self.read_by_name(name)  # bytes crudos de toda la estructura
        return struct_def.decode(data)

    def write_struct(self, name, struct_def, values):
        """Escribe una estructura completa a partir de un dict {miembro: valor}.

        Codifica cada miembro en su offset dentro del bloque y hace una única
        escritura de toda la estructura.
        """
        self.write_by_name(name, struct_def.encode(values))

    # ------------------------------------------------------- notificaciones
    def add_device_notification(
        self,
        index_group,
        index_offset,
        cb_length,
        trans_mode=C.ADSTRANS_SERVERONCHA,
        max_delay=0,
        cycle_time=1000000,
        callback=None,
    ):
        """Suscribe una notificación y devuelve su handle.

        ``cycle_time`` va en unidades de 100 ns; ``max_delay`` en milisegundos.
        ``callback`` recibe un :class:`NotificationSample`.
        """
        attrib = (
            struct.pack("<IIII", cb_length, trans_mode, max_delay, cycle_time) + b"\x00" * 8
        )
        payload = struct.pack("<II", index_group, index_offset) + attrib
        data = self._request(C.ADS_CMD_ADD_DEVICE_NOTIFICATION, payload)
        if len(data) < 4:
            raise AdsError(0x00000001, "Respuesta de notificación inválida")
        handle = struct.unpack("<I", data[:4])[0]
        if callback is not None:
            with self._notif_lock:
                self._notifications[handle] = callback
        return handle

    def del_device_notification(self, handle):
        self._request(C.ADS_CMD_DEL_DEVICE_NOTIFICATION, struct.pack("<I", handle))
        with self._notif_lock:
            self._notifications.pop(handle, None)

    def add_notification_by_name(
        self,
        name,
        plc_datatype=None,
        trans_mode=C.ADSTRANS_SERVERONCHA,
        max_delay=0,
        cycle_time=1000000,
        callback=None,
    ):
        """Suscribe una notificación a una variable por su nombre.

        Resuelve internamente la información del símbolo para obtener el par
        (index_group, index_offset) y devuelve el handle de la notificación.
        """
        info = self.read_symbol_info(name)
        cb_length = info.size if plc_datatype is None else datatypes.size_of(plc_datatype)
        return self.add_device_notification(
            info.index_group,
            info.index_offset,
            cb_length,
            trans_mode=trans_mode,
            max_delay=max_delay,
            cycle_time=cycle_time,
            callback=callback,
        )

    # ------------------------------------------------------------------ sum
    def sum_read(self, entries):
        """``entries``: iterable de tuplas (index_group, index_offset, length).

        Devuelve una lista con los bytes leídos por entrada; lanza
        :class:`AdsError` si alguna entrada falla.
        """
        entries = list(entries)
        body = b"".join(struct.pack("<III", ig, io, ln) for ig, io, ln in entries)
        payload = struct.pack("<III", C.INDEXGROUP_SUMUP_READ, 0, len(body)) + body
        data = self._request(C.ADS_CMD_READ, payload)
        results = []
        off = 0
        for _ig, _io, ln in entries:
            if off + 8 > len(data):
                raise AdsError(0x00000001, "Respuesta sum_read incompleta")
            result, length = struct.unpack("<II", data[off : off + 8])
            off += 8
            chunk = data[off : off + length]
            off += length
            if result != 0:
                raise AdsError(result)
            results.append(chunk)
        return results

    def sum_write(self, entries):
        """``entries``: iterable de tuplas (index_group, index_offset, data)."""
        entries = list(entries)
        body = b"".join(struct.pack("<III", ig, io, len(d)) + d for ig, io, d in entries)
        payload = struct.pack("<III", C.INDEXGROUP_SUMUP_WRITE, 0, len(body)) + body
        data = self._request(C.ADS_CMD_WRITE, payload)
        results = [struct.unpack("<I", data[i : i + 4])[0] for i in range(0, len(data), 4)]
        for result in results:
            if result != 0:
                raise AdsError(result)
        return results

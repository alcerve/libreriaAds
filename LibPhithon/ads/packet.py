"""Codificación/decodificación del frame AMS/TCP y de la cabecera AMS."""

import socket
import struct

from .ams_netid import AmsNetId

TCP_HEADER_SIZE = 6
AMS_HEADER_SIZE = 32


class AmsPacket:
    """Mensaje ADS completo (cabecera AMS + datos)."""

    def __init__(self):
        self.target_netid = AmsNetId()
        self.target_port = 0
        self.source_netid = AmsNetId()
        self.source_port = 0
        self.command_id = 0
        self.state_flags = 0
        self.error_code = 0
        self.invoke_id = 0
        self.data = b""

    def __repr__(self):
        return (
            "AmsPacket(cmd=0x{:04X}, state={}, error=0x{:08X}, invoke={}, "
            "target={}:{}, source={}:{}, data_len={})".format(
                self.command_id,
                self.state_flags,
                self.error_code,
                self.invoke_id,
                self.target_netid,
                self.target_port,
                self.source_netid,
                self.source_port,
                len(self.data),
            )
        )


def encode_ams_packet(packet):
    """Serializa la cabecera AMS (32 bytes) + datos."""
    header = struct.pack(
        "<6sH6sHHHIII",
        bytes(packet.target_netid),
        packet.target_port,
        bytes(packet.source_netid),
        packet.source_port,
        packet.command_id,
        packet.state_flags,
        len(packet.data),
        packet.error_code,
        packet.invoke_id,
    )
    return header + packet.data


def decode_ams_packet(buf):
    """Deserializa una cabecera AMS (mínimo 32 bytes) en un :class:`AmsPacket`."""
    if len(buf) < AMS_HEADER_SIZE:
        raise ValueError("Cabecera AMS incompleta (%d bytes)" % len(buf))
    (
        t_netid,
        t_port,
        s_netid,
        s_port,
        command_id,
        state_flags,
        length,
        error_code,
        invoke_id,
    ) = struct.unpack("<6sH6sHHHIII", buf[:AMS_HEADER_SIZE])
    pkt = AmsPacket()
    pkt.target_netid = AmsNetId(t_netid)
    pkt.target_port = t_port
    pkt.source_netid = AmsNetId(s_netid)
    pkt.source_port = s_port
    pkt.command_id = command_id
    pkt.state_flags = state_flags
    pkt.error_code = error_code
    pkt.invoke_id = invoke_id
    pkt.data = buf[AMS_HEADER_SIZE : AMS_HEADER_SIZE + length]
    return pkt


def build_tcp_frame(ams_bytes):
    """Envuelve una cabecera AMS + datos en el frame AMS/TCP (6 + n bytes)."""
    return struct.pack("<HI", 0, len(ams_bytes)) + ams_bytes


def parse_tcp_frame_header(header6):
    """Devuelve (reserved, length) de una cabecera AMS/TCP de 6 bytes."""
    if len(header6) != TCP_HEADER_SIZE:
        raise ValueError("Cabecera AMS/TCP incompleta")
    reserved, length = struct.unpack("<HI", header6)
    return reserved, length


def send_all(sock, data):
    """Envía todos los bytes por un socket."""
    view = memoryview(data)
    while view:
        sent = sock.send(view)
        view = view[sent:]


def recv_exact(sock, length):
    """Recibe exactamente ``length`` bytes del socket.

    Lanza :class:`socket.timeout` si el socket tiene timeout y expira.
    Lanza :class:`ConnectionError` si la conexión se cierra antes de tiempo.
    """
    chunks = []
    remaining = length
    while remaining > 0:
        chunk = sock.recv(remaining)
        if not chunk:
            raise ConnectionError("Conexión cerrada por el servidor ADS")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def recv_packet(sock):
    """Lee un frame AMS/TCP completo y devuelve un :class:`AmsPacket`."""
    header = recv_exact(sock, TCP_HEADER_SIZE)
    _reserved, length = parse_tcp_frame_header(header)
    if length < AMS_HEADER_SIZE:
        raise ValueError("Longitud AMS inválida: %d" % length)
    body = recv_exact(sock, length)
    return decode_ams_packet(body)

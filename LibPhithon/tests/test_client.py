"""Pruebas de integración del AdsClient contra un mini servidor ADS en hilo."""

import socket
import struct
import threading
import unittest

from ads import AdsClient, AdsError, constants as C
from ads.packet import AmsPacket, build_tcp_frame, encode_ams_packet, recv_packet, send_all


def make_response(request, data=b"", error=0):
    resp = AmsPacket()
    resp.target_netid = request.source_netid
    resp.target_port = request.source_port
    resp.source_netid = request.target_netid
    resp.source_port = request.target_port
    resp.command_id = request.command_id
    resp.state_flags = 1
    resp.error_code = error
    resp.invoke_id = request.invoke_id
    resp.data = data
    return resp


class MiniAdsServer:
    """Servidor ADS mínimo para pruebas (imagen de proceso + símbolos)."""

    def __init__(self):
        self.vars = {
            "MAIN.nCounter": struct.pack("<H", 0),
            "MAIN.fTemp": struct.pack("<f", 21.5),
        }
        self.sock = socket.socket()
        self.sock.bind(("127.0.0.1", 0))
        self.sock.listen(5)
        self.port = self.sock.getsockname()[1]
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def _run(self):
        self.sock.settimeout(0.2)
        while not self._stop.is_set():
            try:
                conn, _addr = self.sock.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            threading.Thread(target=self._serve, args=(conn,), daemon=True).start()

    def _serve(self, conn):
        try:
            while True:
                pkt = recv_packet(conn)
                self._handle(conn, pkt)
        except (OSError, ConnectionError, ValueError):
            pass
        finally:
            try:
                conn.close()
            except OSError:
                pass

    def _send(self, conn, pkt, data=b"", error=0):
        send_all(conn, build_tcp_frame(encode_ams_packet(make_response(pkt, data, error))))

    def _handle(self, conn, pkt):
        cmd = pkt.command_id
        if cmd == C.ADS_CMD_READ_STATE:
            self._send(conn, pkt, struct.pack("<HH", 5, 0))
        elif cmd == C.ADS_CMD_READ_DEVICE_INFO:
            self._send(conn, pkt, b"\x03\x01\x00\x00" + b"MiniSim".ljust(16, b"\x00"))
        elif cmd == C.ADS_CMD_READ:
            self._handle_read(conn, pkt)
        elif cmd == C.ADS_CMD_WRITE:
            self._handle_write(conn, pkt)
        else:
            self._send(conn, pkt, b"", error=0x00000701)

    def _handle_read(self, conn, pkt):
        ig = struct.unpack("<I", pkt.data[0:4])[0]
        if ig == C.INDEXGROUP_SYM_VALBYNAME:
            name_len = struct.unpack("<I", pkt.data[8:12])[0]
            name = pkt.data[12 : 12 + name_len].decode("utf-8")
            size = struct.unpack("<I", pkt.data[12 + name_len : 16 + name_len])[0]
            value = self.vars.get(name, b"\x00" * size)[:size]
            self._send(conn, pkt, value)
        elif ig == C.INDEXGROUP_SYM_HNDBYNAME:
            self._send(conn, pkt, struct.pack("<I", 0x12345678))
        else:
            self._send(conn, pkt, b"", error=0x00000702)

    def _handle_write(self, conn, pkt):
        ig = struct.unpack("<I", pkt.data[0:4])[0]
        if ig == C.INDEXGROUP_SYM_VALBYNAME:
            name_len = struct.unpack("<I", pkt.data[8:12])[0]
            name = pkt.data[12 : 12 + name_len].decode("utf-8")
            data_len = struct.unpack("<I", pkt.data[12 + name_len : 16 + name_len])[0]
            value = pkt.data[16 + name_len : 16 + name_len + data_len]
            self.vars[name] = value
            self._send(conn, pkt)
        else:
            self._send(conn, pkt, b"", error=0x00000702)

    def close(self):
        self._stop.set()
        try:
            self.sock.close()
        except OSError:
            pass


class TestClient(unittest.TestCase):
    def setUp(self):
        self.server = MiniAdsServer()
        self.client = AdsClient(ip_address="127.0.0.1", tcp_port=self.server.port, timeout=2.0)
        self.client.open()

    def tearDown(self):
        self.client.close()
        self.server.close()

    def test_read_state(self):
        state, dev = self.client.read_state()
        self.assertEqual(state, 5)
        self.assertEqual(dev, 0)

    def test_read_device_info(self):
        major, minor, build, name = self.client.read_device_info()
        self.assertEqual((major, minor, name), (3, 1, "MiniSim"))

    def test_read_by_name(self):
        self.assertAlmostEqual(self.client.read_by_name("MAIN.fTemp", "REAL"), 21.5)

    def test_write_and_read(self):
        self.client.write_by_name("MAIN.nCounter", 42, "UINT")
        self.assertEqual(self.client.read_by_name("MAIN.nCounter", "UINT"), 42)

    def test_get_handle(self):
        self.assertEqual(self.client.get_handle("MAIN.iLevel"), 0x12345678)

    def test_invalid_index_group(self):
        with self.assertRaises(AdsError) as cm:
            self.client.read_index(0x9999, 0, 4)
        self.assertEqual(cm.exception.code, 0x00000702)


if __name__ == "__main__":
    unittest.main()

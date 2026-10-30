"""Pruebas de codificación de cabecera AMS y frame AMS/TCP."""

import unittest

from ads.ams_netid import AmsNetId
from ads.packet import (
    AmsPacket,
    build_tcp_frame,
    decode_ams_packet,
    encode_ams_packet,
    parse_tcp_frame_header,
)


class TestAmsNetId(unittest.TestCase):
    def test_roundtrip_str(self):
        nid = AmsNetId("192.168.0.1.1.1")
        self.assertEqual(str(nid), "192.168.0.1.1.1")
        self.assertEqual(bytes(nid), b"\xc0\xa8\x00\x01\x01\x01")

    def test_invalid(self):
        with self.assertRaises(ValueError):
            AmsNetId("1.2.3")
        with self.assertRaises(ValueError):
            AmsNetId("1.2.3.4.5.999")

    def test_empty(self):
        self.assertTrue(AmsNetId().is_empty())


class TestAmsPacket(unittest.TestCase):
    def test_header_roundtrip(self):
        pkt = AmsPacket()
        pkt.target_netid = AmsNetId("127.0.0.1.1.1")
        pkt.target_port = 851
        pkt.source_netid = AmsNetId("127.0.0.1.1.1")
        pkt.source_port = 1234
        pkt.command_id = 0x0002
        pkt.state_flags = 0
        pkt.error_code = 0
        pkt.invoke_id = 7
        pkt.data = b"hola"

        encoded = encode_ams_packet(pkt)
        self.assertEqual(len(encoded), 32 + 4)

        decoded = decode_ams_packet(encoded)
        self.assertEqual(decoded.command_id, 0x0002)
        self.assertEqual(decoded.invoke_id, 7)
        self.assertEqual(decoded.target_port, 851)
        self.assertEqual(decoded.source_port, 1234)
        self.assertEqual(decoded.data, b"hola")
        self.assertEqual(str(decoded.target_netid), "127.0.0.1.1.1")


class TestTcpFrame(unittest.TestCase):
    def test_frame_roundtrip(self):
        pkt = AmsPacket()
        pkt.data = b"\x01\x02\x03"
        frame = build_tcp_frame(encode_ams_packet(pkt))
        self.assertEqual(len(frame), 6 + 32 + 3)

        reserved, length = parse_tcp_frame_header(frame[:6])
        self.assertEqual(reserved, 0)
        self.assertEqual(length, 32 + 3)


if __name__ == "__main__":
    unittest.main()

"""Pruebas de codificación/decodificación de tipos PLC."""

import struct
import unittest

from ads import datatypes


class TestScalarTypes(unittest.TestCase):
    def test_bool(self):
        self.assertEqual(datatypes.encode_value(True, "BOOL"), b"\x01")
        self.assertEqual(datatypes.encode_value(False, "BOOL"), b"\x00")
        self.assertIs(datatypes.decode_value(b"\x01", "BOOL"), True)

    def test_ints(self):
        cases = [
            ("SINT", -5, 1),
            ("USINT", 250, 1),
            ("BYTE", 0xAB, 1),
            ("INT", -1234, 2),
            ("UINT", 40000, 2),
            ("WORD", 0xBEEF, 2),
            ("DINT", -2000000000, 4),
            ("UDINT", 4000000000, 4),
            ("LINT", -(2 ** 40), 8),
            ("ULINT", 2 ** 40, 8),
        ]
        for plc, value, size in cases:
            enc = datatypes.encode_value(value, plc)
            self.assertEqual(len(enc), size, plc)
            self.assertEqual(datatypes.decode_value(enc, plc), value, plc)

    def test_floats(self):
        self.assertEqual(len(datatypes.encode_value(1.5, "REAL")), 4)
        self.assertAlmostEqual(datatypes.decode_value(datatypes.encode_value(1.5, "REAL"), "REAL"), 1.5)
        self.assertEqual(len(datatypes.encode_value(1.5, "LREAL")), 8)
        self.assertAlmostEqual(datatypes.decode_value(datatypes.encode_value(1.5, "LREAL"), "LREAL"), 1.5)


class TestStrings(unittest.TestCase):
    def test_string(self):
        enc = datatypes.encode_value("Hola", "STRING(80)")
        self.assertEqual(len(enc), 81)
        self.assertEqual(enc[0], 4)
        self.assertEqual(datatypes.decode_value(enc, "STRING(80)"), "Hola")

    def test_wstring(self):
        enc = datatypes.encode_value("Hola", "WSTRING(80)")
        self.assertEqual(len(enc), 2 * 81)
        self.assertEqual(datatypes.decode_value(enc, "WSTRING(80)"), "Hola")


class TestArrays(unittest.TestCase):
    def test_array(self):
        enc = datatypes.encode_value([1, 2, 3, 4], "ARRAY[0..3] OF INT")
        self.assertEqual(len(enc), 8)
        self.assertEqual(datatypes.decode_value(enc, "ARRAY[0..3] OF INT"), [1, 2, 3, 4])
        self.assertEqual(datatypes.size_of("ARRAY[0..3] OF INT"), 8)

    def test_array_multidim(self):
        self.assertEqual(datatypes.size_of("ARRAY[0..1,0..2] OF BYTE"), 6)


if __name__ == "__main__":
    unittest.main()

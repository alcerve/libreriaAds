"""Codificación/decodificación de tipos de datos PLC (sección 7 del spec)."""

import re
import struct

# Tamaños de los tipos escalares
_SIZES = {
    "BOOL": 1,
    "SINT": 1,
    "USINT": 1,
    "BYTE": 1,
    "INT": 2,
    "UINT": 2,
    "WORD": 2,
    "DINT": 4,
    "UDINT": 4,
    "DWORD": 4,
    "REAL": 4,
    "TIME": 4,
    "TOD": 4,
    "DT": 4,
    "DATE": 4,
    "LINT": 8,
    "ULINT": 8,
    "LWORD": 8,
    "LREAL": 8,
}

# Formato struct por tipo escalar (None = caso especial BOOL)
_FORMATS = {
    "SINT": "b",
    "USINT": "B",
    "BYTE": "B",
    "INT": "h",
    "UINT": "H",
    "WORD": "H",
    "DINT": "i",
    "UDINT": "I",
    "DWORD": "I",
    "REAL": "f",
    "TIME": "I",
    "TOD": "I",
    "DT": "I",
    "DATE": "I",
    "LINT": "q",
    "ULINT": "Q",
    "LWORD": "Q",
    "LREAL": "d",
}

_STRING_RE = re.compile(r"^\s*STRING\s*\((\d+)\)\s*$", re.IGNORECASE)
_WSTRING_RE = re.compile(r"^\s*WSTRING\s*\((\d+)\)\s*$", re.IGNORECASE)
_ARRAY_RE = re.compile(r"^\s*ARRAY\s*\[([^\]]*)\]\s+OF\s+(.+?)\s*$", re.IGNORECASE)


def _array_count(bounds_spec):
    """Devuelve el número de elementos de una declaración de bounds de array."""
    count = 1
    for part in bounds_spec.split(","):
        part = part.strip()
        match = re.match(r"^(-?\d+)\s*\.\.\s*(-?\d+)$", part)
        if not match:
            raise ValueError("Bounds de array no soportados: %r" % bounds_spec)
        lo, hi = int(match.group(1)), int(match.group(2))
        count *= (hi - lo + 1)
    return count


def _base_and_count(plc_type):
    """Devuelve (tipo_base, nº_elementos) para un tipo PLC (escalar o array)."""
    t = str(plc_type).strip()
    up = t.upper()
    if up in _SIZES:
        return up, 1
    if _STRING_RE.match(t) or _WSTRING_RE.match(t):
        return t, 1
    match = _ARRAY_RE.match(t)
    if match:
        count = _array_count(match.group(1))
        return match.group(2), count
    raise ValueError("Tipo PLC no soportado: %r" % t)


def size_of(plc_type):
    """Tamaño en bytes del valor codificado de un tipo PLC."""
    t = str(plc_type).strip()
    up = t.upper()
    if up in _SIZES:
        return _SIZES[up]
    match = _STRING_RE.match(t)
    if match:
        return int(match.group(1)) + 1
    match = _WSTRING_RE.match(t)
    if match:
        return 2 * (int(match.group(1)) + 1)
    match = _ARRAY_RE.match(t)
    if match:
        count = _array_count(match.group(1))
        return count * size_of(match.group(2))
    raise ValueError("Tipo PLC no soportado: %r" % t)


def encode_value(value, plc_type):
    """Codifica un valor Python a bytes según el tipo PLC."""
    t = str(plc_type).strip()
    up = t.upper()

    if up == "BOOL":
        return b"\x01" if value else b"\x00"

    if up in _FORMATS:
        return struct.pack("<" + _FORMATS[up], value)

    match = _STRING_RE.match(t)
    if match:
        n = int(match.group(1))
        content = str(value).encode("ascii", "replace")[:n]
        return struct.pack("<B", len(content)) + content.ljust(n, b"\x00")

    match = _WSTRING_RE.match(t)
    if match:
        n = int(match.group(1))
        content = str(value).encode("utf-16-le", "replace")[: 2 * n]
        return struct.pack("<H", len(content) // 2) + content.ljust(2 * n, b"\x00")

    match = _ARRAY_RE.match(t)
    if match:
        base_type = match.group(2)
        out = bytearray()
        for item in value:
            out += encode_value(item, base_type)
        return bytes(out)

    raise ValueError("Tipo PLC no soportado: %r" % t)


def decode_value(data, plc_type):
    """Decodifica bytes a un valor Python según el tipo PLC."""
    t = str(plc_type).strip()
    up = t.upper()

    if up == "BOOL":
        return bool(data[0])

    if up in _FORMATS:
        return struct.unpack("<" + _FORMATS[up], data[: struct.calcsize("<" + _FORMATS[up])])[0]

    match = _STRING_RE.match(t)
    if match:
        n = int(match.group(1))
        length = data[0]
        return data[1 : 1 + min(length, n)].decode("ascii", "replace")

    match = _WSTRING_RE.match(t)
    if match:
        n = int(match.group(1))
        length = struct.unpack("<H", data[:2])[0]
        return data[2 : 2 + 2 * min(length, n)].decode("utf-16-le", "replace")

    match = _ARRAY_RE.match(t)
    if match:
        base_type = match.group(2)
        elem_size = size_of(base_type)
        items = []
        for i in range(0, len(data) - elem_size + 1, elem_size):
            items.append(decode_value(data[i : i + elem_size], base_type))
        return items

    raise ValueError("Tipo PLC no soportado: %r" % t)

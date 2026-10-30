"""AmsNetId: identificador de red AMS de 6 bytes."""


class AmsNetId:
    """Identificador de red AMS (6 bytes), representado como ``a.b.c.d.e.f``."""

    def __init__(self, netid=None):
        if netid is None:
            self._bytes = bytearray(6)
        elif isinstance(netid, AmsNetId):
            self._bytes = bytearray(netid._bytes)
        elif isinstance(netid, str):
            self._bytes = self._parse(netid)
        elif isinstance(netid, (bytes, bytearray)):
            if len(netid) != 6:
                raise ValueError("AmsNetId debe tener exactamente 6 bytes")
            self._bytes = bytearray(netid)
        else:
            raise TypeError("AmsNetId inválido: %r" % (netid,))

    @staticmethod
    def _parse(text):
        parts = text.split(".")
        if len(parts) != 6:
            raise ValueError("AmsNetId debe tener el formato a.b.c.d.e.f: %r" % text)
        out = bytearray()
        for part in parts:
            value = int(part)
            if not 0 <= value <= 255:
                raise ValueError("Cada octeto del AmsNetId debe estar entre 0 y 255")
            out.append(value)
        return out

    def __bytes__(self):
        return bytes(self._bytes)

    def to_bytes(self):
        return bytes(self._bytes)

    def __str__(self):
        return ".".join(str(b) for b in self._bytes)

    def __repr__(self):
        return "AmsNetId('%s')" % str(self)

    def __eq__(self, other):
        if isinstance(other, AmsNetId):
            return bytes(self._bytes) == bytes(other._bytes)
        if isinstance(other, str):
            try:
                return bytes(self._bytes) == bytes(AmsNetId(other)._bytes)
            except (ValueError, TypeError):
                return False
        return NotImplemented

    def __hash__(self):
        return hash(bytes(self._bytes))

    def is_empty(self):
        return all(b == 0 for b in self._bytes)

"""AmsAddr: dirección AMS (NetId + puerto)."""

from .ams_netid import AmsNetId


class AmsAddr:
    """Dirección AMS formada por un :class:`AmsNetId` y un puerto."""

    def __init__(self, netid=None, port=0):
        if isinstance(netid, AmsNetId):
            self.netid = netid
        else:
            self.netid = AmsNetId(netid)
        self.port = int(port)

    def __repr__(self):
        return "AmsAddr(%s:%d)" % (self.netid, self.port)

    def __eq__(self, other):
        if not isinstance(other, AmsAddr):
            return NotImplemented
        return self.netid == other.netid and self.port == other.port

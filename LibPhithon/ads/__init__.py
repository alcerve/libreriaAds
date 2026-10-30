"""Librería cliente ADS (Beckhoff Automation Device Specification) en Python puro."""

from .ams_netid import AmsNetId
from .ams_addr import AmsAddr
from .errors import AdsError
from .client import AdsClient, SymbolInfo, NotificationSample
from . import constants
from . import datatypes

__version__ = "0.1.0"

__all__ = [
    "AdsClient",
    "AmsNetId",
    "AmsAddr",
    "AdsError",
    "SymbolInfo",
    "NotificationSample",
    "constants",
    "datatypes",
]

"""Constantes del protocolo ADS (Beckhoff Automation Device Specification)."""

# ---------------------------------------------------------------------------
# Comandos ADS (campo command_id de la cabecera AMS)
# ---------------------------------------------------------------------------
ADS_CMD_INVALID = 0x0000
ADS_CMD_READ_DEVICE_INFO = 0x0001
ADS_CMD_READ = 0x0002
ADS_CMD_WRITE = 0x0003
ADS_CMD_READ_STATE = 0x0004
ADS_CMD_WRITE_CONTROL = 0x0005
ADS_CMD_ADD_DEVICE_NOTIFICATION = 0x0006
ADS_CMD_DEL_DEVICE_NOTIFICATION = 0x0007
ADS_CMD_DEVICE_NOTIFICATION = 0x0008
ADS_CMD_READ_WRITE = 0x0009

# ---------------------------------------------------------------------------
# Grupos de índice
# ---------------------------------------------------------------------------
INDEXGROUP_SYMTAB = 0xF000
INDEXGROUP_SYMNAME = 0xF001
INDEXGROUP_SYMVAL = 0xF002
INDEXGROUP_SYM_HNDBYNAME = 0xF003
INDEXGROUP_SYM_VALBYHND = 0xF004
INDEXGROUP_SYM_VALBYNAME = 0xF005
INDEXGROUP_SYM_INFOBYNAME = 0xF006
INDEXGROUP_SYM_VERSION = 0xF007
INDEXGROUP_SYM_INFOBYNAMEEX = 0xF008
INDEXGROUP_SYM_DOWNLOAD = 0xF009
INDEXGROUP_SYM_RELEASEHND = 0xF014
INDEXGROUP_IOIMAGE_RWIB = 0xF020
INDEXGROUP_IOIMAGE_RWIX = 0xF021
INDEXGROUP_IOIMAGE_RISIZE = 0xF025
INDEXGROUP_IOIMAGE_RWOB = 0xF030
INDEXGROUP_IOIMAGE_RWOX = 0xF031
INDEXGROUP_SUMUP_READ = 0xF080
INDEXGROUP_SUMUP_WRITE = 0xF081
INDEXGROUP_SUMUP_READWRITE = 0xF082
INDEXGROUP_SUMUP_READEX = 0xF083
INDEXGROUP_DEVICE_DATA = 0xF100

# ---------------------------------------------------------------------------
# Puertos AMS habituales
# ---------------------------------------------------------------------------
PORT_LOGGER = 100
PORT_EVENTLOG = 300
PORT_IO = 400
PORT_NC = 500
PORT_PLC = 800
PORT_PLC_TC2 = 801
PORT_PLC_TC3 = 851
PORT_PLC_TC4 = 852
PORT_PLC_TC5 = 853
PORT_SYSTEM_SERVICE = 10000

# Puerto TCP estándar de AMS/TCP
AMS_TCP_PORT = 48898

# ---------------------------------------------------------------------------
# Estados del dispositivo
# ---------------------------------------------------------------------------
ADSSTATE_INVALID = 0
ADSSTATE_IDLE = 1
ADSSTATE_RESET = 2
ADSSTATE_INIT = 3
ADSSTATE_START = 4
ADSSTATE_RUN = 5
ADSSTATE_STOP = 6
ADSSTATE_SAVECFG = 7
ADSSTATE_LOADCFG = 8
ADSSTATE_POWERFAILURE = 9
ADSSTATE_POWERGOOD = 10
ADSSTATE_ERROR = 11
ADSSTATE_SHUTDOWN = 12
ADSSTATE_SUSPEND = 13
ADSSTATE_RESUME = 14
ADSSTATE_CONFIG = 15
ADSSTATE_RECONFIG = 16
ADSSTATE_STOPPING = 17
ADSSTATE_INCOMPATIBLE = 18
ADSSTATE_EXCEPTION = 19

# ---------------------------------------------------------------------------
# Modos de transmisión de notificación
# ---------------------------------------------------------------------------
ADSTRANS_NOTRANS = 0
ADSTRANS_CLIENTCYCLE = 1
ADSTRANS_CLIENTONCHA = 2
ADSTRANS_SERVERCYCLE = 3
ADSTRANS_SERVERONCHA = 4

# ---------------------------------------------------------------------------
# Identificadores de tipo de dato (campo data_type de la info de símbolo)
# ---------------------------------------------------------------------------
ADST_VOID = 0
ADST_INT8 = 1
ADST_UINT8 = 2
ADST_INT16 = 3
ADST_UINT16 = 4
ADST_INT32 = 5
ADST_UINT32 = 6
ADST_INT64 = 7
ADST_UINT64 = 8
ADST_REAL32 = 9
ADST_REAL64 = 10
ADST_STRING = 30
ADST_WSTRING = 31
ADST_REAL80 = 32
ADST_BIT = 33
ADST_MAXTYPES = 34
ADST_BIGTYPE = 65

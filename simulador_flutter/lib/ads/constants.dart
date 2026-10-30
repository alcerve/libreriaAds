/// Constantes del protocolo ADS (Beckhoff Automation Device Specification).
library;

class AdsCommand {
  static const int invalid = 0x0000;
  static const int readDeviceInfo = 0x0001;
  static const int read = 0x0002;
  static const int write = 0x0003;
  static const int readState = 0x0004;
  static const int writeControl = 0x0005;
  static const int addDeviceNotification = 0x0006;
  static const int delDeviceNotification = 0x0007;
  static const int deviceNotification = 0x0008;
  static const int readWrite = 0x0009;
}

class AdsIndexGroup {
  static const int symTab = 0xF000;
  static const int symName = 0xF001;
  static const int symVal = 0xF002;
  static const int symHndByName = 0xF003;
  static const int symValByHnd = 0xF004;
  static const int symValByName = 0xF005;
  static const int symInfoByName = 0xF006;
  static const int symReleaseHnd = 0xF014;
  static const int ioImageRwIb = 0xF020;
  static const int ioImageRwOb = 0xF030;
  static const int sumUpRead = 0xF080;
  static const int sumUpWrite = 0xF081;
  static const int deviceData = 0xF100;
}

class AdsState {
  static const int invalid = 0;
  static const int idle = 1;
  static const int reset = 2;
  static const int init = 3;
  static const int start = 4;
  static const int run = 5;
  static const int stop = 6;
  static const int error = 11;
}

class AdsError {
  static const int noError = 0x00000000;
  static const int internalError = 0x00000001;
  static const int targetPortNotFound = 0x00000006;
  static const int targetMachineNotFound = 0x00000007;
  static const int unknownCommand = 0x00000008;
  static const int invalidAmsLength = 0x0000000E;
  static const int serviceNotSupported = 0x00000701;
  static const int invalidIndexGroup = 0x00000702;
  static const int invalidIndexOffset = 0x00000703;
  static const int readWriteNotPermitted = 0x00000704;
  static const int parameterSizeIncorrect = 0x00000705;
  static const int invalidParameterValue = 0x00000706;
  static const int notFound = 0x0000070C;
  static const int symbolNotFound = 0x00000710;
  static const int serverInvalidState = 0x00000712;
  static const int transModeNotSupported = 0x00000713;
  static const int invalidNotificationHandle = 0x00000714;
  static const int noNotificationSubscribed = 0x00000716;
  static const int timeoutElapsed = 0x00000745;
}

class AdsTransMode {
  static const int noTrans = 0;
  static const int clientCycle = 1;
  static const int clientOnChange = 2;
  static const int serverCycle = 3;
  static const int serverOnChange = 4;
}

class AdsPort {
  static const int plcTc3 = 851;
  static const int tcpPort = 48898;
}

/// Identificadores de tipo de dato (campo data_type de la info de símbolo).
int dataTypeIdFor(String plcType) {
  final t = plcType.trim().toUpperCase();
  if (t.startsWith('ARRAY')) return 65; // BIGTYPE
  if (t.startsWith('STRING')) return 30;
  if (t.startsWith('WSTRING')) return 31;
  switch (t) {
    case 'BOOL': return 33;
    case 'SINT': return 1;
    case 'USINT': case 'BYTE': return 2;
    case 'INT': return 3;
    case 'UINT': case 'WORD': return 4;
    case 'DINT': return 5;
    case 'UDINT': case 'DWORD': return 6;
    case 'LINT': return 7;
    case 'ULINT': case 'LWORD': return 8;
    case 'REAL': return 9;
    case 'LREAL': return 10;
    default: return 0;
  }
}

/// Estado del dispositivo PLC simulado: variables, imagen de proceso y notificaciones.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../ads/ams_header.dart';
import '../ads/constants.dart';
import '../ads/datatypes.dart';
import 'symbol_table.dart';

class NotificationSubscription {
  final int handle;
  final int indexGroup;
  final int indexOffset;
  final int cbLength;
  final int transMode;
  final int cycleTime;
  final Socket socket;
  final AmsNetId clientNetId;
  final int clientPort;
  Uint8List? lastValue;
  Timer? timer;

  NotificationSubscription({
    required this.handle,
    required this.indexGroup,
    required this.indexOffset,
    required this.cbLength,
    required this.transMode,
    required this.cycleTime,
    required this.socket,
    required this.clientNetId,
    required this.clientPort,
  });
}

class Device {
  int adsState = AdsState.run;
  int deviceState = 0;

  final AmsNetId netId;
  final int amsPort;
  final void Function(String) log;

  final SymbolTable symbols = SymbolTable();
  final Uint8List ioInput = Uint8List(1024);
  final Uint8List ioOutput = Uint8List(1024);
  final Map<int, NotificationSubscription> notifications = {};

  int _nextNotifHandle = 1;
  Timer? _counterTimer;

  Device({required this.netId, required this.amsPort, required this.log});

  void initSymbols() {
    var index = 1;
    void add(String name, String plcType, Object? initial) {
      final size = sizeOf(plcType);
      symbols.add(Symbol(name, plcType, size, index++, encodeValue(initial, plcType)));
    }

    add('MAIN.bStart', 'BOOL', false);
    add('MAIN.bStop', 'BOOL', true);
    add('MAIN.nCounter', 'UINT', 0);
    add('MAIN.iLevel', 'INT', 100);
    add('MAIN.fTemp', 'REAL', 21.5);
    add('MAIN.dPosition', 'LREAL', 1.2345);
    add('MAIN.sMessage', 'STRING(80)', 'Hola ADS');
    add('MAIN.arrValues', 'ARRAY[0..3] OF INT', [1, 2, 3, 4]);
  }

  /// Carga variables desde una lista de definiciones (mapas con `name`, `type`
  /// y `value`), reemplazando las actuales. Útil para simular las variables de
  /// un PLC real leyéndolas de un archivo JSON.
  void loadVariableDefinitions(List<dynamic> definitions) {
    symbols.byName.clear();
    symbols.byIndex.clear();
    symbols.byHandle.clear();

    var index = 1;
    var cargadas = 0;
    for (final def in definitions) {
      if (def is! Map) continue;
      final name = def['name'];
      final type = def['type'];
      if (name is! String || type is! String) continue;
      try {
        final size = sizeOf(type);
        final encoded = encodeValue(def['value'], type);
        symbols.add(Symbol(name, type, size, index++, encoded));
        cargadas++;
      } catch (e) {
        log('ERROR cargando variable "$name" ($type): $e');
      }
    }
    log('Variables cargadas: $cargadas');
  }

  void start() {
    _counterTimer?.cancel();
    _counterTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
  }

  void stop() {
    _counterTimer?.cancel();
    _counterTimer = null;
    for (final sub in notifications.values) {
      sub.timer?.cancel();
    }
  }

  void _tick() {
    if (adsState != AdsState.run) return;
    final counter = symbols.findByName('MAIN.nCounter');
    if (counter == null) return;
    final value = (decodeValue(counter.value, 'UINT') as int) + 1;
    counter.value = encodeValue(value & 0xffff, 'UINT');
    notifySymbolChanged(counter);
  }

  void notifySymbolChanged(Symbol symbol) {
    for (final sub in notifications.values) {
      if (_targetsSymbol(sub, symbol)) _deliverOnChange(sub, symbol);
    }
  }

  bool _targetsSymbol(NotificationSubscription sub, Symbol symbol) =>
      sub.indexGroup == AdsIndexGroup.symValByName && sub.indexOffset == symbol.indexOffset;

  int addNotification(
      Socket socket, AmsNetId clientNetId, int clientPort, int indexGroup, int indexOffset, Uint8List attrib) {
    final d = ByteData.sublistView(attrib);
    final cbLength = d.getUint32(0, Endian.little);
    final transMode = d.getUint32(4, Endian.little);
    final cycleTime = d.getUint32(12, Endian.little);

    final handle = _nextNotifHandle++;
    final sub = NotificationSubscription(
      handle: handle,
      indexGroup: indexGroup,
      indexOffset: indexOffset,
      cbLength: cbLength,
      transMode: transMode,
      cycleTime: cycleTime,
      socket: socket,
      clientNetId: clientNetId,
      clientPort: clientPort,
    );
    notifications[handle] = sub;

    if (transMode == AdsTransMode.serverCycle || transMode == AdsTransMode.clientCycle) {
      final ms = (cycleTime / 10000.0).ceil().clamp(10, 100000);
      sub.timer = Timer.periodic(Duration(milliseconds: ms), (_) => _deliverCycle(sub));
    }
    return handle;
  }

  bool removeNotification(int handle) {
    final sub = notifications.remove(handle);
    sub?.timer?.cancel();
    return sub != null;
  }

  Uint8List? _ioBufferFor(int indexGroup) {
    if (indexGroup == AdsIndexGroup.ioImageRwIb) return ioInput;
    if (indexGroup == AdsIndexGroup.ioImageRwOb) return ioOutput;
    return null;
  }

  void _deliverOnChange(NotificationSubscription sub, Symbol symbol) {
    if (sub.transMode == AdsTransMode.clientCycle || sub.transMode == AdsTransMode.serverCycle) return;
    final sample = _sample(sub, symbol.value);
    if (sub.lastValue != null && _bytesEqual(sub.lastValue!, sample)) return;
    sub.lastValue = Uint8List.fromList(sample);
    _sendStamp(sub, sample);
  }

  void _deliverCycle(NotificationSubscription sub) {
    final symbol = symbols.findByIndex(sub.indexOffset);
    final current = symbol?.value ?? _ioBufferFor(sub.indexGroup) ?? Uint8List(0);
    _sendStamp(sub, _sample(sub, current));
  }

  Uint8List _sample(NotificationSubscription sub, Uint8List current) {
    final length = sub.cbLength > current.length ? current.length : sub.cbLength;
    return Uint8List.sublistView(current, 0, length);
  }

  void _sendStamp(NotificationSubscription sub, Uint8List sample) {
    final body = Uint8List(16 + sample.length);
    final stampHeader = ByteData.sublistView(body, 0, 16);
    stampHeader.setUint32(0, sub.handle, Endian.little);
    stampHeader.setUint64(4, _filetimeNow(), Endian.little);
    stampHeader.setUint32(12, sample.length, Endian.little);
    body.setRange(16, 16 + sample.length, sample);

    final data = Uint8List(4 + body.length);
    final lenHeader = ByteData.sublistView(data, 0, 4);
    lenHeader.setUint32(0, body.length, Endian.little);
    data.setRange(4, 4 + body.length, body);

    final header = AmsHeader()
      ..targetNetId = sub.clientNetId
      ..targetPort = sub.clientPort
      ..sourceNetId = netId
      ..sourcePort = amsPort
      ..commandId = AdsCommand.deviceNotification
      ..stateFlags = 4
      ..invokeId = 0
      ..data = data;

    try {
      sub.socket.add(buildTcpFrame(header.encode()));
    } catch (_) {
      sub.timer?.cancel();
      notifications.remove(sub.handle);
    }
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  int _filetimeNow() {
    final micros = DateTime.now().toUtc().microsecondsSinceEpoch;
    const epochDiffMicros = 11644473600000000; // 1601-01-01 -> 1970-01-01
    return (micros + epochDiffMicros) * 10;
  }
}

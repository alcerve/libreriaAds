// Cliente ADS en Dart (para el modo "PLC Real" del simulador).
//
// Se conecta a un PLC real y permite leer/escribir variables por nombre.
// Reutiliza las primitivas de ams_header.dart (cabecera AMS + frame AMS/TCP).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'ams_header.dart';
import 'constants.dart';

class AdsClient {
  final AmsNetId targetNetId;
  final int amsPort;
  final String ipAddress;
  final int tcpPort;
  final Duration timeout;

  Socket? _socket;
  final List<int> _buffer = [];
  final Map<int, Completer<AmsHeader>> _pending = {};
  int _invokeId = 0;
  final AmsNetId _localNetId = AmsNetId.fromString('127.0.0.1.1.1');
  int _localAmsPort = 30000;

  AdsClient({
    required this.targetNetId,
    required this.amsPort,
    required this.ipAddress,
    required this.tcpPort,
    this.timeout = const Duration(seconds: 3),
  });

  bool get isConnected => _socket != null;

  Future<void> connect() async {
    _socket = await Socket.connect(ipAddress, tcpPort);
    _socket!.listen(_onData, onError: (_) => _failAll(), onDone: _failAll);
  }

  void disconnect() {
    _failAll();
    _socket?.destroy();
    _socket = null;
    _buffer.clear();
  }

  void _failAll() {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(Exception('Conexión ADS cerrada'));
    }
    _pending.clear();
  }

  void _onData(Uint8List chunk) {
    _buffer.addAll(chunk);
    while (_buffer.length >= amsTcpHeaderSize) {
      final length = _u32(_buffer, 2);
      final total = amsTcpHeaderSize + length;
      if (_buffer.length < total) break;
      final frame = Uint8List.fromList(_buffer.sublist(0, total));
      _buffer.removeRange(0, total);
      final ams = AmsHeader.decode(Uint8List.sublistView(frame, amsTcpHeaderSize));
      final completer = _pending.remove(ams.invokeId);
      if (completer != null && !completer.isCompleted) {
        completer.complete(ams);
      }
    }
  }

  static int _u32(List<int> b, int o) =>
      (b[o] & 0xff) | ((b[o + 1] & 0xff) << 8) | ((b[o + 2] & 0xff) << 16) | ((b[o + 3] & 0xff) << 24);

  Future<AmsHeader> _request(int commandId, Uint8List data) async {
    final socket = _socket;
    if (socket == null) throw Exception('ADS: no conectado');
    final invokeId = ++_invokeId;
    final header = AmsHeader()
      ..targetNetId = targetNetId
      ..targetPort = amsPort
      ..sourceNetId = _localNetId
      ..sourcePort = _localAmsPort
      ..commandId = commandId
      ..stateFlags = 0
      ..invokeId = invokeId
      ..data = data;

    final completer = Completer<AmsHeader>();
    _pending[invokeId] = completer;
    socket.add(buildTcpFrame(header.encode()));

    final resp = await completer.future.timeout(timeout, onTimeout: () {
      _pending.remove(invokeId);
      throw TimeoutException('ADS: timeout');
    });
    if (resp.errorCode != 0) {
      throw Exception('ADS error 0x${resp.errorCode.toRadixString(16).padLeft(8, '0')}');
    }
    return resp;
  }

  /// Lee el estado del dispositivo: devuelve (adsState, deviceState).
  Future<(int, int)> readState() async {
    final resp = await _request(AdsCommand.readState, Uint8List(0));
    final d = resp.data;
    return (d[0] | (d[1] << 8), d[2] | (d[3] << 8));
  }

  /// Lee una variable por nombre (SYM_VALBYNAME). Devuelve los bytes crudos.
  Future<Uint8List> readByName(String name, int size) async {
    final nb = Uint8List.fromList(utf8.encode(name));
    final payload = Uint8List(12 + nb.length + 4);
    final d = ByteData.sublistView(payload);
    d.setUint32(0, AdsIndexGroup.symValByName, Endian.little);
    d.setUint32(4, 0, Endian.little);
    d.setUint32(8, nb.length, Endian.little);
    payload.setRange(12, 12 + nb.length, nb);
    d.setUint32(12 + nb.length, size, Endian.little);
    final resp = await _request(AdsCommand.read, payload);
    return resp.data;
  }

  /// Escribe una variable por nombre (SYM_VALBYNAME).
  Future<void> writeByName(String name, Uint8List value) async {
    final nb = Uint8List.fromList(utf8.encode(name));
    final payload = Uint8List(12 + nb.length + 4 + value.length);
    final d = ByteData.sublistView(payload);
    d.setUint32(0, AdsIndexGroup.symValByName, Endian.little);
    d.setUint32(4, 0, Endian.little);
    d.setUint32(8, nb.length, Endian.little);
    payload.setRange(12, 12 + nb.length, nb);
    d.setUint32(12 + nb.length, value.length, Endian.little);
    payload.setRange(16 + nb.length, 16 + nb.length + value.length, value);
    await _request(AdsCommand.write, payload);
  }

  /// Consulta el tamaño en bytes de un símbolo por su nombre (SYM_INFOBYNAME).
  Future<int> symbolSize(String name) async {
    final nb = Uint8List.fromList(utf8.encode(name));
    final payload = Uint8List(12 + nb.length);
    final d = ByteData.sublistView(payload);
    d.setUint32(0, AdsIndexGroup.symInfoByName, Endian.little);
    d.setUint32(4, 0, Endian.little);
    d.setUint32(8, nb.length, Endian.little);
    payload.setRange(12, 12 + nb.length, nb);
    final resp = await _request(AdsCommand.read, payload);
    final data = resp.data;
    // La estructura AdsSymbolInfo tiene el tamaño en el offset 8 (uint32 LE).
    return (data[8] & 0xff) | ((data[9] & 0xff) << 8) | ((data[10] & 0xff) << 16) | ((data[11] & 0xff) << 24);
  }
}

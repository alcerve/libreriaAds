/// Servidor ADS sobre TCP: parsea solicitudes y genera respuestas.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../ads/ams_header.dart';
import '../ads/constants.dart';
import 'device.dart';
import 'symbol_table.dart';
import 'trama.dart';

class AdsServer {
  final Device device;
  final int tcpPort;
  ServerSocket? _server;

  bool get running => _server != null;

  AdsServer({required this.device, required this.tcpPort});

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, tcpPort);
    _server!.listen(_onConnection);
    device.log('Escuchando en 127.0.0.1:$tcpPort (NetId ${device.netId}, puerto AMS ${device.amsPort})');
  }

  Future<void> stop() async {
    device.stop();
    await _server?.close();
    _server = null;
  }

  Future<void> _onConnection(Socket socket) async {
    // La dirección se captura al inicio: tras close() el socket ya no es legible.
    final peer = '${socket.remoteAddress.address}:${socket.remotePort}';
    device.log('Conexión desde $peer');
    final buffer = <int>[];
    try {
      await for (final chunk in socket) {
        buffer.addAll(chunk);
        while (buffer.length >= amsTcpHeaderSize) {
          final length = _readU32(buffer, 2);
          final total = amsTcpHeaderSize + length;
          if (buffer.length < total) break;
          final frame = Uint8List.fromList(buffer.sublist(0, total));
          buffer.removeRange(0, total);
          socket.add(_handle(frame, socket));
        }
      }
    } catch (e) {
      device.log('Error de conexión ($peer): $e');
    } finally {
      // Elimina las notificaciones asociadas a este socket.
      final removed = device.notifications.keys
          .where((h) => device.notifications[h]?.socket == socket)
          .toList();
      for (final h in removed) {
        device.removeNotification(h);
      }
      try {
        await socket.close();
      } catch (_) {}
      device.log('Conexión cerrada desde $peer');
    }
  }

  static int _readU32(List<int> buffer, int offset) =>
      (buffer[offset] & 0xff) |
      ((buffer[offset + 1] & 0xff) << 8) |
      ((buffer[offset + 2] & 0xff) << 16) |
      ((buffer[offset + 3] & 0xff) << 24);

  Uint8List _handle(Uint8List frame, Socket socket) {
    final amsBytes = Uint8List.sublistView(frame, amsTcpHeaderSize);
    final request = AmsHeader.decode(amsBytes);

    // Log de la trama recibida (hex + explicación campo a campo).
    device.log(explainFrame('RECIBIDO', frame));

    Uint8List response;
    switch (request.commandId) {
      case AdsCommand.readDeviceInfo:
        response = _readDeviceInfo(request);
        break;
      case AdsCommand.readState:
        response = _readState(request);
        break;
      case AdsCommand.writeControl:
        response = _writeControl(request);
        break;
      case AdsCommand.read:
        response = _read(request);
        break;
      case AdsCommand.write:
        response = _write(request);
        break;
      case AdsCommand.readWrite:
        response = _readWrite(request);
        break;
      case AdsCommand.addDeviceNotification:
        response = _addNotification(request, socket);
        break;
      case AdsCommand.delDeviceNotification:
        response = _delNotification(request);
        break;
      default:
        response = buildResponse(request, error: AdsError.unknownCommand);
        break;
    }

    // Log de la trama enviada como respuesta.
    device.log(explainFrame('ENVIADO', response));
    return response;
  }

  // ------------------------------------------------------------------ info
  Uint8List _readDeviceInfo(AmsHeader request) {
    final data = Uint8List(20);
    data[0] = 3; // major
    data[1] = 1; // minor
    data[2] = 0; // build (low)
    data[3] = 0; // build (high)
    const name = 'ADS-Simulator';
    for (var i = 0; i < name.length && i < 16; i++) {
      data[4 + i] = name.codeUnitAt(i);
    }
    return buildResponse(request, data: data);
  }

  Uint8List _readState(AmsHeader request) {
    final d = ByteData(4)
      ..setUint16(0, device.adsState, Endian.little)
      ..setUint16(2, device.deviceState, Endian.little);
    return buildResponse(request, data: d.buffer.asUint8List());
  }

  Uint8List _writeControl(AmsHeader request) {
    if (request.data.length < 4) {
      return buildResponse(request, error: AdsError.parameterSizeIncorrect);
    }
    final b = ByteData.sublistView(request.data);
    device.adsState = b.getUint16(0, Endian.little);
    device.deviceState = b.getUint16(2, Endian.little);
    device.log('WRITE_CONTROL -> estado ${device.adsState}');
    return buildResponse(request);
  }

  // ------------------------------------------------------------------ read
  Uint8List _read(AmsHeader request) {
    final data = request.data;
    if (data.length < 8) return buildResponse(request, error: AdsError.parameterSizeIncorrect);
    final b = ByteData.sublistView(data);
    final indexGroup = b.getUint32(0, Endian.little);

    switch (indexGroup) {
      case AdsIndexGroup.symValByName:
        return _readByName(request, data);
      case AdsIndexGroup.symValByHnd:
        return _readByHandle(request, data);
      case AdsIndexGroup.symHndByName:
        return _getHandle(request, data);
      case AdsIndexGroup.symInfoByName:
        return _symbolInfo(request, data);
      case AdsIndexGroup.symTab:
        return _symTab(request);
      case AdsIndexGroup.ioImageRwIb:
        return _readIo(request, data, device.ioInput);
      case AdsIndexGroup.ioImageRwOb:
        return _readIo(request, data, device.ioOutput);
      case AdsIndexGroup.sumUpRead:
        return _sumRead(request, data);
      default:
        return buildResponse(request, error: AdsError.invalidIndexGroup);
    }
  }

  Uint8List _readByName(AmsHeader request, Uint8List data) {
    final b = ByteData.sublistView(data);
    final nameLen = b.getUint32(8, Endian.little);
    final name = String.fromCharCodes(data.sublist(12, 12 + nameLen));
    final size = b.getUint32(12 + nameLen, Endian.little);
    final symbol = device.symbols.findByName(name);
    if (symbol == null) return buildResponse(request, error: AdsError.symbolNotFound);
    return buildResponse(request, data: _fit(symbol.value, size));
  }

  Uint8List _readByHandle(AmsHeader request, Uint8List data) {
    final b = ByteData.sublistView(data);
    final handle = b.getUint32(4, Endian.little);
    final size = b.getUint32(8, Endian.little);
    final symbol = device.symbols.findByHandle(handle);
    if (symbol == null) return buildResponse(request, error: AdsError.invalidIndexOffset);
    return buildResponse(request, data: _fit(symbol.value, size));
  }

  Uint8List _getHandle(AmsHeader request, Uint8List data) {
    final b = ByteData.sublistView(data);
    final nameLen = b.getUint32(8, Endian.little);
    final name = String.fromCharCodes(data.sublist(12, 12 + nameLen));
    final handle = device.symbols.createHandle(name);
    if (handle == 0) return buildResponse(request, error: AdsError.symbolNotFound);
    final d = ByteData(4)..setUint32(0, handle, Endian.little);
    return buildResponse(request, data: d.buffer.asUint8List());
  }

  Uint8List _symbolInfo(AmsHeader request, Uint8List data) {
    final b = ByteData.sublistView(data);
    final nameLen = b.getUint32(8, Endian.little);
    final name = String.fromCharCodes(data.sublist(12, 12 + nameLen));
    final symbol = device.symbols.findByName(name);
    if (symbol == null) return buildResponse(request, error: AdsError.symbolNotFound);

    final nameBytes = symbol.name.codeUnits;
    final typeBytes = symbol.plcType.codeUnits;
    final commentBytes = const <int>[];
    final size = 24 + nameBytes.length + typeBytes.length + commentBytes.length;
    final out = ByteData(size)
      ..setUint32(0, AdsIndexGroup.symValByName, Endian.little)
      ..setUint32(4, symbol.indexOffset, Endian.little)
      ..setUint32(8, symbol.size, Endian.little)
      ..setUint32(12, dataTypeIdFor(symbol.plcType), Endian.little)
      ..setUint16(16, 0, Endian.little)
      ..setUint16(18, nameBytes.length, Endian.little)
      ..setUint16(20, typeBytes.length, Endian.little)
      ..setUint16(22, commentBytes.length, Endian.little);

    final result = Uint8List(size);
    result.setRange(0, size, out.buffer.asUint8List(0, size));
    var offset = 24;
    result.setRange(offset, offset + nameBytes.length, nameBytes);
    offset += nameBytes.length;
    result.setRange(offset, offset + typeBytes.length, typeBytes);
    offset += typeBytes.length;
    result.setRange(offset, offset + commentBytes.length, commentBytes);
    return buildResponse(request, data: result);
  }

  Uint8List _symTab(AmsHeader request) {
    final builder = BytesBuilder();
    for (final symbol in device.symbols.byName.values) {
      final nameBytes = symbol.name.codeUnits;
      final typeBytes = symbol.plcType.codeUnits;
      final commentBytes = const <int>[];
      final entrySize = 34 + nameBytes.length + typeBytes.length + commentBytes.length;
      final entry = ByteData(entrySize)
        ..setUint32(0, entrySize, Endian.little)
        ..setUint32(4, AdsIndexGroup.symValByName, Endian.little)
        ..setUint32(8, symbol.indexOffset, Endian.little)
        ..setUint32(12, symbol.size, Endian.little)
        ..setUint32(16, dataTypeIdFor(symbol.plcType), Endian.little)
        ..setUint16(20, 0, Endian.little)
        ..setUint16(22, nameBytes.length, Endian.little)
        ..setUint16(24, typeBytes.length, Endian.little)
        ..setUint16(26, commentBytes.length, Endian.little);
      final bytes = Uint8List(entrySize);
      bytes.setRange(0, entrySize, entry.buffer.asUint8List(0, entrySize));
      var offset = 28;
      bytes.setRange(offset, offset + nameBytes.length, nameBytes);
      offset += nameBytes.length;
      bytes.setRange(offset, offset + typeBytes.length, typeBytes);
      offset += typeBytes.length;
      bytes.setRange(offset, offset + commentBytes.length, commentBytes);
      builder.add(bytes);
    }
    return buildResponse(request, data: builder.toBytes());
  }

  Uint8List _readIo(AmsHeader request, Uint8List data, Uint8List image) {
    final b = ByteData.sublistView(data);
    final offset = b.getUint32(4, Endian.little);
    final size = b.getUint32(8, Endian.little);
    if (offset + size > image.length) return buildResponse(request, error: AdsError.invalidIndexOffset);
    return buildResponse(request, data: Uint8List.sublistView(image, offset, offset + size));
  }

  // ------------------------------------------------------------------ write
  Uint8List _write(AmsHeader request) {
    final data = request.data;
    if (data.length < 8) return buildResponse(request, error: AdsError.parameterSizeIncorrect);
    final b = ByteData.sublistView(data);
    final indexGroup = b.getUint32(0, Endian.little);

    switch (indexGroup) {
      case AdsIndexGroup.symValByName:
        return _writeByName(request, data);
      case AdsIndexGroup.symValByHnd:
        return _writeByHandle(request, data);
      case AdsIndexGroup.symReleaseHnd:
        return _releaseHandle(request, data);
      case AdsIndexGroup.ioImageRwIb:
        return _writeIo(request, data, device.ioInput);
      case AdsIndexGroup.ioImageRwOb:
        return _writeIo(request, data, device.ioOutput);
      case AdsIndexGroup.sumUpWrite:
        return _sumWrite(request, data);
      default:
        return buildResponse(request, error: AdsError.invalidIndexGroup);
    }
  }

  Uint8List _writeByName(AmsHeader request, Uint8List data) {
    final b = ByteData.sublistView(data);
    final nameLen = b.getUint32(8, Endian.little);
    final name = String.fromCharCodes(data.sublist(12, 12 + nameLen));
    final valueLen = b.getUint32(12 + nameLen, Endian.little);
    final value = Uint8List.sublistView(data, 16 + nameLen, 16 + nameLen + valueLen);
    final symbol = device.symbols.findByName(name);
    if (symbol == null) return buildResponse(request, error: AdsError.symbolNotFound);
    symbol.value = Uint8List.fromList(value);
    device.notifySymbolChanged(symbol);
    return buildResponse(request);
  }

  Uint8List _writeByHandle(AmsHeader request, Uint8List data) {
    final b = ByteData.sublistView(data);
    final handle = b.getUint32(4, Endian.little);
    final valueLen = b.getUint32(8, Endian.little);
    final value = Uint8List.sublistView(data, 12, 12 + valueLen);
    final symbol = device.symbols.findByHandle(handle);
    if (symbol == null) return buildResponse(request, error: AdsError.invalidIndexOffset);
    symbol.value = Uint8List.fromList(value);
    device.notifySymbolChanged(symbol);
    return buildResponse(request);
  }

  Uint8List _releaseHandle(AmsHeader request, Uint8List data) {
    final b = ByteData.sublistView(data);
    final handle = b.getUint32(4, Endian.little);
    device.symbols.releaseHandle(handle);
    return buildResponse(request);
  }

  Uint8List _writeIo(AmsHeader request, Uint8List data, Uint8List image) {
    final b = ByteData.sublistView(data);
    final offset = b.getUint32(4, Endian.little);
    final valueLen = b.getUint32(8, Endian.little);
    final value = Uint8List.sublistView(data, 12, 12 + valueLen);
    if (offset + valueLen > image.length) return buildResponse(request, error: AdsError.invalidIndexOffset);
    image.setRange(offset, offset + valueLen, value);
    return buildResponse(request);
  }

  // ------------------------------------------------------------------ read/write
  Uint8List _readWrite(AmsHeader request) {
    final data = request.data;
    if (data.length < 16) return buildResponse(request, error: AdsError.parameterSizeIncorrect);
    final b = ByteData.sublistView(data);
    final indexGroup = b.getUint32(0, Endian.little);
    final indexOffset = b.getUint32(4, Endian.little);
    final readLength = b.getUint32(8, Endian.little);
    final writeLength = b.getUint32(12, Endian.little);
    final writeData = Uint8List.sublistView(data, 16, 16 + writeLength);

    final writeResult = _writeDirect(indexGroup, indexOffset, writeData);
    if (writeResult != AdsError.noError) return buildResponse(request, error: writeResult);
    final (readResult, value) = _readDirect(indexGroup, indexOffset, readLength);
    if (readResult != AdsError.noError) return buildResponse(request, error: readResult);
    return buildResponse(request, data: value);
  }

  // ------------------------------------------------------------------ sum
  Uint8List _sumRead(AmsHeader request, Uint8List data) {
    final b = ByteData.sublistView(data);
    final bodyLength = b.getUint32(8, Endian.little);
    final entries = Uint8List.sublistView(data, 12, 12 + bodyLength);
    final builder = BytesBuilder();
    var offset = 0;
    while (offset + 12 <= entries.length) {
      final e = ByteData.sublistView(entries, offset, offset + 12);
      final indexGroup = e.getUint32(0, Endian.little);
      final indexOffset = e.getUint32(4, Endian.little);
      final length = e.getUint32(8, Endian.little);
      offset += 12;
      final (result, value) = _readDirect(indexGroup, indexOffset, length);
      final head = ByteData(8)
        ..setUint32(0, result, Endian.little)
        ..setUint32(4, value.length, Endian.little);
      builder.add(head.buffer.asUint8List());
      builder.add(value);
    }
    return buildResponse(request, data: builder.toBytes());
  }

  Uint8List _sumWrite(AmsHeader request, Uint8List data) {
    final b = ByteData.sublistView(data);
    final bodyLength = b.getUint32(8, Endian.little);
    final entries = Uint8List.sublistView(data, 12, 12 + bodyLength);
    final builder = BytesBuilder();
    var offset = 0;
    while (offset + 12 <= entries.length) {
      final e = ByteData.sublistView(entries, offset, offset + 12);
      final indexGroup = e.getUint32(0, Endian.little);
      final indexOffset = e.getUint32(4, Endian.little);
      final length = e.getUint32(8, Endian.little);
      offset += 12;
      final value = Uint8List.sublistView(entries, offset, offset + length);
      offset += length;
      final result = _writeDirect(indexGroup, indexOffset, value);
      final head = ByteData(4)..setUint32(0, result, Endian.little);
      builder.add(head.buffer.asUint8List());
    }
    return buildResponse(request, data: builder.toBytes());
  }

  (int, Uint8List) _readDirect(int indexGroup, int indexOffset, int length) {
    if (indexGroup == AdsIndexGroup.symValByName) {
      final symbol = device.symbols.findByIndex(indexOffset);
      if (symbol == null) return (AdsError.symbolNotFound, Uint8List(0));
      return (AdsError.noError, _fit(symbol.value, length));
    }
    if (indexGroup == AdsIndexGroup.ioImageRwIb || indexGroup == AdsIndexGroup.ioImageRwOb) {
      final image = indexGroup == AdsIndexGroup.ioImageRwIb ? device.ioInput : device.ioOutput;
      if (indexOffset + length > image.length) return (AdsError.invalidIndexOffset, Uint8List(0));
      return (AdsError.noError, Uint8List.sublistView(image, indexOffset, indexOffset + length));
    }
    return (AdsError.invalidIndexGroup, Uint8List(0));
  }

  int _writeDirect(int indexGroup, int indexOffset, Uint8List value) {
    if (indexGroup == AdsIndexGroup.symValByName) {
      final symbol = device.symbols.findByIndex(indexOffset);
      if (symbol == null) return AdsError.symbolNotFound;
      symbol.value = Uint8List.fromList(value);
      device.notifySymbolChanged(symbol);
      return AdsError.noError;
    }
    if (indexGroup == AdsIndexGroup.ioImageRwIb || indexGroup == AdsIndexGroup.ioImageRwOb) {
      final image = indexGroup == AdsIndexGroup.ioImageRwIb ? device.ioInput : device.ioOutput;
      if (indexOffset + value.length > image.length) return AdsError.invalidIndexOffset;
      image.setRange(indexOffset, indexOffset + value.length, value);
      return AdsError.noError;
    }
    return AdsError.invalidIndexGroup;
  }

  // ------------------------------------------------------------------ notificaciones
  Uint8List _addNotification(AmsHeader request, Socket socket) {
    final data = request.data;
    if (data.length < 32) return buildResponse(request, error: AdsError.parameterSizeIncorrect);
    final b = ByteData.sublistView(data);
    final indexGroup = b.getUint32(0, Endian.little);
    final indexOffset = b.getUint32(4, Endian.little);
    final attrib = Uint8List.sublistView(data, 8);
    final handle = device.addNotification(
        socket, request.sourceNetId, request.sourcePort, indexGroup, indexOffset, attrib);
    final d = ByteData(4)..setUint32(0, handle, Endian.little);
    return buildResponse(request, data: d.buffer.asUint8List());
  }

  Uint8List _delNotification(AmsHeader request) {
    final data = request.data;
    if (data.length < 4) return buildResponse(request, error: AdsError.parameterSizeIncorrect);
    final b = ByteData.sublistView(data);
    final handle = b.getUint32(0, Endian.little);
    if (!device.removeNotification(handle)) {
      return buildResponse(request, error: AdsError.invalidNotificationHandle);
    }
    return buildResponse(request);
  }

  // ------------------------------------------------------------------ helpers
  static Uint8List _fit(Uint8List source, int size) {
    if (source.length == size) return source;
    final result = Uint8List(size);
    final n = source.length < size ? source.length : size;
    result.setRange(0, n, source);
    return result;
  }
}

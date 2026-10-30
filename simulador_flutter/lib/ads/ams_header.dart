/// Codificación/decodificación del frame AMS/TCP y de la cabecera AMS.
library;

import 'dart:typed_data';

const int amsTcpHeaderSize = 6;
const int amsHeaderSize = 32;

class AmsNetId {
  final Uint8List bytes;

  AmsNetId(this.bytes) {
    if (bytes.length != 6) {
      throw ArgumentError('AmsNetId debe tener exactamente 6 bytes');
    }
  }

  factory AmsNetId.fromString(String value) {
    final parts = value.split('.');
    if (parts.length != 6) {
      throw FormatException('AmsNetId inválido: $value');
    }
    return AmsNetId(Uint8List.fromList(parts.map((p) => int.parse(p)).toList()));
  }

  factory AmsNetId.empty() => AmsNetId(Uint8List(6));

  bool get isEmpty => bytes.every((b) => b == 0);

  @override
  String toString() => bytes.join('.');
}

class AmsHeader {
  AmsNetId targetNetId = AmsNetId.empty();
  int targetPort = 0;
  AmsNetId sourceNetId = AmsNetId.empty();
  int sourcePort = 0;
  int commandId = 0;
  int stateFlags = 0;
  int errorCode = 0;
  int invokeId = 0;
  Uint8List data = Uint8List(0);

  Uint8List encode() {
    final header = ByteData(amsHeaderSize);
    _writeNetId(header, 0, targetNetId);
    header.setUint16(6, targetPort, Endian.little);
    _writeNetId(header, 8, sourceNetId);
    header.setUint16(14, sourcePort, Endian.little);
    header.setUint16(16, commandId, Endian.little);
    header.setUint16(18, stateFlags, Endian.little);
    header.setUint32(20, data.length, Endian.little);
    header.setUint32(24, errorCode, Endian.little);
    header.setUint32(28, invokeId, Endian.little);

    final result = Uint8List(amsHeaderSize + data.length);
    result.setRange(0, amsHeaderSize, header.buffer.asUint8List(0, amsHeaderSize));
    result.setRange(amsHeaderSize, amsHeaderSize + data.length, data);
    return result;
  }

  static AmsHeader decode(Uint8List bytes) {
    if (bytes.length < amsHeaderSize) {
      throw FormatException('Cabecera AMS incompleta');
    }
    final b = ByteData.sublistView(bytes);
    final h = AmsHeader();
    h.targetNetId = _readNetId(b, 0);
    h.targetPort = b.getUint16(6, Endian.little);
    h.sourceNetId = _readNetId(b, 8);
    h.sourcePort = b.getUint16(14, Endian.little);
    h.commandId = b.getUint16(16, Endian.little);
    h.stateFlags = b.getUint16(18, Endian.little);
    final length = b.getUint32(20, Endian.little);
    h.errorCode = b.getUint32(24, Endian.little);
    h.invokeId = b.getUint32(28, Endian.little);
    final end = (amsHeaderSize + length).clamp(0, bytes.length);
    h.data = Uint8List.sublistView(bytes, amsHeaderSize, end);
    return h;
  }

  static void _writeNetId(ByteData b, int offset, AmsNetId netId) {
    for (var i = 0; i < 6; i++) {
      b.setUint8(offset + i, netId.bytes[i]);
    }
  }

  static AmsNetId _readNetId(ByteData b, int offset) {
    return AmsNetId(Uint8List.fromList(List.generate(6, (i) => b.getUint8(offset + i))));
  }
}

/// Envuelve la cabecera AMS + datos en el frame AMS/TCP (6 + n bytes).
Uint8List buildTcpFrame(Uint8List amsBytes) {
  final tcp = ByteData(amsTcpHeaderSize);
  tcp.setUint16(0, 0, Endian.little);
  tcp.setUint32(2, amsBytes.length, Endian.little);
  final result = Uint8List(amsTcpHeaderSize + amsBytes.length);
  result.setRange(0, amsTcpHeaderSize, tcp.buffer.asUint8List(0, amsTcpHeaderSize));
  result.setRange(amsTcpHeaderSize, amsTcpHeaderSize + amsBytes.length, amsBytes);
  return result;
}

/// Construye un frame de respuesta a partir de una petición recibida.
Uint8List buildResponse(AmsHeader request, {Uint8List? data, int error = 0, int stateFlags = 1}) {
  final header = AmsHeader()
    ..targetNetId = request.sourceNetId
    ..targetPort = request.sourcePort
    ..sourceNetId = request.targetNetId
    ..sourcePort = request.targetPort
    ..commandId = request.commandId
    ..stateFlags = stateFlags
    ..errorCode = error
    ..invokeId = request.invokeId
    ..data = data ?? Uint8List(0);
  return buildTcpFrame(header.encode());
}

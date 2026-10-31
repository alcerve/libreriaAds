/// Codificación/decodificación de tipos de datos PLC (sección 7 del PROTOCOL.md).
library;

import 'dart:typed_data';

const Map<String, int> _scalarSizes = {
  'BOOL': 1, 'SINT': 1, 'USINT': 1, 'BYTE': 1,
  'INT': 2, 'UINT': 2, 'WORD': 2,
  'DINT': 4, 'UDINT': 4, 'DWORD': 4, 'REAL': 4,
  'TIME': 4, 'TOD': 4, 'DT': 4, 'DATE': 4,
  'LINT': 8, 'ULINT': 8, 'LWORD': 8, 'LREAL': 8,
};

final RegExp _stringRe = RegExp(r'^STRING\((\d+)\)$');
final RegExp _wstringRe = RegExp(r'^WSTRING\((\d+)\)$');
final RegExp _arrayRe = RegExp(r'^ARRAY\s*\[([^\]]*)\]\s+OF\s+(.+)$');

int sizeOf(String plcType) {
  final t = plcType.trim().toUpperCase();
  final scalar = _scalarSizes[t];
  if (scalar != null) return scalar;
  final str = _stringRe.firstMatch(t);
  if (str != null) return int.parse(str.group(1)!) + 1;
  final wstr = _wstringRe.firstMatch(t);
  if (wstr != null) return 2 * (int.parse(wstr.group(1)!) + 1);
  final arr = _arrayRe.firstMatch(t);
  if (arr != null) return _arrayCount(arr.group(1)!) * sizeOf(arr.group(2)!);
  throw ArgumentError('Tipo PLC no soportado: $plcType');
}

int _arrayCount(String bounds) {
  var count = 1;
  for (final part in bounds.split(',')) {
    final m = RegExp(r'^(-?\d+)\s*\.\.\s*(-?\d+)$').firstMatch(part.trim());
    if (m == null) throw ArgumentError('Bounds de array no soportados: $bounds');
    count *= int.parse(m.group(2)!) - int.parse(m.group(1)!) + 1;
  }
  return count;
}

Uint8List encodeValue(Object? value, String plcType) {
  final t = plcType.trim().toUpperCase();

  if (t == 'BOOL') return Uint8List.fromList([value == true ? 1 : 0]);

  switch (t) {
    case 'SINT': return _s8((value as num).toInt());
    case 'USINT': case 'BYTE': return _u8((value as num).toInt());
    case 'INT': return _s16((value as num).toInt());
    case 'UINT': case 'WORD': return _u16((value as num).toInt());
    case 'DINT': return _s32((value as num).toInt());
    case 'UDINT': case 'DWORD': return _u32((value as num).toInt());
    case 'REAL': return _f32((value as num).toDouble());
    case 'TIME': case 'TOD': case 'DT': case 'DATE': return _u32((value as num).toInt());
    case 'LINT': return _s64((value as num).toInt());
    case 'ULINT': case 'LWORD': return _u64((value as num).toInt());
    case 'LREAL': return _f64((value as num).toDouble());
  }

  final str = _stringRe.firstMatch(t);
  if (str != null) return _encodeString(value.toString(), int.parse(str.group(1)!));

  final wstr = _wstringRe.firstMatch(t);
  if (wstr != null) return _encodeWString(value.toString(), int.parse(wstr.group(1)!));

  final arr = _arrayRe.firstMatch(t);
  if (arr != null && value is List) {
    final elemType = arr.group(2)!;
    final out = BytesBuilder();
    for (final item in value) {
      out.add(encodeValue(item, elemType));
    }
    return out.toBytes();
  }

  throw ArgumentError('Tipo PLC no soportado: $plcType');
}

Object? decodeValue(Uint8List data, String plcType) {
  final t = plcType.trim().toUpperCase();
  final b = ByteData.sublistView(data);

  if (t == 'BOOL') return data.isNotEmpty && data[0] != 0;

  switch (t) {
    case 'SINT': return b.getInt8(0);
    case 'USINT': case 'BYTE': return data[0];
    case 'INT': return b.getInt16(0, Endian.little);
    case 'UINT': case 'WORD': return b.getUint16(0, Endian.little);
    case 'DINT': return b.getInt32(0, Endian.little);
    case 'UDINT': case 'DWORD': return b.getUint32(0, Endian.little);
    case 'REAL': return b.getFloat32(0, Endian.little);
    case 'TIME': case 'TOD': case 'DT': case 'DATE': return b.getUint32(0, Endian.little);
    case 'LINT': return b.getInt64(0, Endian.little);
    case 'ULINT': case 'LWORD': return b.getUint64(0, Endian.little);
    case 'LREAL': return b.getFloat64(0, Endian.little);
  }

  final str = _stringRe.firstMatch(t);
  if (str != null) {
    final n = int.parse(str.group(1)!);
    final len = data.isNotEmpty ? data[0] : 0;
    final realLen = len > n ? n : len;
    final end = (1 + realLen) > data.length ? data.length : (1 + realLen);
    return String.fromCharCodes(data.sublist(1, end));
  }

  final wstr = _wstringRe.firstMatch(t);
  if (wstr != null) {
    final n = int.parse(wstr.group(1)!);
    final len = data.length >= 2 ? b.getUint16(0, Endian.little) : 0;
    final realLen = len > n ? n : len;
    final end = (2 + 2 * realLen) > data.length ? data.length : (2 + 2 * realLen);
    final chars = <int>[];
    for (var i = 2; i + 1 < end; i += 2) {
      chars.add(b.getUint16(i, Endian.little));
    }
    return String.fromCharCodes(chars);
  }

  final arr = _arrayRe.firstMatch(t);
  if (arr != null) {
    final elemType = arr.group(2)!;
    final elemSize = sizeOf(elemType);
    final items = <Object?>[];
    for (var i = 0; i + elemSize <= data.length; i += elemSize) {
      items.add(decodeValue(Uint8List.sublistView(data, i, i + elemSize), elemType));
    }
    return items;
  }

  throw ArgumentError('Tipo PLC no soportado: $plcType');
}

// ---- helpers de codificación escalar ----

Uint8List _u8(int v) => Uint8List.fromList([v & 0xff]);

Uint8List _s8(int v) => Uint8List.fromList([v & 0xff]);

Uint8List _u16(int v) {
  final d = ByteData(2)..setUint16(0, v, Endian.little);
  return d.buffer.asUint8List();
}

Uint8List _s16(int v) {
  final d = ByteData(2)..setInt16(0, v, Endian.little);
  return d.buffer.asUint8List();
}

Uint8List _u32(int v) {
  final d = ByteData(4)..setUint32(0, v, Endian.little);
  return d.buffer.asUint8List();
}

Uint8List _s32(int v) {
  final d = ByteData(4)..setInt32(0, v, Endian.little);
  return d.buffer.asUint8List();
}

Uint8List _u64(int v) {
  final d = ByteData(8)..setUint64(0, v, Endian.little);
  return d.buffer.asUint8List();
}

Uint8List _s64(int v) {
  final d = ByteData(8)..setInt64(0, v, Endian.little);
  return d.buffer.asUint8List();
}

Uint8List _f32(double v) {
  final d = ByteData(4)..setFloat32(0, v, Endian.little);
  return d.buffer.asUint8List();
}

Uint8List _f64(double v) {
  final d = ByteData(8)..setFloat64(0, v, Endian.little);
  return d.buffer.asUint8List();
}

Uint8List _encodeString(String value, int maxLength) {
  final content = value.length > maxLength ? value.substring(0, maxLength) : value;
  final bytes = Uint8List(maxLength + 1);
  bytes[0] = content.length;
  for (var i = 0; i < content.length; i++) {
    bytes[i + 1] = content.codeUnitAt(i) & 0xff;
  }
  return bytes;
}

Uint8List _encodeWString(String value, int maxLength) {
  final content = value.length > maxLength ? value.substring(0, maxLength) : value;
  final bytes = Uint8List(2 * (maxLength + 1));
  final d = ByteData.sublistView(bytes);
  d.setUint16(0, content.length, Endian.little);
  for (var i = 0; i < content.length; i++) {
    d.setUint16(2 + 2 * i, content.codeUnitAt(i), Endian.little);
  }
  return bytes;
}

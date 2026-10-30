/// Traduce una trama ADS (frame AMS/TCP + cabecera AMS + datos) a texto legible,
/// explicando qué es cada campo. Se usa para el log de comunicación del simulador.
library;

import 'dart:typed_data';

import '../ads/ams_header.dart';
import '../ads/constants.dart';

/// Devuelve una explicación multi-línea de una trama completa (6 bytes AMS/TCP +
/// 32 bytes de cabecera AMS + datos). ``direction`` es, por ejemplo, "RECIBIDO" o
/// "ENVIADO".
String explainFrame(String direction, Uint8List frame) {
  if (frame.length < amsTcpHeaderSize + amsHeaderSize) {
    return '== $direction: trama incompleta (${frame.length} bytes) ==';
  }

  final tcpReserved = _u16(frame, 0);
  final tcpLength = _u32(frame, 2);
  final ams = AmsHeader.decode(Uint8List.sublistView(frame, amsTcpHeaderSize));

  final sb = StringBuffer();
  sb.writeln('== $direction · ${frame.length} bytes ==');
  sb.writeln('  HEX:');
  sb.writeln(_hex(frame));
  sb.writeln('  [AMS/TCP] reservado=0x${tcpReserved.toRadixString(16).padLeft(4, '0')}'
      ' | longitud=${tcpLength} bytes (32 cabecera AMS + ${tcpLength - amsHeaderSize} datos)');
  sb.writeln('  [CABECERA AMS]');
  sb.writeln('    target_netid = ${ams.targetNetId}');
  sb.writeln('    target_port  = ${ams.targetPort} (${_portName(ams.targetPort)})');
  sb.writeln('    source_netid = ${ams.sourceNetId}');
  sb.writeln('    source_port  = ${ams.sourcePort}');
  sb.writeln('    command_id   = 0x${ams.commandId.toRadixString(16).padLeft(4, '0')}'
      ' -> ${_cmdName(ams.commandId)}');
  sb.writeln('    state_flags  = ${ams.stateFlags} (${_flagsName(ams.stateFlags)})');
  sb.writeln('    length       = ${ams.data.length} bytes de datos');
  sb.writeln('    error_code   = 0x${ams.errorCode.toRadixString(16).padLeft(8, '0')}'
      ' (${_errorName(ams.errorCode)})');
  sb.writeln('    invoke_id    = ${ams.invokeId}');
  if (ams.data.isNotEmpty) {
    sb.write(_explainData(ams));
  }
  return sb.toString().trimRight();
}

// ---------------------------------------------------------------------------
// Explicación del cuerpo de datos según el comando y si es petición o respuesta.
// ---------------------------------------------------------------------------
String _explainData(AmsHeader ams) {
  final d = ams.data;
  final cmd = ams.commandId;
  final isRequest = ams.stateFlags == 0;
  final sb = StringBuffer();

  switch (cmd) {
    case AdsCommand.readState:
      if (d.length >= 4) {
        sb.writeln('  [DATOS] ads_state=${_u16(d, 0)} (${_stateName(_u16(d, 0))})'
            ' | device_state=${_u16(d, 2)}');
      }
      return sb.toString();

    case AdsCommand.writeControl:
      if (d.length >= 4) {
        sb.writeln('  [DATOS] estado_solicitado=${_u16(d, 0)} (${_stateName(_u16(d, 0))})'
            ' | device_state=${_u16(d, 2)}${d.length > 4 ? ' | datos_extra=${d.length - 4} bytes' : ''}');
      }
      return sb.toString();

    case AdsCommand.readDeviceInfo:
      if (isRequest) {
        sb.writeln('  [DATOS] (sin datos: solo se pide la información del dispositivo)');
      } else if (d.length >= 20) {
        sb.writeln('  [DATOS] versión=${d[0]}.${d[1]} build=${_u16(d, 2)}'
            ' | nombre="${_ascii(d, 4, 16)}"');
      }
      return sb.toString();

    case AdsCommand.readWrite:
      if (d.length >= 16) {
        sb.writeln('  [DATOS] index_group=0x${_u32(d, 0).toRadixString(16)}'
            ' (${_indexGroupName(_u32(d, 0))}) | index_offset=${_u32(d, 4)}');
        sb.writeln('    bytes_a_leer=${_u32(d, 8)} | bytes_a_escribir=${_u32(d, 12)}'
            ' | write_data=${d.length - 16} bytes');
      }
      return sb.toString();

    case AdsCommand.addDeviceNotification:
      if (d.length >= 32) {
        sb.writeln('  [DATOS] index_group=0x${_u32(d, 0).toRadixString(16)}'
            ' (${_indexGroupName(_u32(d, 0))}) | index_offset=${_u32(d, 4)}');
        sb.writeln('    bytes_a_notificar=${_u32(d, 8)} | trans_mode=${_u32(d, 12)}'
            ' (${_transName(_u32(d, 12))})');
        sb.writeln('    max_delay=${_u32(d, 16)} ms | cycle_time=${_u32(d, 20)} (100 ns)');
      }
      return sb.toString();

    case AdsCommand.delDeviceNotification:
      if (d.length >= 4) {
        sb.writeln('  [DATOS] notification_handle=${_u32(d, 0)}');
      }
      return sb.toString();

    case AdsCommand.deviceNotification:
      if (d.length >= 4) {
        sb.writeln('  [DATOS] notificación (stamps): longitud_total=${_u32(d, 0)} bytes');
      }
      return sb.toString();

    case AdsCommand.read:
    case AdsCommand.write:
      return _explainReadWrite(ams);
  }

  sb.writeln('  [DATOS] ${d.length} bytes');
  return sb.toString();
}

String _explainReadWrite(AmsHeader ams) {
  final d = ams.data;
  final isRequest = ams.stateFlags == 0;
  final sb = StringBuffer();

  if (!isRequest) {
    sb.writeln('  [DATOS] respuesta: ${d.length} bytes (valor/datos crudos)');
    return sb.toString();
  }
  if (d.length < 8) {
    sb.writeln('  [DATOS] incompleto');
    return sb.toString();
  }

  final ig = _u32(d, 0);
  final io = _u32(d, 4);
  sb.writeln('  [DATOS] index_group=0x${ig.toRadixString(16)} (${_indexGroupName(ig)})'
      ' | index_offset=$io');

  switch (ig) {
    case AdsIndexGroup.symValByName:
      if (d.length >= 12) {
        final nameLen = _u32(d, 8);
        final name = _ascii(d, 12, nameLen);
        sb.writeln('    nombre="${name}" (longitud=$nameLen)');
        final off = 12 + nameLen;
        if (ams.commandId == AdsCommand.read) {
          if (d.length >= off + 4) sb.writeln('    bytes_a_leer=${_u32(d, off)}');
        } else {
          if (d.length >= off + 4) sb.writeln('    longitud_valor=${_u32(d, off)}');
        }
      }
      break;

    case AdsIndexGroup.symValByHnd:
      sb.writeln('    handle=$io');
      if (d.length >= 12) {
        if (ams.commandId == AdsCommand.read) {
          sb.writeln('    bytes_a_leer=${_u32(d, 8)}');
        } else {
          sb.writeln('    longitud_valor=${_u32(d, 8)}');
        }
      }
      break;

    case AdsIndexGroup.symHndByName:
    case AdsIndexGroup.symInfoByName:
      if (d.length >= 12) {
        final nameLen = _u32(d, 8);
        sb.writeln('    nombre="${_ascii(d, 12, nameLen)}" (longitud=$nameLen)');
      }
      break;

    case AdsIndexGroup.symReleaseHnd:
      sb.writeln('    handle_a_liberar=$io');
      break;

    case AdsIndexGroup.ioImageRwIb:
    case AdsIndexGroup.ioImageRwOb:
      if (d.length >= 12) {
        if (ams.commandId == AdsCommand.read) {
          sb.writeln('    bytes_a_leer=${_u32(d, 8)} (offset en imagen de proceso)');
        } else {
          sb.writeln('    longitud_valor=${_u32(d, 8)} (offset en imagen de proceso)');
        }
      }
      break;

    case AdsIndexGroup.sumUpRead:
      sb.writeln('    (comando sum: varias entradas ig+io+longitud concatenadas)');
      break;
    case AdsIndexGroup.sumUpWrite:
      sb.writeln('    (comando sum: varias entradas ig+io+longitud+datos concatenadas)');
      break;

    default:
      if (ams.commandId == AdsCommand.read && d.length >= 12) {
        sb.writeln('    bytes_a_leer=${_u32(d, 8)}');
      }
  }
  return sb.toString();
}

// ---------------------------------------------------------------------------
// Utilidades
// ---------------------------------------------------------------------------
String _hex(Uint8List bytes) {
  final sb = StringBuffer();
  for (var i = 0; i < bytes.length; i += 16) {
    final end = i + 16 <= bytes.length ? i + 16 : bytes.length;
    final line = StringBuffer('    ');
    for (var j = i; j < end; j++) {
      line.write(bytes[j].toRadixString(16).padLeft(2, '0'));
      line.write(' ');
    }
    sb.writeln(line.toString());
  }
  return sb.toString().trimRight();
}

int _u16(Uint8List b, int o) => (b[o] & 0xff) | ((b[o + 1] & 0xff) << 8);

int _u32(Uint8List b, int o) =>
    (b[o] & 0xff) |
    ((b[o + 1] & 0xff) << 8) |
    ((b[o + 2] & 0xff) << 16) |
    ((b[o + 3] & 0xff) << 24);

String _ascii(Uint8List b, int o, int len) {
  final end = o + len <= b.length ? o + len : b.length;
  return String.fromCharCodes(b.sublist(o, end)).replaceAll('\x00', '');
}

String _cmdName(int c) {
  switch (c) {
    case AdsCommand.readDeviceInfo: return 'READ_DEVICE_INFO (leer info del dispositivo)';
    case AdsCommand.read: return 'READ (leer datos)';
    case AdsCommand.write: return 'WRITE (escribir datos)';
    case AdsCommand.readState: return 'READ_STATE (leer estado)';
    case AdsCommand.writeControl: return 'WRITE_CONTROL (cambiar estado)';
    case AdsCommand.addDeviceNotification: return 'ADD_DEVICE_NOTIFICATION (suscribir notificación)';
    case AdsCommand.delDeviceNotification: return 'DEL_DEVICE_NOTIFICATION (cancelar notificación)';
    case AdsCommand.deviceNotification: return 'DEVICE_NOTIFICATION (notificación)';
    case AdsCommand.readWrite: return 'READ_WRITE (leer y escribir)';
    default: return 'desconocido';
  }
}

String _indexGroupName(int ig) {
  switch (ig) {
    case AdsIndexGroup.symTab: return 'SYMTAB (tabla de símbolos)';
    case AdsIndexGroup.symHndByName: return 'SYM_HNDBYNAME (obtener handle por nombre)';
    case AdsIndexGroup.symValByHnd: return 'SYM_VALBYHND (valor por handle)';
    case AdsIndexGroup.symValByName: return 'SYM_VALBYNAME (valor por nombre)';
    case AdsIndexGroup.symInfoByName: return 'SYM_INFOBYNAME (info de símbolo)';
    case AdsIndexGroup.symReleaseHnd: return 'SYM_RELEASEHND (liberar handle)';
    case AdsIndexGroup.ioImageRwIb: return 'IOIMAGE_RWIB (imagen de proceso: entradas)';
    case AdsIndexGroup.ioImageRwOb: return 'IOIMAGE_RWOB (imagen de proceso: salidas)';
    case AdsIndexGroup.sumUpRead: return 'SUMUP_READ (lectura múltiple)';
    case AdsIndexGroup.sumUpWrite: return 'SUMUP_WRITE (escritura múltiple)';
    default: return 'grupo desconocido';
  }
}

String _portName(int p) {
  switch (p) {
    case 851: return 'PLC Runtime 1 (TC3)';
    case 852: return 'PLC Runtime 2 (TC3)';
    case 853: return 'PLC Runtime 3 (TC3)';
    case 801: return 'PLC Runtime (TC2)';
    case 800: return 'PLC (TC2)';
    case 400: return 'IO';
    case 500: return 'NC';
    case 100: return 'Logger';
    default: return 'puerto de aplicación';
  }
}

String _stateName(int s) {
  switch (s) {
    case 5: return 'RUN (en marcha)';
    case 6: return 'STOP (parado)';
    case 2: return 'RESET';
    case 1: return 'IDLE';
    case 0: return 'INVALID';
    default: return 'estado $s';
  }
}

String _transName(int t) {
  switch (t) {
    case 4: return 'SERVER_ONCHANGE (al cambiar)';
    case 3: return 'SERVER_CYCLE (por ciclo)';
    case 2: return 'CLIENT_ONCHANGE';
    case 1: return 'CLIENT_CYCLE';
    default: return 'sin transmisión';
  }
}

String _errorName(int e) {
  switch (e) {
    case 0x00000000: return 'sin error';
    case 0x00000008: return 'comando desconocido';
    case 0x00000701: return 'servicio no soportado';
    case 0x00000702: return 'grupo de índice inválido';
    case 0x00000703: return 'offset de índice inválido';
    case 0x00000705: return 'tamaño de parámetro incorrecto';
    case 0x00000710: return 'símbolo no encontrado';
    case 0x00000714: return 'handle de notificación inválido';
    default: return 'error $e';
  }
}

String _flagsName(int f) {
  switch (f) {
    case 0: return 'solicitud';
    case 1: return 'respuesta';
    case 4: return 'notificación';
    default: return 'desconocido';
  }
}

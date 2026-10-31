// Entrypoint headless del simulador ADS (sin UI Flutter).
//
// Arranca el servidor ADS sobre TCP usando únicamente Dart puro (dart:io),
// de modo que los clientes Python (LibPhithon) y C# (LibC#) puedan probarse
// sin necesidad de compilar la aplicación Flutter.
//
// Uso:
//   dart bin/server.dart                                     # valores por defecto
//   dart bin/server.dart 40000                               # puerto TCP
//   dart bin/server.dart 40000 127.0.0.1.1.1 851 127.0.0.1   # todos los parámetros

import 'dart:io';

import '../lib/ads/ams_header.dart';
import '../lib/ads/constants.dart';
import '../lib/simulator/ads_server.dart';
import '../lib/simulator/device.dart';

Future<void> main(List<String> args) async {
  // Argumentos opcionales: [puerto_tcp] [ams_net_id] [ams_port] [ip]
  final port = args.isNotEmpty ? (int.tryParse(args[0]) ?? AdsPort.tcpPort) : AdsPort.tcpPort;
  final netId = args.length > 1 ? args[1] : '127.0.0.1.1.1';
  final amsPort = args.length > 2 ? (int.tryParse(args[2]) ?? AdsPort.plcTc3) : AdsPort.plcTc3;
  final ip = args.length > 3 ? args[3] : '127.0.0.1';

  // Identidad del dispositivo simulado (NetId AMS + puerto AMS del runtime PLC).
  final device = Device(
    netId: AmsNetId.fromString(netId),
    amsPort: amsPort,
    log: (message) => stdout.writeln('[${DateTime.now().toIso8601String()}] $message'),
  );

  // Variables PLC simuladas y arranque del temporizador de nCounter.
  device.initSymbols();
  device.start();

  // Servidor ADS sobre TCP.
  final server = AdsServer(device: device, tcpPort: port, bindAddress: ip);
  await server.start();

  stdout.writeln('Simulador ADS en marcha en $ip:$port (NetId $netId, AMS port $amsPort).');
  stdout.writeln('Pulsa Ctrl+C para detener.');

  // Mantiene el proceso vivo indefinidamente (hasta Ctrl+C).
  await Future<void>.delayed(const Duration(days: 365));
}

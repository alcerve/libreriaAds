// Entrypoint headless del simulador ADS (sin UI Flutter).
//
// Arranca el servidor ADS sobre TCP usando únicamente Dart puro (dart:io),
// de modo que los clientes Python (LibPhithon) y C# (LibC#) puedan probarse
// sin necesidad de compilar la aplicación Flutter.
//
// Uso:
//   dart bin/server.dart            # puerto por defecto 48898
//   dart bin/server.dart 48000      # puerto personalizado

import 'dart:io';

import '../lib/ads/ams_header.dart';
import '../lib/ads/constants.dart';
import '../lib/simulator/ads_server.dart';
import '../lib/simulator/device.dart';

Future<void> main(List<String> args) async {
  // Puerto TCP opcional por argumento; por defecto el estándar de AMS/TCP.
  final port = args.isNotEmpty ? (int.tryParse(args[0]) ?? AdsPort.tcpPort) : AdsPort.tcpPort;

  // Identidad del dispositivo simulado (NetId AMS + puerto AMS del runtime PLC).
  final device = Device(
    netId: AmsNetId.fromString('127.0.0.1.1.1'),
    amsPort: AdsPort.plcTc3,
    log: (message) => stdout.writeln('[${DateTime.now().toIso8601String()}] $message'),
  );

  // Variables PLC simuladas y arranque del temporizador de nCounter.
  device.initSymbols();
  device.start();

  // Servidor ADS sobre TCP.
  final server = AdsServer(device: device, tcpPort: port);
  await server.start();

  stdout.writeln('Simulador ADS en marcha en 127.0.0.1:$port (NetId 127.0.0.1.1.1, AMS port 851).');
  stdout.writeln('Pulsa Ctrl+C para detener.');

  // Mantiene el proceso vivo indefinidamente (hasta Ctrl+C).
  await Future<void>.delayed(const Duration(days: 365));
}

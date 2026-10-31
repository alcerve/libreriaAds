// Interfaz gráfica (Flutter) del simulador de dispositivo ADS.
//
// Permite arrancar/detener el servidor ADS, configurar el puerto TCP,
// visualizar en tiempo real las variables PLC simuladas (MAIN.nCounter se
// incrementa cada 500 ms en estado RUN) y editarlas, además de mostrar un
// registro de conexiones y errores.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'ads/ams_header.dart';
import 'ads/constants.dart';
import 'ads/datatypes.dart';
import 'simulator/ads_server.dart';
import 'simulator/device.dart';
import 'simulator/symbol_table.dart';

void main() => runApp(const AdsSimulatorApp());

/// Aplicación raíz del simulador.
class AdsSimulatorApp extends StatelessWidget {
  const AdsSimulatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simulador ADS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const SimulatorPage(),
    );
  }
}

/// Pantalla principal: control del servidor, tabla de variables y registro.
class SimulatorPage extends StatefulWidget {
  const SimulatorPage({super.key});

  @override
  State<SimulatorPage> createState() => _SimulatorPageState();
}

class _SimulatorPageState extends State<SimulatorPage> {
  Device? _device;
  AdsServer? _server;
  final TextEditingController _portController = TextEditingController(text: '40000');
  final List<String> _logs = [];
  final Map<String, TextEditingController> _editors = {};
  Timer? _refreshTimer;
  String _libreriaSeleccionada = 'Python';
  final TextEditingController _variablesPathController = TextEditingController(
    text: r'C:\DeepSeek Harness\libreriaAds\simulador_flutter\variables.json',
  );

  @override
  void initState() {
    super.initState();
    // Refresca periódicamente la tabla para mostrar nCounter en vivo.
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted) setState(() {});
    });
    // Auto-inicia el servidor al abrir la app: menos pasos para el usuario.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _portController.dispose();
    _variablesPathController.dispose();
    for (final controller in _editors.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _log(String message) {
    if (!mounted) return;
    setState(() {
      _logs.insert(0, message);
      if (_logs.length > 200) _logs.removeLast();
    });
  }

  Future<void> _start() async {
    final port = int.tryParse(_portController.text) ?? AdsPort.tcpPort;
    final device = Device(
      netId: AmsNetId.fromString('127.0.0.1.1.1'),
      amsPort: AdsPort.plcTc3,
      log: _log,
    );
    device.initSymbols();
    device.start();
    final server = AdsServer(device: device, tcpPort: port);
    try {
      await server.start();
    } catch (e) {
      device.stop();
      _log('ERROR al iniciar el servidor en 127.0.0.1:$port');
      _log('Detalle: $e');
      _log('Pista: el puerto 48898 suele estar ocupado; prueba con 40000.');
      return;
    }
    setState(() {
      _device = device;
      _server = server;
      for (final symbol in device.symbols.byName.values) {
        _editors.putIfAbsent(symbol.name, () => TextEditingController());
      }
    });
  }

  Future<void> _stop() async {
    await _server?.stop();
    setState(() {
      _server = null;
      _device = null;
    });
  }

  /// Lanza el cliente seleccionado (Python o C#) y muestra su salida en el log.
  Future<void> _lanzarCliente() async {
    final port = _portController.text;
    // Ruta raíz del proyecto (ajústala si mueves la carpeta).
    const raiz = r'C:\DeepSeek Harness\libreriaAds';

    _log('=== Lanzando cliente $_libreriaSeleccionada (puerto $port) ===');
    try {
      final process = _libreriaSeleccionada == 'Python'
          ? await Process.start(
              'python',
              ['examples/verify_simulator.py', port],
              workingDirectory: '$raiz\\LibPhithon',
            )
          : await Process.start(
              'dotnet',
              ['run', '--', port],
              workingDirectory: '$raiz\\LibC#\\examples\\AdsExample',
            );

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isNotEmpty) _log('CLIENTE> $line');
      });
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isNotEmpty) _log('CLIENTE> $line');
      });

      final code = await process.exitCode;
      _log('=== Cliente $_libreriaSeleccionada terminado (código $code) ===');
    } catch (e) {
      _log('ERROR lanzando el cliente $_libreriaSeleccionada: $e');
    }
  }

  /// Carga las variables del simulador desde un archivo JSON (para emular un PLC real).
  Future<void> _cargarVariables() async {
    if (_device == null) {
      _log('Espera a que arranque el servidor antes de cargar variables.');
      return;
    }
    final path = _variablesPathController.text.trim();
    if (path.isEmpty) {
      _log('ERROR: escribe la ruta del archivo de variables.');
      return;
    }
    try {
      final file = File(path);
      if (!file.existsSync()) {
        _log('ERROR: no existe el archivo $path');
        return;
      }
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final definiciones = (json['variables'] as List<dynamic>?) ?? const [];
      _device!.loadVariableDefinitions(definiciones);
      setState(() {
        _editors.clear();
        for (final symbol in _device!.symbols.byName.values) {
          _editors.putIfAbsent(symbol.name, () => TextEditingController());
        }
      });
    } catch (e) {
      _log('ERROR cargando variables: $e');
    }
  }

  /// Muestra un valor PLC en texto legible.
  String _displayValue(Symbol symbol) {
    final value = decodeValue(symbol.value, symbol.plcType);
    if (value is List) return value.join(', ');
    if (value is double) return value.toStringAsFixed(4);
    return value.toString();
  }

  /// Convierte texto escrito por el usuario a un valor Dart según el tipo PLC.
  Object? _parseValue(String text, String plcType) {
    final t = plcType.trim().toUpperCase();
    if (t == 'BOOL') {
      return text.trim().toLowerCase() == 'true' || text.trim() == '1';
    }
    if (t == 'STRING' || t.startsWith('STRING(')) return text;
    if (t.startsWith('ARRAY')) {
      final elemType = RegExp(r'ARRAY\[[^\]]*\]\s+OF\s+(.+)').firstMatch(t)!.group(1)!;
      return text.split(',').map((e) => _parseValue(e.trim(), elemType)).toList();
    }
    if (t == 'REAL' || t == 'LREAL') return double.parse(text.trim());
    return int.parse(text.trim());
  }

  void _write(Symbol symbol) {
    final text = _editors[symbol.name]?.text ?? '';
    try {
      final value = _parseValue(text, symbol.plcType);
      symbol.value = encodeValue(value, symbol.plcType);
      _device?.notifySymbolChanged(symbol);
      _log('Escritura local en ${symbol.name} = ${_displayValue(symbol)}');
    } catch (e) {
      _log('Valor inválido para ${symbol.name}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = _device;
    final running = _server != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Simulador de dispositivo ADS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Acerca de',
            onPressed: () => _showAbout(context),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildControls(running),
          Expanded(child: device == null ? const SizedBox.shrink() : _buildSymbols(device)),
          _buildLogs(),
        ],
      ),
    );
  }

  Widget _buildControls(bool running) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _portController,
                  enabled: !running,
                  decoration: const InputDecoration(
                    labelText: 'Puerto TCP',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  running
                      ? 'ESCUCHANDO en 127.0.0.1:${_portController.text} (AMS 127.0.0.1.1.1:851)'
                      : 'Servidor detenido',
                  style: TextStyle(
                    color: running ? Colors.green.shade700 : Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: running ? _stop : _start,
                icon: Icon(running ? Icons.stop : Icons.play_arrow),
                label: Text(running ? 'Detener' : 'Iniciar'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Librería a probar:'),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _libreriaSeleccionada,
                items: const [
                  DropdownMenuItem(value: 'Python', child: Text('Python (LibPhithon)')),
                  DropdownMenuItem(value: 'C#', child: Text('C# (LibC#)')),
                ],
                onChanged: (v) => setState(() => _libreriaSeleccionada = v ?? 'Python'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'El cliente elegido se conecta al simulador y las tramas se ven abajo.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: running ? _lanzarCliente : null,
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Probar cliente'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Variables (JSON):'),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _variablesPathController,
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: 'ruta de variables.json',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: _cargarVariables,
                icon: const Icon(Icons.upload_file),
                label: const Text('Cargar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSymbols(Device device) {
    final symbols = device.symbols.byName.values.toList();
    return ListView.builder(
      itemCount: symbols.length,
      itemBuilder: (context, index) {
        final symbol = symbols[index];
        final controller = _editors.putIfAbsent(symbol.name, () => TextEditingController());
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 180,
                child: Text(symbol.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              SizedBox(width: 130, child: Text(symbol.plcType)),
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: _displayValue(symbol),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                tooltip: 'Escribir valor',
                onPressed: () => _write(symbol),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLogs() {
    return SizedBox(
      height: 320,
      child: Container(
        color: Colors.black87,
        padding: const EdgeInsets.all(8),
        child: ListView.builder(
          itemCount: _logs.length,
          itemBuilder: (context, index) => Text(
            _logs[index],
            style: const TextStyle(color: Colors.lightGreen, fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Acerca del simulador'),
        content: const Text(
          'Simula un dispositivo ADS (Beckhoff) exponiendo variables PLC '
          '(MAIN.*). Implementa el protocolo ADS/TCP definido en PROTOCOL.md.\n\n'
          'Variables: MAIN.bStart, MAIN.bStop, MAIN.nCounter, MAIN.iLevel, '
          'MAIN.fTemp, MAIN.dPosition, MAIN.sMessage, MAIN.arrValues.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );
  }
}

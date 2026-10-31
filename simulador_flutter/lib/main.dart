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

import 'ads/ads_client.dart';
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
  final TextEditingController _netIdController = TextEditingController(text: '127.0.0.1.1.1');
  final TextEditingController _amsPortController = TextEditingController(text: '851');
  final TextEditingController _ipController = TextEditingController(text: '127.0.0.1');
  String _modo = 'Simulado';
  AdsClient? _realClient;
  Timer? _realRefreshTimer;
  final Set<String> _seleccionadas = {};
  final Map<String, String> _metodos = {};
  final Set<String> _expandidas = {};
  final TextEditingController _busquedaController = TextEditingController();
  String _filtro = '';
  final Map<String, TextEditingController> _indexControllers = {};

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
    _netIdController.dispose();
    _amsPortController.dispose();
    _ipController.dispose();
    _realRefreshTimer?.cancel();
    _realClient?.disconnect();
    _busquedaController.dispose();
    for (final c in _indexControllers.values) {
      c.dispose();
    }
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
    final amsPort = int.tryParse(_amsPortController.text) ?? AdsPort.plcTc3;
    final netIdStr = _netIdController.text.trim();
    final ip = _ipController.text.trim().isEmpty ? '127.0.0.1' : _ipController.text.trim();

    final AmsNetId netId;
    try {
      netId = AmsNetId.fromString(netIdStr);
    } catch (_) {
      _log('ERROR: NetId AMS inválido "$netIdStr" (formato: a.b.c.d.e.f).');
      return;
    }

    if (_modo == 'Real') {
      await _conectarReal(netId, amsPort, ip, port);
      return;
    }

    final device = Device(netId: netId, amsPort: amsPort, log: _log);
    device.initSymbols();
    device.start();
    final server = AdsServer(device: device, tcpPort: port, bindAddress: ip);
    try {
      await server.start();
    } catch (e) {
      device.stop();
      _log('ERROR al iniciar el servidor en $ip:$port');
      _log('Detalle: $e');
      _log('Pista: revisa que el puerto no esté ocupado y que la IP sea correcta.');
      return;
    }
    setState(() {
      _device = device;
      _server = server;
      _realClient = null;
      for (final symbol in device.symbols.byName.values) {
        _editors.putIfAbsent(symbol.name, () => TextEditingController());
      }
    });
  }

  Future<void> _stop() async {
    if (_modo == 'Real') {
      _realRefreshTimer?.cancel();
      _realRefreshTimer = null;
      _realClient?.disconnect();
      setState(() {
        _realClient = null;
        _device = null;
      });
      _log('Desconectado del PLC real.');
      return;
    }
    await _server?.stop();
    setState(() {
      _server = null;
      _device = null;
    });
  }

  /// Conecta con un PLC real y empieza a leer sus variables periódicamente.
  Future<void> _conectarReal(AmsNetId netId, int amsPort, String ip, int port) async {
    final client = AdsClient(targetNetId: netId, amsPort: amsPort, ipAddress: ip, tcpPort: port);
    try {
      await client.connect();
    } catch (e) {
      _log('ERROR al conectar con el PLC real en $ip:$port');
      _log('Detalle: $e');
      return;
    }
    final device = Device(netId: netId, amsPort: amsPort, log: _log);
    device.initSymbols();
    setState(() {
      _device = device;
      _server = null;
      _realClient = client;
      for (final symbol in device.symbols.byName.values) {
        _editors.putIfAbsent(symbol.name, () => TextEditingController());
      }
    });
    _log('Conectado al PLC real en $ip:$port (NetId $netId, AMS $amsPort).');
    _realRefreshTimer?.cancel();
    _realRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) => _refrescarReal());
    _refrescarReal();
  }

  bool _refrescandoReal = false;

  /// Lee las variables del PLC real y actualiza la tabla.
  Future<void> _refrescarReal() async {
    if (_refrescandoReal) return;
    _refrescandoReal = true;
    try {
      final client = _realClient;
      final device = _device;
      if (client == null || device == null) return;
      for (final name in _seleccionadas.toList()) {
        final symbol = device.symbols.byName[name];
        if (symbol == null) continue;
        final metodo = _metodos[name] ?? 'Leer';
        if (metodo == 'Escribir') continue; // solo se leen Leer/Ambos
        try {
          final bytes = await client.readByName(symbol.name, symbol.size);
          symbol.value = Uint8List.fromList(bytes);
        } catch (_) {
          // error de lectura puntual: se reintentará en el siguiente ciclo
        }
      }
      if (mounted) setState(() {});
    } finally {
      _refrescandoReal = false;
    }
  }

  /// Lanza el cliente seleccionado (Python o C#) y muestra su salida en el log.
  Future<void> _lanzarCliente() async {
    final port = _portController.text;
    final netId = _netIdController.text.trim();
    final amsPort = _amsPortController.text.trim();
    final ip = _ipController.text.trim();
    // Ruta raíz del proyecto (ajústala si mueves la carpeta).
    const raiz = r'C:\DeepSeek Harness\libreriaAds';

    _log('=== Lanzando cliente $_libreriaSeleccionada ($ip:$port, NetId $netId, AMS $amsPort) ===');
    try {
      final process = _libreriaSeleccionada == 'Python'
          ? await Process.start(
              'python',
              ['examples/verify_simulator.py', port, netId, amsPort, ip],
              workingDirectory: '$raiz\\LibPhithon',
            )
          : await Process.start(
              'dotnet',
              ['run', '--', port, netId, amsPort, ip],
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
      _device!.loadProject(json);
      setState(() {
        _editors.clear();
        _seleccionadas.clear();
        _metodos.clear();
        _expandidas.clear();
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
    try {
      final value = decodeValue(symbol.value, symbol.plcType);
      if (value is List) return value.join(', ');
      if (value is double) return value.toStringAsFixed(4);
      return value.toString();
    } catch (_) {
      return '(estructura, ${symbol.size} bytes)';
    }
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
    final metodo = _metodos[symbol.name] ?? 'Ambos';
    if (!_seleccionadas.contains(symbol.name) || metodo == 'Leer') {
      _log('Selecciona la variable y elige método Escribir/Ambos para poder escribir.');
      return;
    }
    final text = _editors[symbol.name]?.text ?? '';
    try {
      final value = _parseValue(text, symbol.plcType);
      final encoded = encodeValue(value, symbol.plcType);
      if (_modo == 'Real' && _realClient != null) {
        _realClient!.writeByName(symbol.name, encoded);
        symbol.value = encoded;
        _log('Escritura en PLC real: ${symbol.name} = ${_displayValue(symbol)}');
      } else {
        symbol.value = encoded;
        _device?.notifySymbolChanged(symbol);
        _log('Escritura local en ${symbol.name} = ${_displayValue(symbol)}');
      }
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

  Widget _paramField(String label, TextEditingController controller, double width, {bool enabled = true}) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        enabled: enabled,
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
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
              const Text('Modo:'),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _modo,
                items: const [
                  DropdownMenuItem(value: 'Simulado', child: Text('PLC Simulado')),
                  DropdownMenuItem(value: 'Real', child: Text('PLC Real')),
                ],
                onChanged: running ? null : (v) => setState(() => _modo = v ?? 'Simulado'),
              ),
              const SizedBox(width: 12),
              _paramField('NetId AMS', _netIdController, 130, enabled: !running),
              const SizedBox(width: 8),
              _paramField('Puerto AMS', _amsPortController, 80, enabled: !running),
              const SizedBox(width: 8),
              _paramField('IP', _ipController, 100, enabled: !running),
              const SizedBox(width: 8),
              _paramField('Puerto TCP', _portController, 80, enabled: !running),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  running
                      ? 'ESCUCHANDO en ${_ipController.text}:${_portController.text} (NetId ${_netIdController.text}, AMS ${_amsPortController.text})'
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
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: _guardarVariables,
                icon: const Icon(Icons.save),
                label: const Text('Guardar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Expande la posición [index] de un array (de estructuras o de tipos simples).
  void _expandArrayIndex(Symbol symbol) {
    final device = _device;
    final parsed = device?.parseArrayType(symbol.plcType);
    if (device == null || parsed == null) return;
    final (lo, hi, _) = parsed;
    final index = int.tryParse(_indexControllers[symbol.name]?.text.trim() ?? '') ?? lo;
    final i = index < lo ? lo : (index > hi ? hi : index);
    setState(() {
      device.collapseStruct(symbol); // quita los índices expandidos anteriores
      _expandidas.removeWhere((n) => n.startsWith('${symbol.name}['));
      device.expandArrayElement(symbol, i);
      _expandidas.add('${symbol.name}[$i]');
    });
  }

  /// Guarda las variables actuales (con sus valores escalares) en el archivo JSON.
  void _guardarVariables() {
    final device = _device;
    if (device == null) {
      _log('No hay variables cargadas para guardar.');
      return;
    }
    final path = _variablesPathController.text.trim();
    if (path.isEmpty) {
      _log('ERROR: escribe la ruta del archivo de destino.');
      return;
    }
    try {
      final variables = <Map<String, dynamic>>[];
      for (final symbol in device.symbols.byName.values) {
        final item = <String, dynamic>{
          'name': symbol.name,
          'type': symbol.plcType,
          'size': symbol.size,
        };
        try {
          final value = decodeValue(symbol.value, symbol.plcType);
          if (value is bool || value is num || value is String) {
            item['value'] = value;
          }
        } catch (_) {
          // estructura o tipo no serializable: se omite el valor
        }
        variables.add(item);
      }
      final types = <String, dynamic>{};
      for (final e in device.types.entries) {
        types[e.key] = e.value;
      }
      final json = {'types': types, 'variables': variables};
      File(path).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
      _log('Variables guardadas en $path (${variables.length} símbolos).');
    } catch (e) {
      _log('ERROR guardando variables: $e');
    }
  }

  void _toggleExpand(Symbol symbol, Device device) {
    setState(() {
      if (_expandidas.contains(symbol.name)) {
        _expandidas.remove(symbol.name);
        device.collapseStruct(symbol);
      } else {
        _expandidas.add(symbol.name);
        device.expandStruct(symbol);
      }
    });
  }

  void _toggleSeleccion(Symbol symbol, bool value) {
    setState(() {
      if (value) {
        _seleccionadas.add(symbol.name);
        _metodos.putIfAbsent(symbol.name, () => 'Ambos');
      } else {
        _seleccionadas.remove(symbol.name);
        _metodos.remove(symbol.name);
      }
    });
  }

  Widget _buildSymbols(Device device) {
    final all = device.symbols.byName.values.toList();
    final filtered = _filtro.isEmpty
        ? all
        : all.where((s) => s.name.toLowerCase().contains(_filtro.toLowerCase())).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: TextField(
            controller: _busquedaController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar variable…',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _filtro = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${_seleccionadas.length} seleccionadas · ${filtered.length} mostradas',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('Sin variables. Pulsa "Cargar" con un variables.json.'))
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) => _buildSymbolRow(filtered[index], device),
                ),
        ),
      ],
    );
  }

  Widget _buildSymbolRow(Symbol symbol, Device device) {
    final esEstructura = device.esExpandible(symbol);
    final bounds = device.parseArrayType(symbol.plcType);
    final esArray = bounds != null;
    final defaultIndex = bounds != null ? '${bounds.$1}' : '0';
    final expandida = _expandidas.contains(symbol.name);
    final seleccionada = _seleccionadas.contains(symbol.name);
    final metodo = _metodos[symbol.name] ?? 'Ambos';
    final profundidad = symbol.name.split('.').length - 1;

    return Padding(
      padding: EdgeInsets.only(left: 8.0 + profundidad * 18.0, right: 8, top: 2, bottom: 2),
      child: Row(
        children: [
          if (esEstructura)
            IconButton(
              icon: Icon(expandida ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right),
              visualDensity: VisualDensity.compact,
              tooltip: expandida ? 'Colapsar' : 'Expandir',
              onPressed: () => _toggleExpand(symbol, device),
            )
          else if (esArray)
            ...[
              SizedBox(
                width: 52,
                child: TextField(
                  controller: _indexControllers.putIfAbsent(
                    symbol.name,
                    () => TextEditingController(text: defaultIndex),
                  ),
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                  style: const TextStyle(fontSize: 12),
                  keyboardType: TextInputType.number,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.unfold_more, size: 18),
                visualDensity: VisualDensity.compact,
                tooltip: 'Expandir índice del array',
                onPressed: () => _expandArrayIndex(symbol),
              ),
            ]
          else
            const SizedBox(width: 40),
          Checkbox(
            value: seleccionada,
            onChanged: (v) => _toggleSeleccion(symbol, v ?? false),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  symbol.name,
                  style: TextStyle(
                    fontWeight: seleccionada ? FontWeight.w700 : FontWeight.w400,
                    fontSize: 12,
                    color: esEstructura ? Colors.indigo.shade700 : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  symbol.plcType,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (seleccionada) ...[
            DropdownButton<String>(
              value: metodo,
              underline: const SizedBox(),
              style: const TextStyle(fontSize: 12),
              items: const [
                DropdownMenuItem(value: 'Leer', child: Text('Leer')),
                DropdownMenuItem(value: 'Escribir', child: Text('Escribir')),
                DropdownMenuItem(value: 'Ambos', child: Text('Ambos')),
              ],
              onChanged: (v) => setState(() => _metodos[symbol.name] = v ?? 'Ambos'),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 150,
              child: TextField(
                controller: _editors.putIfAbsent(symbol.name, () => TextEditingController()),
                decoration: InputDecoration(
                  hintText: _displayValue(symbol),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send),
              visualDensity: VisualDensity.compact,
              tooltip: 'Escribir',
              onPressed: () => _write(symbol),
            ),
          ],
        ],
      ),
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

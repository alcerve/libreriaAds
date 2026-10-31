/// Parser de archivos .tpy de TwinCAT (exportación de símbolos).
///
/// Convierte el XML de TwinCAT en la estructura que usa el simulador:
///   { "types": {NombreTipo: [ {name, type, size}, ... ]},
///     "variables": [ {name, type, size}, ... ] }
///
/// Procesa los elementos <DataType> (estructuras), <Symbol> (variables) y
/// <VarConfig> (variables configuradas, p. ej. ejes NC).
library;

import 'package:xml/xml.dart';

/// Tipos escalares IEC 61131-3 que el simulador sabe codificar directamente.
const Set<String> _baseTypes = {
  'BOOL', 'BYTE', 'SINT', 'USINT', 'INT', 'UINT', 'WORD',
  'DINT', 'UDINT', 'DWORD', 'REAL', 'TIME', 'TOD', 'DT', 'DATE',
  'LINT', 'ULINT', 'LREAL',
};

int _bytes(int bits) => bits <= 0 ? 1 : (bits + 7) ~/ 8;

String _text(XmlElement? el) => (el?.innerText ?? '').trim();

/// Parsea el contenido XML de un .tpy y devuelve el proyecto (types + variables).
Map<String, dynamic> parseTpy(String xmlContent) {
  final doc = XmlDocument.parse(xmlContent);

  // 1) Estructuras: <DataType> con <SubItem>.
  final tipos = <String, List<Map<String, dynamic>>>{};
  for (final dt in doc.findAllElements('DataType')) {
    final name = _text(dt.getElement('Name'));
    if (name.isEmpty) continue;
    final subItems = dt.findAllElements('SubItem').toList();
    if (subItems.isEmpty) continue;
    final miembros = <Map<String, dynamic>>[];
    for (final si in subItems) {
      final mn = _text(si.getElement('Name'));
      final mt = _text(si.getElement('Type'));
      final bits = int.tryParse(_text(si.getElement('BitSize'))) ?? 0;
      if (mn.isEmpty || mt.isEmpty) continue;
      miembros.add({'name': mn, 'type': mt, 'size': _bytes(bits)});
    }
    if (miembros.isNotEmpty) tipos[name] = miembros;
  }

  // 2) Variables: <Symbol> + <VarConfig>.
  final variables = <Map<String, dynamic>>[];
  final nodos = <XmlElement>[
    ...doc.findAllElements('Symbol'),
    ...doc.findAllElements('VarConfig'),
  ];
  for (final nodo in nodos) {
    final name = _text(nodo.getElement('Name'));
    final type = _text(nodo.getElement('Type'));
    final bits = int.tryParse(_text(nodo.getElement('BitSize'))) ?? 0;
    if (name.isEmpty || type.isEmpty) continue;
    variables.add({'name': name, 'type': type, 'size': _bytes(bits)});
  }

  return {'types': tipos, 'variables': variables};
}

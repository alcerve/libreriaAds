/// Tabla de símbolos del PLC simulado.
library;

import 'dart:typed_data';

class Symbol {
  final String name;
  final String plcType;
  final int size;
  final int indexOffset; // índice único y estable dentro del área 0xF005
  Uint8List value;

  Symbol(this.name, this.plcType, this.size, this.indexOffset, this.value);
}

class SymbolTable {
  final Map<String, Symbol> byName = {};
  final Map<int, Symbol> byIndex = {};
  final Map<int, Symbol> byHandle = {};
  int _nextHandle = 1;

  void add(Symbol symbol) {
    byName[symbol.name] = symbol;
    byIndex[symbol.indexOffset] = symbol;
  }

  Symbol? findByName(String name) => byName[name];
  Symbol? findByIndex(int indexOffset) => byIndex[indexOffset];
  Symbol? findByHandle(int handle) => byHandle[handle];

  int createHandle(String name) {
    final symbol = byName[name];
    if (symbol == null) return 0;
    final handle = _nextHandle++;
    byHandle[handle] = symbol;
    return handle;
  }

  void releaseHandle(int handle) => byHandle.remove(handle);
}

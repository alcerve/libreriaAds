# -*- coding: utf-8 -*-
"""Convierte un archivo .tpy de TwinCAT a variables.json para el simulador ADS.

Genera dos secciones:
  - "types":     definición de las estructuras (miembros con nombre, tipo y tamaño).
  - "variables": símbolos de nivel superior (nombre, tipo y tamaño).

La expansión de estructuras se hace BAJO DEMANDA en la interfaz del simulador,
para no generar cientos de miles de entradas.

Uso:
    python convertir_tpy.py <archivo.tpy> [salida.json]
"""

import json
import re
import sys
import xml.etree.ElementTree as ET

BASE_TYPES = {
    "BOOL", "BYTE", "SINT", "USINT", "INT", "UINT", "WORD",
    "DINT", "UDINT", "DWORD", "REAL", "TIME", "TOD", "DT", "DATE",
    "LINT", "ULINT", "LREAL",
}
_ARRAY_RE = re.compile(r"^ARRAY\s*\[([^\]]*)\]\s+OF\s+(.+)$", re.IGNORECASE)


def _bytes(bits):
    return max(1, (bits + 7) // 8)


def parsear_tipos(root):
    """Devuelve {nombre: [{'name','type','size'}...]} solo para estructuras."""
    registry = {}
    for dt in root.iter("DataType"):
        name_el = dt.find("Name")
        if name_el is None or not (name_el.text or "").strip():
            continue
        nombre = name_el.text.strip()
        subitems = dt.findall("SubItem")
        if not subitems:
            continue
        miembros = []
        for si in subitems:
            mn = si.find("Name")
            mt = si.find("Type")
            mb = si.find("BitSize")
            if mn is None or mt is None or mb is None:
                continue
            try:
                bits = int(mb.text or 0)
            except ValueError:
                continue
            miembros.append({
                "name": (mn.text or "").strip(),
                "type": (mt.text or "").strip(),
                "size": _bytes(bits),
            })
        if miembros:
            registry[nombre] = miembros
    return registry


def convertir(ruta_tpy, ruta_json):
    tree = ET.parse(ruta_tpy)
    root = tree.getroot()
    tipos = parsear_tipos(root)

    variables = []
    omitidos = 0
    for sym in root.iter("Symbol"):
        name_el = sym.find("Name")
        type_el = sym.find("Type")
        bit_el = sym.find("BitSize")
        if name_el is None or type_el is None or bit_el is None:
            omitidos += 1
            continue
        nombre = (name_el.text or "").strip()
        tipo = (type_el.text or "").strip()
        try:
            bits = int(bit_el.text or 0)
        except ValueError:
            omitidos += 1
            continue
        if not nombre or not tipo:
            omitidos += 1
            continue
        variables.append({"name": nombre, "type": tipo, "size": _bytes(bits)})

    with open(ruta_json, "w", encoding="utf-8") as f:
        json.dump({"types": tipos, "variables": variables}, f, indent=2, ensure_ascii=False)

    print(f"Estructuras: {len(tipos)} | Símbolos: {len(variables)} -> {ruta_json}")
    if omitidos:
        print(f"({omitidos} omitidos por falta de datos)")


if __name__ == "__main__":
    tpy = sys.argv[1] if len(sys.argv) > 1 else r"C:\DeepSeek Harness\libreriaAds\PLC_Portale.tpy"
    salida = sys.argv[2] if len(sys.argv) > 2 else r"C:\DeepSeek Harness\libreriaAds\simulador_flutter\variables.json"
    convertir(tpy, salida)

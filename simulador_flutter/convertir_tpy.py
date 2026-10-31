# -*- coding: utf-8 -*-
"""Convierte un archivo .tpy de TwinCAT (exportación de símbolos) a variables.json
para el simulador ADS.

Uso:
    python convertir_tpy.py <archivo.tpy> [salida.json]

Los tipos de datos propios de TwinCAT (structs, enums, FB) se convierten a una
matriz de bytes del tamaño correcto, para poder leer/escribir los bytes crudos
igual que harías por ADS contra el PLC real.
"""

import json
import re
import sys
import xml.etree.ElementTree as ET

# Tipos escalares soportados directamente por el simulador.
BASE_TYPES = {
    "BOOL", "BYTE", "SINT", "USINT", "INT", "UINT", "WORD",
    "DINT", "UDINT", "DWORD", "REAL", "TIME", "TOD", "DT", "DATE",
    "LINT", "ULINT", "LREAL",
}
NUMERIC_TYPES = BASE_TYPES - {"BOOL"}

_ARRAY_RE = re.compile(r"^ARRAY\s*\[([^\]]*)\]\s+OF\s+(.+)$", re.IGNORECASE)


def es_tipo_simple(tipo):
    """True si el tipo (posiblemente ARRAY anidado) termina en un tipo base."""
    t = tipo.strip().upper()
    if t in BASE_TYPES:
        return True
    if t.startswith("STRING(") or t.startswith("WSTRING("):
        return True
    m = _ARRAY_RE.match(t)
    if m:
        return es_tipo_simple(m.group(2))
    return False


def mapear_tipo(tipo, bit_size):
    """Devuelve el tipo en formato del simulador. Los tipos propios pasan a bytes."""
    t = tipo.strip()
    if es_tipo_simple(t):
        return t
    n = (bit_size + 7) // 8  # bytes (redondeo hacia arriba)
    return f"ARRAY [0..{n - 1}] OF BYTE"


def valor_por_defecto(tipo):
    """Valor inicial para tipos escalares; None = rellenar con ceros."""
    up = tipo.strip().upper()
    if up == "BOOL":
        return False
    if up in ("REAL", "LREAL"):
        return 0.0
    if up in NUMERIC_TYPES:
        return 0
    return None


def convertir(ruta_tpy, ruta_json):
    tree = ET.parse(ruta_tpy)
    root = tree.getroot()
    variables = []
    omitidos = 0
    for sym in root.iter("Symbol"):
        name_el = sym.find("Name")
        type_el = sym.find("Type")
        bit_el = sym.find("BitSize")
        if name_el is None or type_el is None or bit_el is None:
            continue
        name = (name_el.text or "").strip()
        tipo_bruto = (type_el.text or "").strip()
        try:
            bit_size = int(bit_el.text)
        except (TypeError, ValueError):
            omitidos += 1
            continue
        if not name or not tipo_bruto:
            omitidos += 1
            continue
        tipo = mapear_tipo(tipo_bruto, bit_size)
        item = {"name": name, "type": tipo}
        valor = valor_por_defecto(tipo)
        if valor is not None:
            item["value"] = valor
        variables.append(item)

    with open(ruta_json, "w", encoding="utf-8") as f:
        json.dump({"variables": variables}, f, indent=2, ensure_ascii=False)

    print(f"Convertidos {len(variables)} símbolos -> {ruta_json}")
    if omitidos:
        print(f"({omitidos} omitidos por falta de datos)")


if __name__ == "__main__":
    tpy = sys.argv[1] if len(sys.argv) > 1 else r"C:\DeepSeek Harness\libreriaAds\PLC_Portale.tpy"
    salida = sys.argv[2] if len(sys.argv) > 2 else r"C:\DeepSeek Harness\libreriaAds\simulador_flutter\variables.json"
    convertir(tpy, salida)

# LibPhithon — Cliente ADS en Python

Librería **pura** (sin dependencias externas) que implementa el protocolo
**ADS (Automation Device Specification)** de Beckhoff como cliente.

Sigue la especificación común en [`../PROTOCOL.md`](../PROTOCOL.md).

## Instalación

```bash
pip install -e .
```

No requiere ningún paquete de terceros (solo la biblioteca estándar de Python ≥ 3.8).

## Uso rápido

```python
from ads import AdsClient

with AdsClient(ams_net_id="127.0.0.1.1.1", ams_port=851,
               ip_address="127.0.0.1", tcp_port=48898) as c:
    state, dev = c.read_state()
    n = c.read_by_name("MAIN.nCounter", "UINT")
    c.write_by_name("MAIN.bStart", True, "BOOL")
    t = c.read_by_name("MAIN.fTemp", "REAL")
```

## API principal (`AdsClient`)

| Método | Descripción |
|--------|-------------|
| `open()` / `close()` / context manager | Gestión de conexión |
| `read_device_info()` | `(major, minor, build, name)` |
| `read_state()` | `(ads_state, device_state)` |
| `write_control(state, device_state, data)` | Cambiar estado |
| `read_by_name(name, plc_datatype=None)` | Lectura por nombre (0xF005) |
| `write_by_name(name, value, plc_datatype=None)` | Escritura por nombre |
| `get_handle(name)` / `release_handle(h)` | Handles de símbolo (0xF003 / 0xF014) |
| `read_by_handle(h, size)` / `write_by_handle(h, data)` | Acceso por handle (0xF004) |
| `read_symbol_info(name)` | Info de símbolo (0xF006) |
| `read_index(ig, io, size)` / `write_index(ig, io, data)` | Acceso directo por índice/offset |
| `read_write(ig, io, read_len, write_data)` | Comando 0x0009 |
| `sum_read(entries)` / `sum_write(entries)` | Comandos sum (0xF080 / 0xF081) |
| `add_device_notification(...)` / `del_device_notification(h)` | Notificaciones |

## Tipos PLC soportados

`BOOL`, `BYTE`, `SINT`, `USINT`, `INT`, `UINT`, `WORD`, `DINT`, `UDINT`,
`DWORD`, `REAL`, `TIME`, `TOD`, `DT`, `DATE`, `LINT`, `ULINT`, `LREAL`,
`STRING(n)`, `WSTRING(n)` y `ARRAY[a..b] OF T`.

## Pruebas

```bash
python -m unittest discover -s tests -v
```

## Ejemplo contra el simulador

Con el simulador Flutter en marcha (ver `../simulador_flutter/README.md`):

```bash
python examples/example.py
```

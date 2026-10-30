# simulador_flutter — Servidor ADS (simula un PLC TwinCAT)

Simulador de dispositivo **ADS (Automation Device Specification)** de Beckhoff
implementado en **Dart/Flutter**. Actúa como **servidor**: los clientes
`LibPhithon` (Python) y `LibC#` (C#) se conectan por TCP y leen/escriben las
variables PLC simuladas.

Sigue la especificación común en [`../PROTOCOL.md`](../PROTOCOL.md).

## Modos de ejecución

### 1. Sin interfaz (headless, solo Dart)

```bash
dart bin/server.dart            # puerto 48898
dart bin/server.dart 48000      # puerto personalizado
```

No requiere compilar Flutter; basta el SDK de Dart (incluido con Flutter).

### 2. Con interfaz gráfica (Flutter)

```bash
flutter run -d windows          # (o -d linux / -d macos)
```

La UI permite arrancar/detener el servidor, cambiar el puerto, ver en vivo las
variables (incluido `MAIN.nCounter` que se incrementa cada 500 ms en RUN) y
editarlas, además de un registro de conexiones.

## Configuración de red

| Parámetro | Valor |
|-----------|-------|
| Dirección TCP | `127.0.0.1:48898` (configurable) |
| AmsNetId | `127.0.0.1.1.1` |
| Puerto AMS (runtime PLC) | `851` |

## Variables simuladas

| Símbolo | Tipo | Valor inicial |
|---------|------|---------------|
| `MAIN.bStart` | BOOL | `false` |
| `MAIN.bStop` | BOOL | `true` |
| `MAIN.nCounter` | UINT | `0` (se incrementa cada 500 ms en RUN) |
| `MAIN.iLevel` | INT | `100` |
| `MAIN.fTemp` | REAL | `21.5` |
| `MAIN.dPosition` | LREAL | `1.2345` |
| `MAIN.sMessage` | STRING(80) | `"Hola ADS"` |
| `MAIN.arrValues` | ARRAY[0..3] OF INT | `[1, 2, 3, 4]` |

## Comandos ADS soportados

- `READ_DEVICE_INFO`, `READ_STATE`, `WRITE_CONTROL`
- `READ`/`WRITE` por nombre, por handle, handle-por-nombre, info de símbolo,
  tabla de símbolos e imagen de proceso (entradas/salidas)
- `READ_WRITE`
- `SUMUP_READ` y `SUMUP_WRITE`
- `ADD/DEL/DEVICE_NOTIFICATION` (notificaciones por cambio y por ciclo)

## Estructura

```
simulador_flutter/
├── pubspec.yaml
├── bin/server.dart            # servidor headless (Dart puro)
└── lib/
    ├── main.dart              # interfaz Flutter
    ├── ads/                   # núcleo del protocolo (Dart puro)
    │   ├── ams_header.dart
    │   ├── constants.dart
    │   └── datatypes.dart
    └── simulator/             # lógica del PLC simulado
        ├── ads_server.dart
        ├── device.dart
        └── symbol_table.dart
```

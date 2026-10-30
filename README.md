# libreriaAds

Librerías **independientes** que implementan el protocolo de comunicaciones
**ADS (Automation Device Specification)** de Beckhoff, más un **simulador** de
dispositivo (PLC) en Flutter para probarlas.

## Componentes

| Componente | Lenguaje | Rol |
|------------|----------|-----|
| [`LibPhithon/`](LibPhithon/) | Python (sin dependencias) | Cliente ADS |
| [`LibC#/`](LibC#/) | C# / .NET 6 (sin NuGet) | Cliente ADS |
| [`simulador_flutter/`](simulador_flutter/) | Dart / Flutter | Servidor ADS (simula un PLC TwinCAT) |

Las tres piezas comparten un único contrato de interoperabilidad:
[`PROTOCOL.md`](PROTOCOL.md).

## Inicio rápido

1. **Arranca el simulador** (servidor ADS en `127.0.0.1:48898`):

   ```bash
   cd simulador_flutter
   dart bin/server.dart            # headless, sin UI
   # o: flutter run -d windows      # con interfaz gráfica
   ```

2. **Prueba con Python**:

   ```bash
   cd LibPhithon
   pip install -e .
   python examples/example.py
   ```

3. **Prueba con C#**:

   ```bash
   cd LibC#/examples/AdsExample
   dotnet run
   ```

## Documentación

La documentación amplia y detallada está en [`docs/`](docs/):

- [Arquitectura y proceso general](docs/01-arquitectura.md)
- [Manual de la librería Python](docs/02-manual-python.md)
- [Manual de la librería C#](docs/03-manual-csharp.md)
- [Manual del simulador Flutter](docs/04-manual-simulador.md)
- [Guía de integración y pruebas](docs/05-guia-integracion.md)

## Pruebas

```bash
# Python
cd LibPhithon && python -m unittest discover -s tests -v

# C#
cd LibC#/tests/Ads.Tests && dotnet run
```

## Licencia

MIT.

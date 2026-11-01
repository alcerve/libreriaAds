# Documentación de libreriaAds

Repositorio con dos librerías **independientes** (Python y C#) que implementan el
protocolo **ADS (Automation Device Specification)** de Beckhoff, más un
**simulador** en Flutter/Dart para probarlas.

## Índice de documentación

1. [Arquitectura y proceso general](01-arquitectura.md) — visión global, piezas
   del sistema, formato de cable ADS/TCP y flujo de trabajo.
2. [Manual de la librería Python (LibPhithon)](02-manual-python.md) — instalación,
   uso y referencia completa de cada función.
3. [Manual de la librería C# (LibC#)](03-manual-csharp.md) — compilación, uso y
   referencia completa de cada clase y método.
4. [Manual del simulador Flutter](04-manual-simulador.md) — cómo ejecutarlo,
   variables expuestas y comportamiento del servidor.
5. [Guía de integración y pruebas](05-guia-integracion.md) — cómo probar las tres
   piezas juntas, paso a paso.
6. [Manual del log de tramas ADS](06-manual-tramas.md) — cómo leer la trama en
   hexadecimal y qué significa cada campo del log de comunicación.
7. [Manual del programador](07-manual-programador.md) — cómo compilar y usar las
   dos librerías: qué método llamar y con qué parámetros.

## Lectura rápida

| ¿Qué quieres hacer? | Dónde mirar |
|---|---|
| Entender el protocolo ADS a nivel de bytes | [`../PROTOCOL.md`](../PROTOCOL.md) y [`01-arquitectura.md`](01-arquitectura.md) |
| Usar la librería Python | [`02-manual-python.md`](02-manual-python.md) |
| Usar la librería C# | [`03-manual-csharp.md`](03-manual-csharp.md) |
| Arrancar el simulador | [`04-manual-simulador.md`](04-manual-simulador.md) |
| Probar todo el conjunto | [`05-guia-integracion.md`](05-guia-integracion.md) |
| Compilar y usar las librerías (métodos + parámetros) | [`07-manual-programador.md`](07-manual-programador.md) |

## Estructura del repositorio

```
libreriaAds/
├── PROTOCOL.md          # Especificación común del protocolo ADS (contrato)
├── README.md            # Descripción general del repositorio
├── docs/                # Documentación amplia y detallada (este directorio)
├── LibPhithon/          # Librería cliente ADS en Python
├── LibC#/               # Librería cliente ADS en C# / .NET
└── simulador_flutter/   # Servidor ADS (simula un PLC TwinCAT) en Flutter/Dart
```

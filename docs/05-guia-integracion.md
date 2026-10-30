# 5. Guía de integración y pruebas

Esta guía describe el proceso completo: desde arrancar el simulador hasta probar
las dos librerías cliente.

## 5.1. Requisitos previos

- Python ≥ 3.8.
- SDK de .NET 6.0.
- SDK de Flutter (con Dart).

## 5.2. Paso 1 — Arrancar el simulador

Opción headless:

```bash
cd libreriaAds/simulador_flutter
dart bin/server.dart
```

Verás en consola:

```
Escuchando en 127.0.0.1:48898 (NetId 127.0.0.1.1.1, puerto AMS 851)
```

Opción con interfaz:

```bash
cd libreriaAds/simulador_flutter
flutter run -d windows
```

## 5.3. Paso 2 — Probar la librería Python

```bash
cd libreriaAds/LibPhithon
python examples/example.py
```

Salida esperada (valores pueden variar según el momento):

```
Device info: v3.1 (build 0) 'ADS-Simulator'
Estado ADS: 5, estado dispositivo: 0
nCounter=12  fTemp=21.50  sMessage="Hola ADS"  arrValues=[1, 2, 3, 4]
MAIN.bStart -> True
...
```

## 5.4. Paso 3 — Probar la librería C#

```bash
cd libreriaAds/LibC#/examples/AdsExample
dotnet run
```

## 5.5. Paso 4 — Pruebas unitarias (sin simulador)

Python:

```bash
cd libreriaAds/LibPhithon
python -m unittest discover -s tests -v
```

C#:

```bash
cd libreriaAds/LibC#/tests/Ads.Tests
dotnet run
```

## 5.6. Comprobación de interoperabilidad

Las pruebas unitarias de Python y C# levantan un **mini servidor ADS en hilo**
(in-memory) y validan el cliente contra él. El simulador Flutter, a su vez, usa
exactamente el mismo formato de cable definido en `PROTOCOL.md`, por lo que las
tres piezas son interoperables.

Para una comprobación de extremo a extremo:

1. Arranca el simulador (paso 1).
2. Ejecuta `python examples/example.py` (debe leer/escribir sin errores).
3. Ejecuta `dotnet run` en `examples/AdsExample` (debe leer/escribir sin errores).
4. Suscribe una notificación a `MAIN.nCounter` y comprueba que recibes muestras
   cada 500 ms (el contador se incrementa en estado RUN).

## 5.7. Errores comunes

| Síntoma | Causa probable |
|---------|----------------|
| `Timeout agotado` (0x745) | El simulador no está en marcha o el puerto TCP no coincide. |
| `Símbolo no encontrado` (0x710) | El nombre de la variable no coincide con los expuestos (`MAIN.*`). |
| `Host inalcanzable` | La conexión TCP se cerró; verifica dirección y puerto. |

# LibC# — Cliente ADS en C# / .NET

Librería **independiente** que implementa el protocolo **ADS (Automation Device
Specification)** de Beckhoff como cliente, sin paquetes NuGet externos
(solo la BCL de .NET 6.0).

Sigue la especificación común en [`../PROTOCOL.md`](../PROTOCOL.md).

## Estructura

```
LibC#/
├── src/Beckhoff.Ads/       # biblioteca de clases (net6.0)
├── examples/AdsExample/    # aplicación de consola de ejemplo
└── tests/Ads.Tests/        # runner de pruebas propio (sin xUnit)
```

## Compilar

```bash
dotnet build src/Beckhoff.Ads/Beckhoff.Ads.csproj
```

## Pruebas

```bash
cd tests/Ads.Tests && dotnet run
```

## Ejemplo contra el simulador

Con el simulador Flutter en marcha (ver `../simulador_flutter/README.md`):

```bash
cd examples/AdsExample && dotnet run
```

## Uso rápido

```csharp
using Beckhoff.Ads;

using var client = new TcAdsClient(
    amsNetId: "127.0.0.1.1.1",
    amsPort: AdsPorts.PlcTc3,
    ipAddress: "127.0.0.1",
    tcpPort: AdsPorts.TcpPort);

client.Connect();

var (state, deviceState) = client.ReadState();
ushort counter = client.ReadValue<ushort>("MAIN.nCounter", "UINT");
client.WriteValue<bool>("MAIN.bStart", true, "BOOL");
float temp = client.ReadValue<float>("MAIN.fTemp", "REAL");
string msg = client.ReadValue<string>("MAIN.sMessage", "STRING(80)");
```

## API principal (`TcAdsClient`)

| Método | Descripción |
|--------|-------------|
| `Connect()` / `Disconnect()` / `Dispose()` | Gestión de conexión |
| `ReadDeviceInfo()` | `AdsDeviceInfo` (0x0001) |
| `ReadState()` | `(AdsState, ushort)` (0x0004) |
| `WriteControl(state, deviceState, data)` | Cambiar estado (0x0005) |
| `ReadAny(ig, io, length)` / `WriteAny(ig, io, data)` | Acceso por índice/offset |
| `ReadWrite(ig, io, readLen, writeData)` | Comando 0x0009 |
| `ReadSymbol(name[, size|plcType])` / `WriteSymbol(name, value)` | Acceso por nombre (0xF005) |
| `CreateVariableHandle(name)` / `DeleteVariableHandle(h)` | Handles (0xF003 / 0xF014) |
| `ReadByHandle(h, len)` / `WriteByHandle(h, data)` | Acceso por handle (0xF004) |
| `GetSymbolInfo(name)` | Info de símbolo (0xF006) |
| `SumRead(entries)` / `SumWrite(entries)` | Comandos sum (0xF080 / 0xF081) |
| `AddDeviceNotification(...)` / `DeleteDeviceNotification(h)` | Notificaciones |
| `ReadValue<T>(name[, plcType])` / `WriteValue<T>(...)` | Acceso tipado |
| `ReadStruct<T>(name)` / `WriteStruct<T>(...)` | Structs `[StructLayout(Sequential, Pack=1)]` |

## Tipos PLC soportados

`BOOL`, `BYTE`, `SINT`, `USINT`, `INT`, `UINT`, `WORD`, `DINT`, `UDINT`,
`DWORD`, `REAL`, `TIME`, `TOD`, `DT`, `DATE`, `LINT`, `ULINT`, `LREAL`,
`STRING(n)`, `WSTRING(n)` y `ARRAY[a..b] OF T`.

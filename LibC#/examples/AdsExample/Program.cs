using System;
using System.Threading;
using Beckhoff.Ads;

// Ejemplo de uso contra el simulador Flutter (127.0.0.1:48898, AMS 127.0.0.1.1.1:851).
// Ejecutar: dotnet run
class Program
{
    static void Main(string[] args)
    {
        // Argumentos opcionales: [puerto_tcp] [ams_net_id] [ams_port] [ip]
        int tcpPort = args.Length > 0 && int.TryParse(args[0], out var p) ? p : AdsPorts.TcpPort;
        string amsNetId = args.Length > 1 ? args[1] : "127.0.0.1.1.1";
        ushort amsPort = args.Length > 2 && ushort.TryParse(args[2], out var ap) ? ap : AdsPorts.PlcTc3;
        string ipAddress = args.Length > 3 ? args[3] : "127.0.0.1";

        using var client = new TcAdsClient(
            amsNetId: amsNetId,
            amsPort: amsPort,
            ipAddress: ipAddress,
            tcpPort: tcpPort,
            timeoutMs: 5000);

        client.Connect();
        Console.WriteLine("Conectado.");

        var info = client.ReadDeviceInfo();
        Console.WriteLine($"Device info: {info}");

        var (state, deviceState) = client.ReadState();
        Console.WriteLine($"Estado ADS: {state}, estado dispositivo: {deviceState}");

        ushort counter = client.ReadValue<ushort>("MAIN.nCounter", "UINT");
        float temp = client.ReadValue<float>("MAIN.fTemp", "REAL");
        string message = client.ReadValue<string>("MAIN.sMessage", "STRING(80)");
        Console.WriteLine($"nCounter={counter}  fTemp={temp:F2}  sMessage=\"{message}\"");

        client.WriteValue<bool>("MAIN.bStart", true, "BOOL");
        Console.WriteLine($"MAIN.bStart -> {client.ReadValue<bool>("MAIN.bStart", "BOOL")}");

        uint h = client.CreateVariableHandle("MAIN.iLevel");
        Console.WriteLine($"Handle de MAIN.iLevel: {h}");
        var raw = client.ReadByHandle(h, 2);
        Console.WriteLine($"iLevel (crudo): {raw.Length} bytes");
        client.DeleteVariableHandle(h);

        // Notificación: observar cambios de MAIN.nCounter (se incrementa cada 500 ms).
        using var received = new ManualResetEventSlim();
        uint notifHandle = 0;
        notifHandle = client.AddNotificationByName(
            "MAIN.nCounter", AdsTransMode.ServerOnChange, 0, 1000000,
            stamp =>
            {
                ushort value = System.Buffers.Binary.BinaryPrimitives.ReadUInt16LittleEndian(stamp.Data);
                Console.WriteLine($"  Notificación nCounter={value}");
                received.Set();
            });

        Console.WriteLine("Esperando notificación de nCounter (2 s)...");
        received.Wait(2000);
        client.DeleteDeviceNotification(notifHandle);

        client.Disconnect();
        Console.WriteLine("Desconectado.");
    }
}

using System;
using System.Buffers.Binary;
using System.Collections.Concurrent;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Beckhoff.Ads;

// Runner de pruebas propio (sin paquetes externos). Ejecutar: dotnet run
internal static class TestRunner
{
    private static int _passed;
    private static int _failed;

    private static void Check(bool condition, string name)
    {
        if (condition) { _passed++; Console.WriteLine($"  OK    {name}"); }
        else { _failed++; Console.WriteLine($"  FALLO {name}"); }
    }

    private static int Main()
    {
        Console.WriteLine("== Ads.Tests ==\n");

        AmsNetIdTests();
        AmsHeaderTests();
        PlcTypeTests();
        ClientTests();

        Console.WriteLine($"\nResultado: {_passed} OK, {_failed} fallos");
        return _failed == 0 ? 0 : 1;
    }

    private static void AmsNetIdTests()
    {
        Console.WriteLine("AmsNetId");
        var nid = AmsNetId.Parse("192.168.0.1.1.1");
        Check(nid.ToString() == "192.168.0.1.1.1", "ToString roundtrip");
        var bytes = nid.ToByteArray();
        Check(bytes.Length == 6 && bytes[0] == 192 && bytes[5] == 1, "ToByteArray");
        Check(AmsNetId.FromByteArray(bytes).Equals(nid), "FromByteArray");
        Check(AmsNetId.Empty.IsEmpty, "Empty.IsEmpty");
        Check(AmsNetId.Parse("127.0.0.1.1.1") == AmsNetId.Parse("127.0.0.1.1.1"), "igualdad");
    }

    private static void AmsHeaderTests()
    {
        Console.WriteLine("AmsHeader/AmsTcpHeader");
        var header = new AmsHeader
        {
            TargetNetId = AmsNetId.Parse("127.0.0.1.1.1"),
            TargetPort = 851,
            SourceNetId = AmsNetId.Parse("127.0.0.1.1.1"),
            SourcePort = 1234,
            CommandId = AdsCommands.Read,
            StateFlags = 0,
            Length = 4,
            ErrorCode = 0,
            InvokeId = 7,
        };
        var buf = new byte[AmsHeader.Size];
        header.Write(buf);
        var back = AmsHeader.Read(buf);
        Check(back.CommandId == AdsCommands.Read && back.InvokeId == 7 && back.TargetPort == 851, "AmsHeader roundtrip");

        var tcp = new AmsTcpHeader(42);
        var tcpBuf = new byte[AmsTcpHeader.Size];
        tcp.Write(tcpBuf);
        var tcpBack = AmsTcpHeader.Read(tcpBuf);
        Check(tcpBack.Length == 42 && tcpBack.Reserved == 0, "AmsTcpHeader roundtrip");
    }

    private static void PlcTypeTests()
    {
        Console.WriteLine("PlcType");
        Check(PlcType.SizeOf("BOOL") == 1, "SizeOf BOOL");
        Check(PlcType.SizeOf("INT") == 2, "SizeOf INT");
        Check(PlcType.SizeOf("REAL") == 4, "SizeOf REAL");
        Check(PlcType.SizeOf("LREAL") == 8, "SizeOf LREAL");
        Check(PlcType.SizeOf("STRING(80)") == 81, "SizeOf STRING(80)");
        Check(PlcType.SizeOf("ARRAY[0..3] OF INT") == 8, "SizeOf ARRAY");

        Check((short)PlcType.Decode(PlcType.Encode((short)-1234, "INT"), "INT") == -1234, "INT roundtrip");
        Check(Math.Abs((float)PlcType.Decode(PlcType.Encode(1.5f, "REAL"), "REAL") - 1.5f) < 1e-6, "REAL roundtrip");
        Check((string)PlcType.Decode(PlcType.Encode("Hola", "STRING(80)"), "STRING(80)") == "Hola", "STRING roundtrip");

        var arr = new int[] { 1, 2, 3, 4 };
        var decodedArr = (object[])PlcType.Decode(PlcType.Encode(arr, "ARRAY[0..3] OF INT"), "ARRAY[0..3] OF INT");
        Check(decodedArr.Length == 4 && (short)decodedArr[3] == 4, "ARRAY roundtrip");
    }

    private static void ClientTests()
    {
        Console.WriteLine("TcAdsClient (contra mini servidor)");
        using var server = new MiniAdsServer();
        using var client = new TcAdsClient(ipAddress: "127.0.0.1", tcpPort: server.Port, timeoutMs: 3000);
        client.Connect();

        var (state, devState) = client.ReadState();
        Check(state == AdsState.Run && devState == 0, "ReadState");

        var info = client.ReadDeviceInfo();
        Check(info.MajorVersion == 3 && info.DeviceName == "MiniSim", "ReadDeviceInfo");

        Check(Math.Abs(client.ReadValue<float>("MAIN.fTemp", "REAL") - 21.5f) < 1e-5, "ReadValue<float>");

        client.WriteValue<ushort>("MAIN.nCounter", 42, "UINT");
        Check(client.ReadValue<ushort>("MAIN.nCounter", "UINT") == 42, "WriteValue/ReadValue");

        Check(client.CreateVariableHandle("MAIN.iLevel") == 0x12345678, "CreateVariableHandle");

        try
        {
            client.ReadAny(0x9999, 0, 4);
            Check(false, "grupo inválido lanza AdsException");
        }
        catch (AdsException ex)
        {
            Check(ex.ErrorCode == AdsErrorCode.InvalidIndexGroup, "grupo inválido lanza AdsException");
        }

        client.Disconnect();
    }
}

internal sealed class MiniAdsServer : IDisposable
{
    public int Port { get; }
    private readonly TcpListener _listener;
    private readonly CancellationTokenSource _cts = new();
    public ConcurrentDictionary<string, byte[]> Vars { get; } = new();

    public MiniAdsServer()
    {
        _listener = new TcpListener(IPAddress.Loopback, 0);
        _listener.Start();
        Port = ((IPEndPoint)_listener.LocalEndpoint).Port;
        Vars["MAIN.nCounter"] = new byte[] { 0, 0 };
        Vars["MAIN.fTemp"] = new byte[4];
        BinaryPrimitives.WriteSingleLittleEndian(Vars["MAIN.fTemp"], 21.5f);
        _ = Task.Run(AcceptLoop);
    }

    private async Task AcceptLoop()
    {
        while (!_cts.IsCancellationRequested)
        {
            TcpClient client;
            try { client = await _listener.AcceptTcpClientAsync(); }
            catch { break; }
            _ = Task.Run(() => Handle(client));
        }
    }

    private void Handle(TcpClient client)
    {
        using (client)
        {
            var stream = client.GetStream();
            var buf = new byte[1024 * 1024];
            try
            {
                while (true)
                {
                    ReadExact(stream, buf, 0, AmsTcpHeader.Size);
                    uint length = BinaryPrimitives.ReadUInt32LittleEndian(buf.AsSpan(2, 4));
                    if (length < AmsHeader.Size) break;
                    ReadExact(stream, buf, AmsTcpHeader.Size, (int)length);
                    var header = AmsHeader.Read(buf.AsSpan(AmsTcpHeader.Size, AmsHeader.Size));
                    var data = new byte[length - AmsHeader.Size];
                    Array.Copy(buf, AmsTcpHeader.Size + AmsHeader.Size, data, 0, data.Length);
                    Respond(stream, header, data);
                }
            }
            catch { /* cerrado */ }
        }
    }

    private void Respond(NetworkStream stream, AmsHeader header, byte[] data)
    {
        byte[] response;
        switch (header.CommandId)
        {
            case AdsCommands.ReadState:
                response = BuildResponse(header, new byte[] { 5, 0, 0, 0 });
                break;
            case AdsCommands.ReadDeviceInfo:
                var info = new byte[20];
                info[0] = 3; info[1] = 1;
                Encoding.ASCII.GetBytes("MiniSim").CopyTo(info, 4);
                response = BuildResponse(header, info);
                break;
            case AdsCommands.Read:
                response = HandleRead(header, data);
                break;
            case AdsCommands.Write:
                response = HandleWrite(header, data);
                break;
            default:
                response = BuildResponse(header, Array.Empty<byte>(), AdsErrorCode.ServiceNotSupported);
                break;
        }
        stream.Write(response, 0, response.Length);
        stream.Flush();
    }

    private byte[] HandleRead(AmsHeader header, byte[] data)
    {
        uint ig = BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(0, 4));
        if (ig == AdsIndexGroups.SymValByName)
        {
            int nameLen = (int)BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(8, 4));
            string name = Encoding.UTF8.GetString(data, 12, nameLen);
            int size = (int)BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(12 + nameLen, 4));
            var value = Vars.TryGetValue(name, out var v) ? v : new byte[size];
            if (value.Length != size)
            {
                var tmp = new byte[size];
                Array.Copy(value, tmp, Math.Min(size, value.Length));
                value = tmp;
            }
            return BuildResponse(header, value);
        }
        if (ig == AdsIndexGroups.SymHndByName)
        {
            var h = new byte[4];
            BinaryPrimitives.WriteUInt32LittleEndian(h, 0x12345678);
            return BuildResponse(header, h);
        }
        return BuildResponse(header, Array.Empty<byte>(), AdsErrorCode.InvalidIndexGroup);
    }

    private byte[] HandleWrite(AmsHeader header, byte[] data)
    {
        uint ig = BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(0, 4));
        if (ig == AdsIndexGroups.SymValByName)
        {
            int nameLen = (int)BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(8, 4));
            string name = Encoding.UTF8.GetString(data, 12, nameLen);
            int dataLen = (int)BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(12 + nameLen, 4));
            var value = new byte[dataLen];
            Array.Copy(data, 16 + nameLen, value, 0, dataLen);
            Vars[name] = value;
            return BuildResponse(header, Array.Empty<byte>());
        }
        return BuildResponse(header, Array.Empty<byte>(), AdsErrorCode.InvalidIndexGroup);
    }

    private static byte[] BuildResponse(AmsHeader request, byte[] data, uint error = 0)
    {
        var header = new AmsHeader
        {
            TargetNetId = request.SourceNetId,
            TargetPort = request.SourcePort,
            SourceNetId = request.TargetNetId,
            SourcePort = request.TargetPort,
            CommandId = request.CommandId,
            StateFlags = 1,
            Length = (uint)data.Length,
            ErrorCode = error,
            InvokeId = request.InvokeId,
        };
        var ams = new byte[AmsHeader.Size + data.Length];
        header.Write(ams);
        data.CopyTo(ams, AmsHeader.Size);
        var frame = new byte[AmsTcpHeader.Size + ams.Length];
        new AmsTcpHeader((uint)ams.Length).Write(frame);
        ams.CopyTo(frame, AmsTcpHeader.Size);
        return frame;
    }

    private static void ReadExact(NetworkStream stream, byte[] buffer, int offset, int count)
    {
        int read = 0;
        while (read < count)
        {
            int n = stream.Read(buffer, offset + read, count - read);
            if (n <= 0) throw new EndOfStreamException();
            read += n;
        }
    }

    public void Dispose()
    {
        _cts.Cancel();
        _listener.Stop();
    }
}

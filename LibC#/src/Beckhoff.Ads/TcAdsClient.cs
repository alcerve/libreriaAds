using System;
using System.Buffers.Binary;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Beckhoff.Ads;

/// <summary>Cliente del protocolo ADS de Beckhoff (con soporte de notificaciones).</summary>
public sealed class TcAdsClient : IDisposable
{
    private readonly AmsNetId _localNetId = AmsNetId.Parse("127.0.0.1.1.1");
    private readonly ushort _localAmsPort;

    private TcpClient? _tcp;
    private NetworkStream? _stream;
    private readonly object _sendLock = new();
    private int _invokeIdCounter;
    private readonly CancellationTokenSource _cts = new();

    private readonly ConcurrentDictionary<uint, TaskCompletionSource<AdsResponse>> _pending = new();
    private readonly ConcurrentDictionary<uint, Action<NotificationStamp>> _notifications = new();

    public AmsNetId TargetNetId { get; }
    public ushort AmsPort { get; }
    public string IpAddress { get; }
    public int TcpPort { get; }
    public int TimeoutMs { get; }
    public bool IsConnected => _tcp?.Connected == true;

    public TcAdsClient(
        string amsNetId = "127.0.0.1.1.1",
        ushort amsPort = AdsPorts.PlcTc3,
        string ipAddress = "127.0.0.1",
        int tcpPort = AdsPorts.TcpPort,
        int timeoutMs = 5000)
    {
        TargetNetId = AmsNetId.Parse(amsNetId);
        AmsPort = amsPort;
        IpAddress = ipAddress;
        TcpPort = tcpPort;
        TimeoutMs = timeoutMs;
        _localAmsPort = (ushort)new Random().Next(2000, 60000);
    }

    // ------------------------------------------------------------------ ciclo
    public void Connect()
    {
        if (_tcp != null) return;
        _tcp = new TcpClient();
        _tcp.Connect(IpAddress, TcpPort);
        _stream = _tcp.GetStream();
        _ = Task.Run(ReaderLoop);
    }

    public void Disconnect()
    {
        _cts.Cancel();
        try { _stream?.Close(); } catch { }
        try { _tcp?.Close(); } catch { }
        _stream = null;
        _tcp = null;
        FailAllPending();
    }

    public void Dispose() => Disconnect();

    // ------------------------------------------------------------------ lector
    private void ReaderLoop()
    {
        var buffer = new byte[1024 * 1024];
        try
        {
            while (!_cts.IsCancellationRequested)
            {
                ReadExact(buffer, 0, AmsTcpHeader.Size);
                uint length = BinaryPrimitives.ReadUInt32LittleEndian(buffer.AsSpan(2, 4));
                if (length < AmsHeader.Size || length > buffer.Length - AmsTcpHeader.Size)
                    continue;
                ReadExact(buffer, AmsTcpHeader.Size, (int)length);
                var header = AmsHeader.Read(buffer.AsSpan(AmsTcpHeader.Size, AmsHeader.Size));
                int dataLen = (int)length - AmsHeader.Size;
                var data = new byte[dataLen];
                Array.Copy(buffer, AmsTcpHeader.Size + AmsHeader.Size, data, 0, dataLen);
                Dispatch(header, data);
            }
        }
        catch
        {
            // Conexión cerrada o error de socket.
        }
        finally
        {
            FailAllPending();
        }
    }

    private void ReadExact(byte[] buffer, int offset, int count)
    {
        int read = 0;
        while (read < count)
        {
            int n = _stream!.Read(buffer, offset + read, count - read);
            if (n <= 0) throw new IOException("Conexión cerrada por el servidor ADS");
            read += n;
        }
    }

    private void Dispatch(AmsHeader header, byte[] data)
    {
        if (header.CommandId == AdsCommands.DeviceNotification)
        {
            HandleNotification(data);
            return;
        }
        if (_pending.TryRemove(header.InvokeId, out var tcs))
            tcs.TrySetResult(new AdsResponse(header.CommandId, header.ErrorCode, data));
    }

    private void FailAllPending()
    {
        foreach (var key in _pending.Keys)
        {
            if (_pending.TryRemove(key, out var tcs))
                tcs.TrySetResult(new AdsResponse(0, AdsErrorCode.HostUnreachable, Array.Empty<byte>()));
        }
    }

    private void HandleNotification(byte[] data)
    {
        if (data.Length < 4) return;
        int total = (int)BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(0, 4));
        int off = 4;
        int end = Math.Min(4 + total, data.Length);
        while (off + 16 <= end)
        {
            uint handle = BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(off, 4));
            ulong timestamp = BinaryPrimitives.ReadUInt64LittleEndian(data.AsSpan(off + 4, 8));
            uint sampleSize = BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(off + 12, 4));
            off += 16;
            var sample = new byte[sampleSize];
            Array.Copy(data, off, sample, 0, Math.Min((int)sampleSize, data.Length - off));
            off += (int)sampleSize;
            if (_notifications.TryGetValue(handle, out var callback))
                callback?.Invoke(new NotificationStamp(handle, timestamp, sample));
        }
    }

    // ------------------------------------------------------------------ request
    private static byte[] BuildFrame(AmsHeader header, byte[] data)
    {
        var ams = new byte[AmsHeader.Size + data.Length];
        header.Length = (uint)data.Length;
        header.Write(ams);
        data.CopyTo(ams, AmsHeader.Size);
        var frame = new byte[AmsTcpHeader.Size + ams.Length];
        new AmsTcpHeader((uint)ams.Length).Write(frame);
        ams.CopyTo(frame, AmsTcpHeader.Size);
        return frame;
    }

    private AdsResponse Request(ushort commandId, byte[] data)
    {
        // Flujo: reservar invoke_id -> registrar TCS -> enviar -> esperar -> validar error.
        if (_stream == null) throw new AdsException(AdsErrorCode.TargetPortNotFound, "Cliente no conectado (llama a Connect())");

        // invoke_id correlaciona petición y respuesta (campo de la cabecera AMS).
        uint invokeId = unchecked((uint)Interlocked.Increment(ref _invokeIdCounter));
        var tcs = new TaskCompletionSource<AdsResponse>(TaskCreationOptions.RunContinuationsAsynchronously);
        _pending[invokeId] = tcs; // el lector completará esta tarea al llegar la respuesta

        // Cabecera AMS de solicitud: destino = PLC, origen = cliente local, flags=0.
        var header = new AmsHeader
        {
            TargetNetId = TargetNetId,
            TargetPort = AmsPort,
            SourceNetId = _localNetId,
            SourcePort = _localAmsPort,
            CommandId = commandId,
            StateFlags = 0,   // 0 = solicitud (1 = respuesta, 4 = notificación)
            InvokeId = invokeId,
        };

        // Frame AMS/TCP = 6 bytes (reservado + longitud) + cabecera AMS (32) + datos.
        var frame = BuildFrame(header, data);
        try
        {
            lock (_sendLock) // serializa escrituras si varios hilos envían a la vez
            {
                _stream.Write(frame, 0, frame.Length);
                _stream.Flush();
            }
        }
        catch (Exception ex)
        {
            _pending.TryRemove(invokeId, out _);
            throw new AdsException(AdsErrorCode.HostUnreachable, $"Fallo al enviar: {ex.Message}");
        }

        // Espera la respuesta con timeout; el lector completa la tarea al correlacionar invoke_id.
        if (!tcs.Task.Wait(TimeoutMs))
        {
            _pending.TryRemove(invokeId, out _);
            throw new AdsException(AdsErrorCode.TimeoutElapsed);
        }

        var resp = tcs.Task.Result;
        if (resp.ErrorCode != 0) // el PLC devolvió un código de error ADS
            throw new AdsException(resp.ErrorCode);
        return resp;
    }

    // ------------------------------------------------------------------ info
    public AdsDeviceInfo ReadDeviceInfo() =>
        AdsDeviceInfo.Parse(Request(AdsCommands.ReadDeviceInfo, Array.Empty<byte>()).Data);

    public (AdsState State, ushort DeviceState) ReadState()
    {
        var data = Request(AdsCommands.ReadState, Array.Empty<byte>()).Data;
        return ((AdsState)BinaryPrimitives.ReadUInt16LittleEndian(data.AsSpan(0, 2)),
                BinaryPrimitives.ReadUInt16LittleEndian(data.AsSpan(2, 2)));
    }

    public void WriteControl(AdsState state, ushort deviceState, byte[]? data = null)
    {
        data ??= Array.Empty<byte>();
        var payload = new byte[8 + data.Length];
        BinaryPrimitives.WriteUInt16LittleEndian(payload, (ushort)state);
        BinaryPrimitives.WriteUInt16LittleEndian(payload.AsSpan(2), deviceState);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(4), (uint)data.Length);
        data.CopyTo(payload, 8);
        Request(AdsCommands.WriteControl, payload);
    }

    // ------------------------------------------------------------------ acceso raw
    public byte[] ReadAny(uint indexGroup, uint indexOffset, int length)
    {
        var payload = new byte[12];
        BinaryPrimitives.WriteUInt32LittleEndian(payload, indexGroup);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(4), indexOffset);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(8), (uint)length);
        return Request(AdsCommands.Read, payload).Data;
    }

    public void WriteAny(uint indexGroup, uint indexOffset, byte[] data)
    {
        var payload = new byte[12 + data.Length];
        BinaryPrimitives.WriteUInt32LittleEndian(payload, indexGroup);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(4), indexOffset);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(8), (uint)data.Length);
        data.CopyTo(payload, 12);
        Request(AdsCommands.Write, payload);
    }

    public byte[] ReadWrite(uint indexGroup, uint indexOffset, int readLength, byte[] writeData)
    {
        var payload = new byte[16 + writeData.Length];
        BinaryPrimitives.WriteUInt32LittleEndian(payload, indexGroup);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(4), indexOffset);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(8), (uint)readLength);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(12), (uint)writeData.Length);
        writeData.CopyTo(payload, 16);
        return Request(AdsCommands.ReadWrite, payload).Data;
    }

    // ------------------------------------------------------------------ símbolos
    public byte[] ReadSymbol(string name, int size)
    {
        // Payload de lectura por nombre:
        //   [index_group u32][index_offset u32][longitud_nombre u32][nombre][bytes_a_leer u32]
        var nb = Encoding.UTF8.GetBytes(name);
        var payload = new byte[16 + nb.Length]; // 12 (ig+io+len) + nombre + 4 (size)
        BinaryPrimitives.WriteUInt32LittleEndian(payload, AdsIndexGroups.SymValByName);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(4), 0);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(8), (uint)nb.Length);
        nb.CopyTo(payload, 12);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(12 + nb.Length), (uint)size);
        return Request(AdsCommands.Read, payload).Data;
    }

    public byte[] ReadSymbol(string name) => ReadSymbol(name, (int)GetSymbolInfo(name).Size);

    public byte[] ReadSymbol(string name, string plcType) => ReadSymbol(name, PlcType.SizeOf(plcType));

    public void WriteSymbol(string name, byte[] value)
    {
        // Payload de escritura por nombre:
        //   [index_group u32][index_offset u32][longitud_nombre u32][nombre][longitud_valor u32][valor]
        var nb = Encoding.UTF8.GetBytes(name);
        var payload = new byte[16 + nb.Length + value.Length]; // 12 + nombre + 4 (len) + valor
        BinaryPrimitives.WriteUInt32LittleEndian(payload, AdsIndexGroups.SymValByName);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(4), 0);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(8), (uint)nb.Length);
        nb.CopyTo(payload, 12);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(12 + nb.Length), (uint)value.Length);
        value.CopyTo(payload, 16 + nb.Length);
        Request(AdsCommands.Write, payload);
    }

    public uint CreateVariableHandle(string name)
    {
        var nb = Encoding.UTF8.GetBytes(name);
        var payload = new byte[12 + nb.Length];
        BinaryPrimitives.WriteUInt32LittleEndian(payload, AdsIndexGroups.SymHndByName);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(4), 0);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(8), (uint)nb.Length);
        nb.CopyTo(payload, 12);
        var data = Request(AdsCommands.Read, payload).Data;
        return BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(0, 4));
    }

    public void DeleteVariableHandle(uint handle)
    {
        var payload = new byte[12];
        BinaryPrimitives.WriteUInt32LittleEndian(payload, AdsIndexGroups.SymReleaseHnd);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(4), handle);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(8), 0);
        Request(AdsCommands.Write, payload);
    }

    public byte[] ReadByHandle(uint handle, int length)
    {
        var payload = new byte[12];
        BinaryPrimitives.WriteUInt32LittleEndian(payload, AdsIndexGroups.SymValByHnd);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(4), handle);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(8), (uint)length);
        return Request(AdsCommands.Read, payload).Data;
    }

    public void WriteByHandle(uint handle, byte[] data)
    {
        var payload = new byte[12 + data.Length];
        BinaryPrimitives.WriteUInt32LittleEndian(payload, AdsIndexGroups.SymValByHnd);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(4), handle);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(8), (uint)data.Length);
        data.CopyTo(payload, 12);
        Request(AdsCommands.Write, payload);
    }

    public AdsSymbolInfo GetSymbolInfo(string name)
    {
        var nb = Encoding.UTF8.GetBytes(name);
        var payload = new byte[12 + nb.Length];
        BinaryPrimitives.WriteUInt32LittleEndian(payload, AdsIndexGroups.SymInfoByName);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(4), 0);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(8), (uint)nb.Length);
        nb.CopyTo(payload, 12);
        return AdsSymbolInfo.Parse(Request(AdsCommands.Read, payload).Data);
    }

    // ------------------------------------------------------------------ sum
    public IReadOnlyList<byte[]> SumRead(IReadOnlyList<(uint IndexGroup, uint IndexOffset, int Length)> entries)
    {
        var body = new List<byte>(entries.Count * 12);
        foreach (var (ig, io, len) in entries)
        {
            var e = new byte[12];
            BinaryPrimitives.WriteUInt32LittleEndian(e, ig);
            BinaryPrimitives.WriteUInt32LittleEndian(e.AsSpan(4), io);
            BinaryPrimitives.WriteUInt32LittleEndian(e.AsSpan(8), (uint)len);
            body.AddRange(e);
        }
        var payload = new byte[12 + body.Count];
        BinaryPrimitives.WriteUInt32LittleEndian(payload, AdsIndexGroups.SumUpRead);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(4), 0);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(8), (uint)body.Count);
        body.CopyTo(payload, 12);
        var data = Request(AdsCommands.Read, payload).Data;

        var results = new List<byte[]>(entries.Count);
        int off = 0;
        foreach (var (_, _, len) in entries)
        {
            uint result = BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(off, 4));
            uint length = BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(off + 4, 4));
            off += 8;
            if (result != 0) throw new AdsException(result);
            var chunk = new byte[length];
            Array.Copy(data, off, chunk, 0, Math.Min((int)length, data.Length - off));
            off += (int)length;
            results.Add(chunk);
        }
        return results;
    }

    public void SumWrite(IReadOnlyList<(uint IndexGroup, uint IndexOffset, byte[] Data)> entries)
    {
        var body = new List<byte>();
        foreach (var (ig, io, d) in entries)
        {
            var e = new byte[12 + d.Length];
            BinaryPrimitives.WriteUInt32LittleEndian(e, ig);
            BinaryPrimitives.WriteUInt32LittleEndian(e.AsSpan(4), io);
            BinaryPrimitives.WriteUInt32LittleEndian(e.AsSpan(8), (uint)d.Length);
            d.CopyTo(e, 12);
            body.AddRange(e);
        }
        var payload = new byte[12 + body.Count];
        BinaryPrimitives.WriteUInt32LittleEndian(payload, AdsIndexGroups.SumUpWrite);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(4), 0);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(8), (uint)body.Count);
        body.CopyTo(payload, 12);
        var data = Request(AdsCommands.Write, payload).Data;

        for (int i = 0; i + 4 <= data.Length; i += 4)
        {
            uint result = BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(i, 4));
            if (result != 0) throw new AdsException(result);
        }
    }

    // ------------------------------------------------------- notificaciones
    public uint AddDeviceNotification(
        uint indexGroup,
        uint indexOffset,
        int cbLength,
        AdsTransMode transMode,
        uint maxDelay,
        uint cycleTime,
        Action<NotificationStamp>? callback = null)
    {
        var payload = new byte[32];
        BinaryPrimitives.WriteUInt32LittleEndian(payload, indexGroup);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(4), indexOffset);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(8), (uint)cbLength);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(12), (uint)transMode);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(16), maxDelay);
        BinaryPrimitives.WriteUInt32LittleEndian(payload.AsSpan(20), cycleTime);
        var data = Request(AdsCommands.AddDeviceNotification, payload).Data;
        uint handle = BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(0, 4));
        if (callback != null) _notifications[handle] = callback;
        return handle;
    }

    public void DeleteDeviceNotification(uint handle)
    {
        var payload = new byte[4];
        BinaryPrimitives.WriteUInt32LittleEndian(payload, handle);
        Request(AdsCommands.DelDeviceNotification, payload);
        _notifications.TryRemove(handle, out _);
    }

    /// <summary>
    /// Suscribe una notificación a una variable por su nombre, resolviendo
    /// internamente el par (index_group, index_offset) mediante GetSymbolInfo.
    /// </summary>
    public uint AddNotificationByName(
        string name,
        AdsTransMode transMode = AdsTransMode.ServerOnChange,
        uint maxDelay = 0,
        uint cycleTime = 1000000,
        Action<NotificationStamp>? callback = null)
    {
        var info = GetSymbolInfo(name);
        return AddDeviceNotification(info.IndexGroup, info.IndexOffset, (int)info.Size, transMode, maxDelay, cycleTime, callback);
    }

    // ------------------------------------------------------------------ tipado
    public T ReadValue<T>(string name, string? plcType = null)
    {
        string t = plcType ?? InferType(typeof(T))
            ?? throw new AdsException(AdsErrorCode.InvalidParameterValue, "Especifica plcType para este tipo");
        var data = ReadSymbol(name, t);
        return PlcType.Decode<T>(data, t);
    }

    public void WriteValue<T>(string name, T value, string? plcType = null)
    {
        string t = plcType ?? InferType(typeof(T))
            ?? throw new AdsException(AdsErrorCode.InvalidParameterValue, "Especifica plcType para este tipo");
        WriteSymbol(name, PlcType.Encode(value!, t));
    }

    public T ReadStruct<T>(string name) where T : struct
    {
        int size = Marshal.SizeOf<T>();
        return BytesToStruct<T>(ReadSymbol(name, size));
    }

    public void WriteStruct<T>(string name, T value) where T : struct
    {
        WriteSymbol(name, StructToBytes(value));
    }

    private static string? InferType(Type t) => Type.GetTypeCode(t) switch
    {
        TypeCode.Boolean => "BOOL",
        TypeCode.SByte => "SINT",
        TypeCode.Byte => "USINT",
        TypeCode.Int16 => "INT",
        TypeCode.UInt16 => "UINT",
        TypeCode.Int32 => "DINT",
        TypeCode.UInt32 => "UDINT",
        TypeCode.Int64 => "LINT",
        TypeCode.UInt64 => "ULINT",
        TypeCode.Single => "REAL",
        TypeCode.Double => "LREAL",
        _ => null,
    };

    private static byte[] StructToBytes<T>(T value) where T : struct
    {
        int size = Marshal.SizeOf<T>();
        var buf = new byte[size];
        IntPtr ptr = Marshal.AllocHGlobal(size);
        try
        {
            Marshal.StructureToPtr(value!, ptr, false);
            Marshal.Copy(ptr, buf, 0, size);
        }
        finally { Marshal.FreeHGlobal(ptr); }
        return buf;
    }

    private static T BytesToStruct<T>(byte[] data) where T : struct
    {
        int size = Marshal.SizeOf<T>();
        IntPtr ptr = Marshal.AllocHGlobal(size);
        try
        {
            Marshal.Copy(data, 0, ptr, Math.Min(size, data.Length));
            return Marshal.PtrToStructure<T>(ptr);
        }
        finally { Marshal.FreeHGlobal(ptr); }
    }
}

internal sealed record AdsResponse(ushort CommandId, uint ErrorCode, byte[] Data);

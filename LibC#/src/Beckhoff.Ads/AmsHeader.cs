using System;
using System.Buffers.Binary;

namespace Beckhoff.Ads;

/// <summary>Cabecera AMS de 32 bytes (ver sección 2 del PROTOCOL.md).</summary>
public sealed class AmsHeader
{
    public const int Size = 32;

    public AmsNetId TargetNetId { get; set; } = AmsNetId.Empty;
    public ushort TargetPort { get; set; }
    public AmsNetId SourceNetId { get; set; } = AmsNetId.Empty;
    public ushort SourcePort { get; set; }
    public ushort CommandId { get; set; }
    public ushort StateFlags { get; set; }
    public uint Length { get; set; }
    public uint ErrorCode { get; set; }
    public uint InvokeId { get; set; }

    public void Write(Span<byte> destination)
    {
        if (destination.Length < Size) throw new ArgumentException("Buffer demasiado pequeño", nameof(destination));
        TargetNetId.ToByteArray().CopyTo(destination.Slice(0, 6));
        BinaryPrimitives.WriteUInt16LittleEndian(destination.Slice(6), TargetPort);
        SourceNetId.ToByteArray().CopyTo(destination.Slice(8, 6));
        BinaryPrimitives.WriteUInt16LittleEndian(destination.Slice(14), SourcePort);
        BinaryPrimitives.WriteUInt16LittleEndian(destination.Slice(16), CommandId);
        BinaryPrimitives.WriteUInt16LittleEndian(destination.Slice(18), StateFlags);
        BinaryPrimitives.WriteUInt32LittleEndian(destination.Slice(20), Length);
        BinaryPrimitives.WriteUInt32LittleEndian(destination.Slice(24), ErrorCode);
        BinaryPrimitives.WriteUInt32LittleEndian(destination.Slice(28), InvokeId);
    }

    public static AmsHeader Read(ReadOnlySpan<byte> source)
    {
        if (source.Length < Size) throw new ArgumentException("Cabecera AMS incompleta", nameof(source));
        var netIdBytes = new byte[6];
        source.Slice(0, 6).CopyTo(netIdBytes);
        var targetNetId = AmsNetId.FromByteArray(netIdBytes);
        var targetPort = BinaryPrimitives.ReadUInt16LittleEndian(source.Slice(6));
        source.Slice(8, 6).CopyTo(netIdBytes);
        var sourceNetId = AmsNetId.FromByteArray(netIdBytes);
        var sourcePort = BinaryPrimitives.ReadUInt16LittleEndian(source.Slice(14));
        var commandId = BinaryPrimitives.ReadUInt16LittleEndian(source.Slice(16));
        var stateFlags = BinaryPrimitives.ReadUInt16LittleEndian(source.Slice(18));
        var length = BinaryPrimitives.ReadUInt32LittleEndian(source.Slice(20));
        var errorCode = BinaryPrimitives.ReadUInt32LittleEndian(source.Slice(24));
        var invokeId = BinaryPrimitives.ReadUInt32LittleEndian(source.Slice(28));

        return new AmsHeader
        {
            TargetNetId = targetNetId,
            TargetPort = targetPort,
            SourceNetId = sourceNetId,
            SourcePort = sourcePort,
            CommandId = commandId,
            StateFlags = stateFlags,
            Length = length,
            ErrorCode = errorCode,
            InvokeId = invokeId,
        };
    }
}

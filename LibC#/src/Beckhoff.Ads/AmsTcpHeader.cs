using System;
using System.Buffers.Binary;

namespace Beckhoff.Ads;

/// <summary>Cabecera AMS/TCP de 6 bytes (reservado + longitud).</summary>
public readonly struct AmsTcpHeader
{
    public const int Size = 6;

    public ushort Reserved { get; }   // siempre 0
    public uint Length { get; }       // bytes de cabecera AMS + datos

    public AmsTcpHeader(uint length)
    {
        Reserved = 0;
        Length = length;
    }

    private AmsTcpHeader(uint length, ushort reserved)
    {
        Reserved = reserved;
        Length = length;
    }

    public void Write(Span<byte> destination)
    {
        if (destination.Length < Size) throw new ArgumentException("Buffer demasiado pequeño", nameof(destination));
        BinaryPrimitives.WriteUInt16LittleEndian(destination, Reserved);
        BinaryPrimitives.WriteUInt32LittleEndian(destination[2..], Length);
    }

    public static AmsTcpHeader Read(ReadOnlySpan<byte> source)
    {
        if (source.Length < Size) throw new ArgumentException("Cabecera AMS/TCP incompleta", nameof(source));
        var reserved = BinaryPrimitives.ReadUInt16LittleEndian(source);
        var length = BinaryPrimitives.ReadUInt32LittleEndian(source[2..]);
        return new AmsTcpHeader(length, reserved);
    }
}

using System;
using System.Buffers.Binary;
using System.Text;

namespace Beckhoff.Ads;

/// <summary>Información de un símbolo PLC (respuesta de SYM_INFOBYNAME).</summary>
public sealed class AdsSymbolInfo
{
    public uint IndexGroup { get; init; }
    public uint IndexOffset { get; init; }
    public uint Size { get; init; }
    public uint DataType { get; init; }
    public ushort Flags { get; init; }
    public string Name { get; init; } = "";
    public string TypeName { get; init; } = "";
    public string Comment { get; init; } = "";

    public static AdsSymbolInfo Parse(byte[] data)
    {
        if (data == null || data.Length < 24)
            throw new AdsException(AdsErrorCode.InternalError, "Información de símbolo inválida");
        var indexGroup = BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(0, 4));
        var indexOffset = BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(4, 4));
        var size = BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(8, 4));
        var dataType = BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(12, 4));
        var flags = BinaryPrimitives.ReadUInt16LittleEndian(data.AsSpan(16, 2));
        var nameLength = BinaryPrimitives.ReadUInt16LittleEndian(data.AsSpan(18, 2));
        var typeLength = BinaryPrimitives.ReadUInt16LittleEndian(data.AsSpan(20, 2));
        var commentLength = BinaryPrimitives.ReadUInt16LittleEndian(data.AsSpan(22, 2));

        int off = 24;
        string name = ReadString(data, off, nameLength); off += nameLength;
        string typeName = ReadString(data, off, typeLength); off += typeLength;
        string comment = ReadString(data, off, commentLength);

        return new AdsSymbolInfo
        {
            IndexGroup = indexGroup,
            IndexOffset = indexOffset,
            Size = size,
            DataType = dataType,
            Flags = flags,
            Name = name,
            TypeName = typeName,
            Comment = comment,
        };
    }

    private static string ReadString(byte[] data, int offset, int length)
    {
        if (length <= 0) return "";
        if (offset + length > data.Length) length = data.Length - offset;
        var s = Encoding.UTF8.GetString(data, offset, length);
        int nul = s.IndexOf('\0');
        return nul >= 0 ? s.Substring(0, nul) : s;
    }

    public override string ToString() => $"SymbolInfo({Name}: {TypeName}, size={Size})";
}

using System;
using System.Buffers.Binary;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace Beckhoff.Ads;

/// <summary>Codificación/decodificación de tipos de datos PLC (sección 7 del PROTOCOL.md).</summary>
public static class PlcType
{
    private static readonly Regex StringRe = new(@"^\s*STRING\s*\((\d+)\)\s*$", RegexOptions.IgnoreCase);
    private static readonly Regex WStringRe = new(@"^\s*WSTRING\s*\((\d+)\)\s*$", RegexOptions.IgnoreCase);
    private static readonly Regex ArrayRe = new(@"^\s*ARRAY\s*\[([^\]]*)\]\s+OF\s+(.+?)\s*$", RegexOptions.IgnoreCase);

    /// <summary>Tamaño en bytes del valor codificado de un tipo PLC.</summary>
    public static int SizeOf(string plcType)
    {
        string t = plcType.Trim().ToUpperInvariant();
        if (ScalarSize(t, out int size)) return size;
        var m = StringRe.Match(t);
        if (m.Success) return int.Parse(m.Groups[1].Value) + 1;
        m = WStringRe.Match(t);
        if (m.Success) return 2 * (int.Parse(m.Groups[1].Value) + 1);
        m = ArrayRe.Match(t);
        if (m.Success)
            return ArrayCount(m.Groups[1].Value) * SizeOf(m.Groups[2].Value);
        throw new NotSupportedException($"Tipo PLC no soportado: '{plcType}'");
    }

    private static bool ScalarSize(string t, out int size)
    {
        switch (t)
        {
            case "BOOL": case "SINT": case "USINT": case "BYTE": size = 1; return true;
            case "INT": case "UINT": case "WORD": size = 2; return true;
            case "DINT": case "UDINT": case "DWORD": case "REAL":
            case "TIME": case "TOD": case "DT": case "DATE": size = 4; return true;
            case "LINT": case "ULINT": case "LWORD": case "LREAL": size = 8; return true;
            default: size = 0; return false;
        }
    }

    private static int ArrayCount(string bounds)
    {
        int count = 1;
        foreach (var part in bounds.Split(','))
        {
            var m = Regex.Match(part.Trim(), @"^(-?\d+)\s*\.\.\s*(-?\d+)$");
            if (!m.Success) throw new NotSupportedException($"Bounds de array no soportados: '{bounds}'");
            count *= int.Parse(m.Groups[2].Value) - int.Parse(m.Groups[1].Value) + 1;
        }
        return count;
    }

    /// <summary>Codifica un valor a bytes según el tipo PLC.</summary>
    public static byte[] Encode(object value, string plcType)
    {
        string t = plcType.Trim().ToUpperInvariant();

        if (t == "BOOL")
            return new[] { (byte)(Convert.ToBoolean(value, CultureInfo.InvariantCulture) ? 1 : 0) };

        if (TryEncodeScalar(t, value, out var scalar)) return scalar;

        var m = StringRe.Match(t);
        if (m.Success) return EncodeString(Convert.ToString(value, CultureInfo.InvariantCulture) ?? "", int.Parse(m.Groups[1].Value));

        m = WStringRe.Match(t);
        if (m.Success) return EncodeWString(Convert.ToString(value, CultureInfo.InvariantCulture) ?? "", int.Parse(m.Groups[1].Value));

        m = ArrayRe.Match(t);
        if (m.Success && value is System.Collections.IEnumerable items)
            return EncodeArray(items, m.Groups[2].Value);

        throw new NotSupportedException($"Tipo PLC no soportado: '{plcType}'");
    }

    private static bool TryEncodeScalar(string t, object value, out byte[] bytes)
    {
        switch (t)
        {
            case "SINT": bytes = new[] { unchecked((byte)Convert.ToSByte(value, CultureInfo.InvariantCulture)) }; return true;
            case "USINT": case "BYTE": bytes = new[] { Convert.ToByte(value, CultureInfo.InvariantCulture) }; return true;
            case "INT": bytes = new byte[2]; BinaryPrimitives.WriteInt16LittleEndian(bytes, Convert.ToInt16(value, CultureInfo.InvariantCulture)); return true;
            case "UINT": case "WORD": bytes = new byte[2]; BinaryPrimitives.WriteUInt16LittleEndian(bytes, Convert.ToUInt16(value, CultureInfo.InvariantCulture)); return true;
            case "DINT": bytes = new byte[4]; BinaryPrimitives.WriteInt32LittleEndian(bytes, Convert.ToInt32(value, CultureInfo.InvariantCulture)); return true;
            case "UDINT": case "DWORD": bytes = new byte[4]; BinaryPrimitives.WriteUInt32LittleEndian(bytes, Convert.ToUInt32(value, CultureInfo.InvariantCulture)); return true;
            case "REAL": bytes = new byte[4]; BinaryPrimitives.WriteSingleLittleEndian(bytes, Convert.ToSingle(value, CultureInfo.InvariantCulture)); return true;
            case "TIME": case "TOD": case "DT": case "DATE": bytes = new byte[4]; BinaryPrimitives.WriteUInt32LittleEndian(bytes, Convert.ToUInt32(value, CultureInfo.InvariantCulture)); return true;
            case "LINT": bytes = new byte[8]; BinaryPrimitives.WriteInt64LittleEndian(bytes, Convert.ToInt64(value, CultureInfo.InvariantCulture)); return true;
            case "ULINT": case "LWORD": bytes = new byte[8]; BinaryPrimitives.WriteUInt64LittleEndian(bytes, Convert.ToUInt64(value, CultureInfo.InvariantCulture)); return true;
            case "LREAL": bytes = new byte[8]; BinaryPrimitives.WriteDoubleLittleEndian(bytes, Convert.ToDouble(value, CultureInfo.InvariantCulture)); return true;
            default: bytes = Array.Empty<byte>(); return false;
        }
    }

    /// <summary>Decodifica bytes a un valor (boxed) según el tipo PLC.</summary>
    public static object Decode(byte[] data, string plcType)
    {
        string t = plcType.Trim().ToUpperInvariant();

        if (t == "BOOL") return data[0] != 0;

        switch (t)
        {
            case "SINT": return unchecked((sbyte)data[0]);
            case "USINT": case "BYTE": return data[0];
            case "INT": return BinaryPrimitives.ReadInt16LittleEndian(data);
            case "UINT": case "WORD": return BinaryPrimitives.ReadUInt16LittleEndian(data);
            case "DINT": return BinaryPrimitives.ReadInt32LittleEndian(data);
            case "UDINT": case "DWORD": return BinaryPrimitives.ReadUInt32LittleEndian(data);
            case "REAL": return BinaryPrimitives.ReadSingleLittleEndian(data);
            case "TIME": case "TOD": case "DT": case "DATE": return BinaryPrimitives.ReadUInt32LittleEndian(data);
            case "LINT": return BinaryPrimitives.ReadInt64LittleEndian(data);
            case "ULINT": case "LWORD": return BinaryPrimitives.ReadUInt64LittleEndian(data);
            case "LREAL": return BinaryPrimitives.ReadDoubleLittleEndian(data);
        }

        var m = StringRe.Match(t);
        if (m.Success)
        {
            int n = int.Parse(m.Groups[1].Value);
            int len = Math.Min(data[0], n);
            return Encoding.ASCII.GetString(data, 1, len);
        }

        m = WStringRe.Match(t);
        if (m.Success)
        {
            int n = int.Parse(m.Groups[1].Value);
            int len = Math.Min(BinaryPrimitives.ReadUInt16LittleEndian(data), n);
            return Encoding.Unicode.GetString(data, 2, len * 2);
        }

        m = ArrayRe.Match(t);
        if (m.Success)
        {
            var elementType = m.Groups[2].Value;
            int elemSize = SizeOf(elementType);
            var list = new List<object>();
            for (int i = 0; i + elemSize <= data.Length; i += elemSize)
            {
                var slice = new byte[elemSize];
                Array.Copy(data, i, slice, 0, elemSize);
                list.Add(Decode(slice, elementType));
            }
            return list.ToArray();
        }

        throw new NotSupportedException($"Tipo PLC no soportado: '{plcType}'");
    }

    /// <summary>Decodifica bytes y convierte a T.</summary>
    public static T Decode<T>(byte[] data, string plcType) => (T)Convert.ChangeType(Decode(data, plcType), typeof(T), CultureInfo.InvariantCulture);

    private static byte[] EncodeString(string value, int maxLength)
    {
        var content = Encoding.ASCII.GetBytes(value ?? "");
        int len = Math.Min(content.Length, maxLength);
        var buf = new byte[maxLength + 1];
        buf[0] = (byte)len;
        Array.Copy(content, 0, buf, 1, len);
        return buf;
    }

    private static byte[] EncodeWString(string value, int maxLength)
    {
        var content = Encoding.Unicode.GetBytes(value ?? "");
        int len = Math.Min(content.Length / 2, maxLength);
        var buf = new byte[2 * (maxLength + 1)];
        BinaryPrimitives.WriteUInt16LittleEndian(buf, (ushort)len);
        Array.Copy(content, 0, buf, 2, len * 2);
        return buf;
    }

    private static byte[] EncodeArray(System.Collections.IEnumerable items, string elementType)
    {
        var list = new List<byte>();
        foreach (var item in items)
            list.AddRange(Encode(item, elementType));
        return list.ToArray();
    }
}

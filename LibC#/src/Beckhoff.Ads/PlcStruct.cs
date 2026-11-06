using System;
using System.Collections.Generic;

namespace Beckhoff.Ads;

/// <summary>Un miembro de una estructura PLC (nombre, tipo y offset en bytes).</summary>
public sealed class PlcMember
{
    /// <summary>Nombre del miembro.</summary>
    public string Name { get; }

    /// <summary>Tipo PLC del miembro (ej. "LREAL", "BOOL").</summary>
    public string TypeName { get; }

    /// <summary>Offset en bytes del miembro dentro de la estructura.</summary>
    public int ByteOffset { get; }

    /// <summary>Tamaño en bytes del miembro codificado.</summary>
    public int Size { get; }

    public PlcMember(string name, string plcType, int byteOffset)
    {
        Name = name;
        TypeName = plcType;
        ByteOffset = byteOffset;
        Size = PlcType.SizeOf(plcType);
    }
}

/// <summary>Definición de una estructura PLC: lista de miembros + tamaño total.
///
/// Permite leer/escribir una estructura **completa** como un diccionario
/// {nombre_miembro: valor}, de forma automática (una sola lectura/escritura del
/// bloque de bytes de la estructura).
/// </summary>
public sealed class PlcStruct
{
    /// <summary>Miembros de la estructura, en orden.</summary>
    public IReadOnlyList<PlcMember> Members { get; }

    /// <summary>Tamaño total en bytes del bloque de la estructura.</summary>
    public int TotalSize { get; }

    public PlcStruct(IEnumerable<PlcMember> members, int? totalSize = null)
    {
        Members = new List<PlcMember>(members);
        TotalSize = totalSize ?? ComputeSize(Members);
    }

    /// <summary>Tamaño = mayor (offset + tamaño) de todos los miembros.</summary>
    private static int ComputeSize(IReadOnlyList<PlcMember> members)
    {
        int max = 0;
        foreach (var m in members)
            max = Math.Max(max, m.ByteOffset + m.Size);
        return max;
    }

    /// <summary>Decodifica un bloque de bytes en un dict {nombre: valor}.</summary>
    public Dictionary<string, object?> Decode(byte[] data)
    {
        var result = new Dictionary<string, object?>();
        foreach (var m in Members)
        {
            var chunk = new byte[m.Size];
            Array.Copy(data, m.ByteOffset, chunk, 0, Math.Min(m.Size, data.Length - m.ByteOffset));
            result[m.Name] = PlcType.Decode(chunk, m.TypeName);
        }
        return result;
    }

    /// <summary>Codifica un dict {nombre: valor} en un bloque de bytes.</summary>
    public byte[] Encode(Dictionary<string, object?> values)
    {
        var buffer = new byte[TotalSize];
        foreach (var m in Members)
        {
            if (!values.TryGetValue(m.Name, out var value) || value is null) continue;
            var chunk = PlcType.Encode(value, m.TypeName);
            Array.Copy(chunk, 0, buffer, m.ByteOffset, Math.Min(chunk.Length, TotalSize - m.ByteOffset));
        }
        return buffer;
    }
}

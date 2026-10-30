using System;

namespace Beckhoff.Ads;

/// <summary>Identificador de red AMS de 6 bytes, escrito como a.b.c.d.e.f.</summary>
public readonly struct AmsNetId : IEquatable<AmsNetId>
{
    private readonly byte _b0, _b1, _b2, _b3, _b4, _b5;

    public AmsNetId(byte b0, byte b1, byte b2, byte b3, byte b4, byte b5)
    {
        _b0 = b0; _b1 = b1; _b2 = b2; _b3 = b3; _b4 = b4; _b5 = b5;
    }

    public static AmsNetId Empty => default;

    public bool IsEmpty => _b0 == 0 && _b1 == 0 && _b2 == 0 && _b3 == 0 && _b4 == 0 && _b5 == 0;

    public byte[] ToByteArray() => new[] { _b0, _b1, _b2, _b3, _b4, _b5 };

    public static AmsNetId FromByteArray(byte[] bytes, int offset = 0)
    {
        if (bytes == null) throw new ArgumentNullException(nameof(bytes));
        if (offset < 0 || offset + 6 > bytes.Length)
            throw new ArgumentOutOfRangeException(nameof(offset), "Se requieren 6 bytes.");
        return new AmsNetId(bytes[offset], bytes[offset + 1], bytes[offset + 2],
                            bytes[offset + 3], bytes[offset + 4], bytes[offset + 5]);
    }

    public static AmsNetId Parse(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
            return Empty;
        var parts = value.Split('.');
        if (parts.Length != 6)
            throw new FormatException($"AmsNetId inválido (se espera a.b.c.d.e.f): '{value}'");
        var b = new byte[6];
        for (int i = 0; i < 6; i++)
        {
            if (!byte.TryParse(parts[i], out b[i]))
                throw new FormatException($"AmsNetId inválido: '{value}'");
        }
        return new AmsNetId(b[0], b[1], b[2], b[3], b[4], b[5]);
    }

    public override string ToString() => $"{_b0}.{_b1}.{_b2}.{_b3}.{_b4}.{_b5}";

    public bool Equals(AmsNetId other) =>
        _b0 == other._b0 && _b1 == other._b1 && _b2 == other._b2 &&
        _b3 == other._b3 && _b4 == other._b4 && _b5 == other._b5;

    public override bool Equals(object? obj) => obj is AmsNetId other && Equals(other);

    public override int GetHashCode() => HashCode.Combine(_b0, _b1, _b2, _b3, _b4, _b5);

    public static bool operator ==(AmsNetId left, AmsNetId right) => left.Equals(right);
    public static bool operator !=(AmsNetId left, AmsNetId right) => !left.Equals(right);
}

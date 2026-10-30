using System;

namespace Beckhoff.Ads;

/// <summary>Dirección AMS formada por un AmsNetId y un puerto.</summary>
public readonly struct AmsAddress : IEquatable<AmsAddress>
{
    public AmsNetId NetId { get; }
    public ushort Port { get; }

    public AmsAddress(AmsNetId netId, ushort port)
    {
        NetId = netId;
        Port = port;
    }

    public AmsAddress(string netId, ushort port)
        : this(AmsNetId.Parse(netId), port)
    {
    }

    public override string ToString() => $"{NetId}:{Port}";

    public bool Equals(AmsAddress other) => NetId.Equals(other.NetId) && Port == other.Port;
    public override bool Equals(object? obj) => obj is AmsAddress other && Equals(other);
    public override int GetHashCode() => HashCode.Combine(NetId, Port);
    public static bool operator ==(AmsAddress left, AmsAddress right) => left.Equals(right);
    public static bool operator !=(AmsAddress left, AmsAddress right) => !left.Equals(right);
}

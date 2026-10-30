namespace Beckhoff.Ads;

/// <summary>Muestra entregada por una notificación ADS.</summary>
public sealed class NotificationStamp
{
    public uint Handle { get; }
    public ulong Timestamp { get; }   // FILETIME Windows (100 ns desde 1601-01-01)
    public byte[] Data { get; }

    public NotificationStamp(uint handle, ulong timestamp, byte[] data)
    {
        Handle = handle;
        Timestamp = timestamp;
        Data = data;
    }

    public override string ToString() => $"NotificationStamp(handle={Handle}, len={Data?.Length ?? 0})";
}

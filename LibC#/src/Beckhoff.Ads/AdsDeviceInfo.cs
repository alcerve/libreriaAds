using System;
using System.Text;

namespace Beckhoff.Ads;

/// <summary>Información del dispositivo (respuesta de READ_DEVICE_INFO).</summary>
public sealed class AdsDeviceInfo
{
    public byte MajorVersion { get; init; }
    public byte MinorVersion { get; init; }
    public ushort BuildVersion { get; init; }
    public string DeviceName { get; init; } = "";

    public static AdsDeviceInfo Parse(byte[] data)
    {
        if (data == null || data.Length < 20)
            throw new AdsException(AdsErrorCode.InternalError, "Respuesta de dispositivo inválida");
        int nameLength = 16;
        var name = Encoding.ASCII.GetString(data, 4, nameLength);
        int nul = name.IndexOf('\0');
        if (nul >= 0) name = name.Substring(0, nul);
        return new AdsDeviceInfo
        {
            MajorVersion = data[0],
            MinorVersion = data[1],
            BuildVersion = (ushort)(data[2] | (data[3] << 8)),
            DeviceName = name,
        };
    }

    public override string ToString() => $"{DeviceName} v{MajorVersion}.{MinorVersion} (build {BuildVersion})";
}

using System;

namespace Beckhoff.Ads;

/// <summary>Excepción del protocolo ADS con su código numérico.</summary>
public class AdsException : Exception
{
    public uint ErrorCode { get; }

    public AdsException(uint errorCode)
        : base($"ADS error 0x{errorCode:X8}: {AdsErrorCode.GetMessage(errorCode)}")
    {
        ErrorCode = errorCode;
    }

    public AdsException(uint errorCode, string message)
        : base(message)
    {
        ErrorCode = errorCode;
    }
}

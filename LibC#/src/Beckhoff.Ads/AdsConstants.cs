namespace Beckhoff.Ads;

/// <summary>Constantes del protocolo ADS.</summary>
public static class AdsCommands
{
    public const ushort Invalid = 0x0000;
    public const ushort ReadDeviceInfo = 0x0001;
    public const ushort Read = 0x0002;
    public const ushort Write = 0x0003;
    public const ushort ReadState = 0x0004;
    public const ushort WriteControl = 0x0005;
    public const ushort AddDeviceNotification = 0x0006;
    public const ushort DelDeviceNotification = 0x0007;
    public const ushort DeviceNotification = 0x0008;
    public const ushort ReadWrite = 0x0009;
}

public static class AdsIndexGroups
{
    public const uint SymTab = 0xF000;
    public const uint SymName = 0xF001;
    public const uint SymVal = 0xF002;
    public const uint SymHndByName = 0xF003;
    public const uint SymValByHnd = 0xF004;
    public const uint SymValByName = 0xF005;
    public const uint SymInfoByName = 0xF006;
    public const uint SymVersion = 0xF007;
    public const uint SymInfoByNameEx = 0xF008;
    public const uint SymDownload = 0xF009;
    public const uint SymReleaseHnd = 0xF014;
    public const uint IoImageRwIb = 0xF020;
    public const uint IoImageRwIx = 0xF021;
    public const uint IoImageRwOb = 0xF030;
    public const uint IoImageRwOx = 0xF031;
    public const uint SumUpRead = 0xF080;
    public const uint SumUpWrite = 0xF081;
    public const uint SumUpReadWrite = 0xF082;
    public const uint DeviceData = 0xF100;
}

public static class AdsPorts
{
    public const ushort Logger = 100;
    public const ushort EventLog = 300;
    public const ushort Io = 400;
    public const ushort Nc = 500;
    public const ushort Plc = 800;
    public const ushort PlcTc2 = 801;
    public const ushort PlcTc3 = 851;
    public const ushort PlcTc4 = 852;
    public const ushort PlcTc5 = 853;
    public const ushort SystemService = 10000;

    public const int TcpPort = 48898;
}

public enum AdsState : ushort
{
    Invalid = 0,
    Idle = 1,
    Reset = 2,
    Init = 3,
    Start = 4,
    Run = 5,
    Stop = 6,
    SaveCfg = 7,
    LoadCfg = 8,
    PowerFailure = 9,
    PowerGood = 10,
    Error = 11,
    Shutdown = 12,
    Suspend = 13,
    Resume = 14,
    Config = 15,
    Reconfig = 16,
    Stopping = 17,
    Incompatible = 18,
    Exception = 19,
}

public enum AdsTransMode : uint
{
    NoTrans = 0,
    ClientCycle = 1,
    ClientOnChange = 2,
    ServerCycle = 3,
    ServerOnChange = 4,
}

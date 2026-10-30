namespace Beckhoff.Ads;

/// <summary>Códigos de error ADS (sección 8 del PROTOCOL.md).</summary>
public static class AdsErrorCode
{
    public const uint NoError = 0x00000000;
    public const uint InternalError = 0x00000001;
    public const uint TargetPortNotFound = 0x00000006;
    public const uint TargetMachineNotFound = 0x00000007;
    public const uint UnknownCommand = 0x00000008;
    public const uint InvalidAmsLength = 0x0000000E;
    public const uint InvalidAmsNetId = 0x0000000F;
    public const uint PortDisabled = 0x00000012;
    public const uint PortAlreadyConnected = 0x00000013;
    public const uint HostUnreachable = 0x0000001B;

    public const uint ServiceNotSupported = 0x00000701;
    public const uint InvalidIndexGroup = 0x00000702;
    public const uint InvalidIndexOffset = 0x00000703;
    public const uint ReadWriteNotPermitted = 0x00000704;
    public const uint ParameterSizeIncorrect = 0x00000705;
    public const uint InvalidParameterValue = 0x00000706;
    public const uint NotFound = 0x0000070C;
    public const uint SymbolNotFound = 0x00000710;
    public const uint ServerInvalidState = 0x00000712;
    public const uint TransModeNotSupported = 0x00000713;
    public const uint InvalidNotificationHandle = 0x00000714;
    public const uint NoNotificationSubscribed = 0x00000716;
    public const uint TimeoutElapsed = 0x00000745;
    public const uint InvalidClientTimeout = 0x00000750;

    public static string GetMessage(uint code) => code switch
    {
        NoError => "Sin error",
        InternalError => "Error interno",
        TargetPortNotFound => "Puerto destino no encontrado",
        TargetMachineNotFound => "Máquina destino no encontrada",
        UnknownCommand => "Comando desconocido",
        InvalidAmsLength => "Longitud AMS inválida",
        InvalidAmsNetId => "AmsNetId inválido",
        PortDisabled => "Puerto deshabilitado",
        PortAlreadyConnected => "Puerto ya conectado",
        HostUnreachable => "Host inalcanzable",
        ServiceNotSupported => "Servicio no soportado",
        InvalidIndexGroup => "Grupo de índice inválido",
        InvalidIndexOffset => "Offset de índice inválido",
        ReadWriteNotPermitted => "Lectura/escritura no permitida",
        ParameterSizeIncorrect => "Tamaño de parámetro incorrecto",
        InvalidParameterValue => "Valor(es) de parámetro inválido(s)",
        NotFound => "No encontrado",
        SymbolNotFound => "Símbolo no encontrado",
        ServerInvalidState => "Servidor en estado inválido",
        TransModeNotSupported => "Modo de transmisión no soportado",
        InvalidNotificationHandle => "Handle de notificación inválido",
        NoNotificationSubscribed => "Sin notificación suscrita",
        TimeoutElapsed => "Timeout agotado",
        InvalidClientTimeout => "Timeout de cliente inválido",
        _ => $"Error ADS desconocido (0x{code:X8})",
    };
}

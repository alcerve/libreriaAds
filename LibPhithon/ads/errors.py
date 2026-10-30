"""Excepciones y mapa de códigos de error ADS."""

_ERROR_MESSAGES = {
    0x00000000: "Sin error",
    0x00000001: "Error interno",
    0x00000002: "No hay runtime",
    0x00000006: "Puerto destino no encontrado",
    0x00000007: "Máquina destino no encontrada",
    0x00000008: "Comando desconocido",
    0x0000000E: "Longitud AMS inválida",
    0x0000000F: "AmsNetId inválido",
    0x00000012: "Puerto deshabilitado",
    0x00000013: "Puerto ya conectado",
    0x0000001B: "Host inalcanzable",
    0x00000701: "Servicio no soportado",
    0x00000702: "Grupo de índice inválido",
    0x00000703: "Offset de índice inválido",
    0x00000704: "Lectura/escritura no permitida",
    0x00000705: "Tamaño de parámetro incorrecto",
    0x00000706: "Valor(es) de parámetro inválido(s)",
    0x00000707: "Dispositivo no preparado",
    0x0000070C: "No encontrado",
    0x00000710: "Símbolo no encontrado",
    0x00000712: "Servidor en estado inválido",
    0x00000713: "Modo de transmisión no soportado",
    0x00000714: "Handle de notificación inválido",
    0x00000715: "Cliente de notificación no encontrado",
    0x00000716: "Sin notificación suscrita",
    0x00000745: "Timeout agotado",
    0x00000750: "Timeout de cliente inválido",
    0x00000760: "Desbordamiento de puerto",
    0x00000771: "Error de conversión de valor",
    0x00000790: "Valor no encontrado",
}


class AdsError(Exception):
    """Error del protocolo ADS con su código numérico.

    Atributos:
        code: código de error ADS (uint32).
    """

    def __init__(self, code=0x00000001, message=None):
        self.code = int(code) & 0xFFFFFFFF
        if message is None:
            message = _ERROR_MESSAGES.get(self.code, "Error ADS desconocido")
        super().__init__("ADS error 0x{:08X}: {}".format(self.code, message))

    def __repr__(self):
        return "AdsError(code=0x{:08X}, message={!r})".format(self.code, str(self))


def error_message(code):
    """Devuelve un texto legible para un código de error ADS."""
    return _ERROR_MESSAGES.get(int(code) & 0xFFFFFFFF, "Error ADS desconocido")

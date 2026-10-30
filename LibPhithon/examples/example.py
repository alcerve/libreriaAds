"""Ejemplo de uso de la librería ADS contra el simulador Flutter.

Requiere que el simulador esté en marcha (``dart run bin/server.dart`` o la app
Flutter) escuchando en 127.0.0.1:48898.

Ejecutar:  python examples/example.py
"""

import sys
import time

# Permite ejecutar el ejemplo sin instalar el paquete.
sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.dirname(__file__)))

from ads import AdsClient  # noqa: E402


def main():
    client = AdsClient(
        ams_net_id="127.0.0.1.1.1",
        ams_port=851,
        ip_address="127.0.0.1",
        tcp_port=48898,
        timeout=5.0,
    )
    with client:
        major, minor, build, name = client.read_device_info()
        print("Device info: v%d.%d (build %d) '%s'" % (major, minor, build, name))

        state, device_state = client.read_state()
        print("Estado ADS: %d, estado dispositivo: %d" % (state, device_state))

        counter = client.read_by_name("MAIN.nCounter", "UINT")
        temp = client.read_by_name("MAIN.fTemp", "REAL")
        message = client.read_by_name("MAIN.sMessage", "STRING(80)")
        values = client.read_by_name("MAIN.arrValues", "ARRAY[0..3] OF INT")
        print("nCounter=%d  fTemp=%.2f  sMessage=%r  arrValues=%s" % (counter, temp, message, values))

        # Escribir una variable BOOL.
        client.write_by_name("MAIN.bStart", True, "BOOL")
        print("MAIN.bStart -> %s" % client.read_by_name("MAIN.bStart", "BOOL"))

        # Handle.
        h = client.get_handle("MAIN.iLevel")
        print("Handle de MAIN.iLevel: %d" % h)
        level = client.read_by_handle(h, 2)
        print("iLevel (crudo): %r" % level)
        client.release_handle(h)

        # Notificación: observar cambios de nCounter durante ~1.2 s.
        seen = []

        def on_change(sample):
            seen.append(sample.data)

        nh = client.add_notification_by_name("MAIN.nCounter", "UINT", callback=on_change)
        time.sleep(1.2)
        client.del_device_notification(nh)
        print("Notificación activa %d; muestras recibidas: %d" % (nh, len(seen)))


if __name__ == "__main__":
    main()

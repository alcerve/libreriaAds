"""Verificación de integración: AdsClient (Python) contra el simulador Dart.

Uso:
    python examples/verify_simulator.py [puerto]     # puerto por defecto 48898
"""

import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from ads import AdsClient  # noqa: E402


def main():
    # Argumentos opcionales: [puerto_tcp] [ams_net_id] [ams_port] [ip]
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 48898
    net_id = sys.argv[2] if len(sys.argv) > 2 else "127.0.0.1.1.1"
    ams_port = int(sys.argv[3]) if len(sys.argv) > 3 else 851
    ip_address = sys.argv[4] if len(sys.argv) > 4 else "127.0.0.1"
    client = AdsClient(
        ams_net_id=net_id,
        ams_port=ams_port,
        ip_address=ip_address,
        tcp_port=port,
        timeout=5.0,
    )
    with client:
        print("Device info:", client.read_device_info())
        print("Estado:", client.read_state())
        print("nCounter:", client.read_by_name("MAIN.nCounter", "UINT"))
        print("fTemp:", client.read_by_name("MAIN.fTemp", "REAL"))
        print("sMessage:", client.read_by_name("MAIN.sMessage", "STRING(80)"))
        print("arrValues:", client.read_by_name("MAIN.arrValues", "ARRAY[0..3] OF INT"))

        client.write_by_name("MAIN.bStart", True, "BOOL")
        print("bStart tras escritura:", client.read_by_name("MAIN.bStart", "BOOL"))

        info = client.read_symbol_info("MAIN.nCounter")
        print("SymbolInfo:", info)

        handle = client.get_handle("MAIN.iLevel")
        print("Handle MAIN.iLevel:", handle, "crudo:", client.read_by_handle(handle, 2))
        client.release_handle(handle)

        # Notificación por cambio de MAIN.nCounter (se incrementa cada 500 ms).
        ninfo = client.read_symbol_info("MAIN.nCounter")
        samples = []
        nh = client.add_device_notification(
            ninfo.index_group,
            ninfo.index_offset,
            ninfo.size,
            trans_mode=4,
            callback=lambda s: samples.append(s.data),
        )
        print("Notificación handle:", nh)
        time.sleep(1.6)
        client.del_device_notification(nh)
        print("Muestras de notificación recibidas:", len(samples))
        if samples:
            print("Última muestra:", list(samples[-1]))

    print("INTEGRACIÓN OK")


if __name__ == "__main__":
    main()

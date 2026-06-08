"""
Gateway MQTT: Suscribe a sensores locales, publica en AWS IoT Core
Usa certificados X.509 para mutual-TLS, no credenciales IAM
"""

import paho.mqtt.client as mqtt
import json
import boto3
import os
import time
import ssl
import socket
from datetime import datetime
from pathlib import Path

# ============================================================================
# CONFIGURACIÓN MQTT LOCAL
# ============================================================================

MQTT_BROKER_LOCAL = os.getenv("MQTT_BROKER", "mosquitto")
MQTT_PORT_LOCAL = int(os.getenv("MQTT_PORT", "1883"))
MQTT_TOPICS_LOCAL = ["sensors/temperature", "sensors/humidity", "sensors/pressure"]

# ============================================================================
# CONFIGURACIÓN AWS IoT CORE
# ============================================================================

AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
AWS_IOT_ENDPOINT = os.getenv("AWS_IOT_ENDPOINT")
AWS_IOT_PORT = 8883
CERTS_DIR = Path(os.getenv("CERTS_DIR", "./certs"))

# Rutas de certificados (deben estar montados en volumen Docker)
CERT_PATH = CERTS_DIR / "iot-device-cert.pem"
KEY_PATH = CERTS_DIR / "iot-device-key.pem"
ROOT_CA_PATH = CERTS_DIR / "AmazonRootCA1.pem"

# ============================================================================
# FUNCIONES AUXILIARES
# ============================================================================


def discover_iot_endpoint():
    """Descubre el AWS IoT endpoint usando AWS CLI con reintentos exponenciales."""
    if AWS_IOT_ENDPOINT:
        return AWS_IOT_ENDPOINT

    backoff = 2
    for attempt in range(1, 11):
        try:
            print(f"[{attempt}/10] Descubriendo AWS IoT endpoint...")
            iot_client = boto3.client("iot", region_name=AWS_REGION)
            resp = iot_client.describe_endpoint(endpointType="iot:Data-ATS")
            endpoint = resp.get("endpointAddress")
            if endpoint:
                print(f"✓ Endpoint detectado: {endpoint}")
                return endpoint
        except Exception as e:
            err_msg = str(e)
            if "Unable to locate credentials" in err_msg:
                print("    Credenciales AWS no encontradas. Verifica que ~/.aws/credentials exista en el host.")
            else:
                print(f"    Intento {attempt} falló: {err_msg[:100]}")

        time.sleep(backoff)
        backoff = min(backoff * 2, 30)

    raise SystemExit(
        "ERROR: No se pudo descubrir AWS_IOT_ENDPOINT tras 10 intentos.\n"
        "Verifica que:\n"
        "  - El archivo ~/.aws/credentials exista en el host con credenciales válidas\n"
        "  - El token de Learner Lab no esté expirado\n"
        "  - Tengas permiso iot:DescribeEndpoint"
    )


def verify_certificates():
    """Verifica que los certificados X.509 existan y sean válidos."""
    required_files = [
        (CERT_PATH, "Certificado de dispositivo"),
        (KEY_PATH, "Clave privada"),
        (ROOT_CA_PATH, "CA raíz de Amazon"),
    ]

    missing = []
    for cert_file, desc in required_files:
        if not cert_file.exists():
            missing.append(f"  - {desc}: {cert_file}")

    if missing:
        print("ERROR: Certificados X.509 no encontrados:")
        for m in missing:
            print(m)
        print(
            "\nPara generar certificados, ejecuta:"
            r"\n  .\scripts\provision-iot-certificates.ps1"
            "\no en Linux/Mac:"
            "\n  bash scripts/provision-iot-certificates.sh"
        )
        raise SystemExit(1)

    print("✓ Certificados X.509 verificados")
    print(f"  - Certificado: {CERT_PATH}")
    print(f"  - Clave privada: {KEY_PATH}")
    print(f"  - CA raíz: {ROOT_CA_PATH}")


# ============================================================================
# GATEWAY MQTT
# ============================================================================


class MQTTGateway:
    """
    Gateway bidireccional:
    - Suscribe a sensores locales (sensores/temperature, etc)
    - Publica en AWS IoT Core usando certificados X.509
    """

    def __init__(self, aws_endpoint: str):
        """Inicializa clientes MQTT locales y AWS IoT"""

        self.aws_endpoint = aws_endpoint
        self.message_count = 0

        # ====================================================================
        # Cliente MQTT Local (suscriptor a sensores)
        # ====================================================================

        self.local_client = mqtt.Client(
            callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
            client_id="gateway-local-subscriber",
        )

        self.local_client.on_connect = self._on_local_connect
        self.local_client.on_message = self._on_local_message
        self.local_client.on_disconnect = self._on_local_disconnect

        # ====================================================================
        # Cliente MQTT AWS IoT (publicador con certificados TLS)
        # ====================================================================

        self.aws_client = mqtt.Client(
            callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
            client_id="gateway-iot-publisher",
        )

        self.aws_client.on_connect = self._on_aws_connect
        self.aws_client.on_disconnect = self._on_aws_disconnect
        self.aws_client.on_publish = self._on_aws_publish

        # Configurar TLS con certificados X.509
        try:
            self.aws_client.tls_set(
                ca_certs=str(ROOT_CA_PATH),
                certfile=str(CERT_PATH),
                keyfile=str(KEY_PATH),
                cert_reqs=ssl.CERT_REQUIRED,
                tls_version=ssl.PROTOCOL_TLSv1_2,
                ciphers=None,
            )
            # Desabilitar verificación de hostname para testing (mejor: True en producción)
            self.aws_client.tls_insecure_set(False)
            print("✓ TLS configurado con certificados X.509")
        except Exception as e:
            raise SystemExit(f"ERROR: No se pudo configurar TLS: {e}")

    def _on_local_connect(self, client, userdata, flags, reason_code, properties=None):
        """Callback: conexión a MQTT local exitosa"""
        if reason_code == 0:
            print(f"✓ Conectado a MQTT local ({MQTT_BROKER_LOCAL}:{MQTT_PORT_LOCAL})")
            for topic in MQTT_TOPICS_LOCAL:
                client.subscribe(topic)
                print(f"  ├─ Suscrito a: {topic}")
        else:
            print(f"✗ Error conexión MQTT local (código: {reason_code})")

    def _on_local_message(self, client, userdata, message):
        """Callback: mensaje recibido de sensor local"""
        try:
            payload = json.loads(message.payload.decode())
            self.message_count += 1
            timestamp = datetime.utcnow().isoformat()

            print(
                f"\n[{self.message_count}] Mensaje recibido en {timestamp}"
                f"\n  Topic local: {message.topic}"
                f"\n  Payload: {payload}"
            )

            # Reenviar a AWS IoT Core
            try:
                # Publicar en AWS IoT en el mismo topic
                self.aws_client.publish(
                    topic=message.topic, qos=1, payload=json.dumps(payload)
                )
                print(f"  ✓ Reenviado a AWS IoT Core: {message.topic}")

            except Exception as e:
                print(f"  ✗ Error publicando en AWS IoT: {e}")

        except json.JSONDecodeError:
            print(f"✗ Error decodificando JSON: {message.payload}")
        except Exception as e:
            print(f"✗ Error procesando mensaje: {e}")

    def _on_local_disconnect(
        self, client, userdata, flags=None, reason_code=None, properties=None
    ):
        """Callback: desconexión de MQTT local"""
        if reason_code and reason_code != 0:
            print(f"✗ Desconexión inesperada de MQTT local (código: {reason_code})")

    def _on_aws_connect(self, client, userdata, flags, reason_code, properties=None):
        """Callback: conexión a AWS IoT Core exitosa"""
        if reason_code == 0:
            print(f"\n✓ Conectado a AWS IoT Core ({self.aws_endpoint}:{AWS_IOT_PORT})")
            print("  Certificados X.509 validados correctamente")
        else:
            print(f"✗ Error conexión AWS IoT (código: {reason_code})")
            if reason_code == 1:
                print(
                    "  Hint: Verifica que los certificados sean válidos y estén correctamente montados"
                )

    def _on_aws_disconnect(
        self, client, userdata, flags=None, reason_code=None, properties=None
    ):
        """Callback: desconexión de AWS IoT"""
        if reason_code and reason_code != 0:
            print(f"✗ Desconexión inesperada de AWS IoT (código: {reason_code})")

    def _on_aws_publish(self, client, userdata, mid):
        """Callback: confirmación de publicación en AWS IoT"""
        # Silencioso para no saturar logs
        pass

    def connect_local(self):
        """Conecta a MQTT local y mantiene conexión"""
        try:
            print(f"\nConectando a MQTT local ({MQTT_BROKER_LOCAL}:{MQTT_PORT_LOCAL})...")
            self.local_client.connect(MQTT_BROKER_LOCAL, MQTT_PORT_LOCAL, keepalive=60)
            self.local_client.loop_start()
            # Dar tiempo para establecer conexión
            time.sleep(2)
        except Exception as e:
            raise SystemExit(f"ERROR: No se pudo conectar a MQTT local: {e}")

    def connect_aws(self):
        """Conecta a AWS IoT Core con certificados X.509"""
        try:
            print(f"\nConectando a AWS IoT Core ({self.aws_endpoint}:{AWS_IOT_PORT})...")
            print("  Usando autenticación mutua TLS (certificados X.509)...")

            self.aws_client.connect(
                self.aws_endpoint, AWS_IOT_PORT, keepalive=60, clean_start=True
            )
            self.aws_client.loop_start()

            # Dar tiempo para establecer conexión
            time.sleep(2)

        except Exception as e:
            raise SystemExit(f"ERROR: No se pudo conectar a AWS IoT Core: {e}")

    def run(self):
        """Mantiene el gateway activo"""
        try:
            print("\n" + "=" * 70)
            print("GATEWAY ACTIVO")
            print("=" * 70)
            print("\nRecibirá mensajes de sensores locales y los reenviará a AWS IoT Core.")
            print("Presiona Ctrl+C para detener.\n")

            while True:
                time.sleep(1)

        except KeyboardInterrupt:
            print("\n\nShutdown solicitado...")

    def disconnect(self):
        """Desconecta ambos clientes"""
        print("\nDesconectando...")
        self.local_client.loop_stop()
        self.local_client.disconnect()
        self.aws_client.loop_stop()
        self.aws_client.disconnect()
        print(f"✓ Gateway detenido (procesó {self.message_count} mensajes)")


# ============================================================================
# MAIN
# ============================================================================


def main():
    print("\n" + "=" * 70)
    print("AWS IoT Gateway - Sensor Local Forwarder")
    print("=" * 70)

    # Verificar certificados
    print("\n[1/4] Verificando certificados X.509...")
    verify_certificates()

    # Descubrir endpoint
    print("\n[2/4] Descubriendo AWS IoT endpoint...")
    try:
        endpoint = discover_iot_endpoint()
    except SystemExit:
        print("✗ No se pudo descubrir el endpoint. Verifica tus credenciales AWS.")
        raise

    # Inicializar gateway
    print("\n[3/4] Inicializando gateway MQTT...")
    gateway = MQTTGateway(endpoint)

    # Conectar
    print("\n[4/4] Estableciendo conexiones...")
    try:
        gateway.connect_local()
        gateway.connect_aws()
    except SystemExit as e:
        print(f"✗ Error durante conexión: {e}")
        raise

    # Ejecutar
    try:
        gateway.run()
    except KeyboardInterrupt:
        pass
    finally:
        gateway.disconnect()


if __name__ == "__main__":
    main()

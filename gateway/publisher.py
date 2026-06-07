import paho.mqtt.client as mqtt
import json
import boto3
import os
import time
from datetime import datetime

# Configuración MQTT Local
# Por defecto usa el nombre del servicio "mosquitto" en docker compose.
# Si MQTT_BROKER está definido como variable de entorno, se respeta ese valor
# (útil cuando corres el gateway fuera de compose: e.g. MQTT_BROKER=localhost).
MQTT_BROKER = os.getenv("MQTT_BROKER", "mosquitto")
MQTT_PORT = int(os.getenv("MQTT_PORT", "1883"))
MQTT_TOPICS = ["sensors/temperature", "sensors/humidity", "sensors/pressure"]

# Configuración AWS
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
AWS_ENDPOINT = os.getenv("AWS_IOT_ENDPOINT")


def discover_iot_endpoint():
    """Descubre el AWS IoT endpoint con reintentos exponenciales."""
    if AWS_ENDPOINT:
        return AWS_ENDPOINT
    backoff = 2
    for attempt in range(1, 11):
        try:
            print(f"[{attempt}] Intentando descubrir AWS IoT endpoint...")
            iot_client = boto3.client("iot", region_name=AWS_REGION)
            resp = iot_client.describe_endpoint(endpointType="iot:Data-ATS")
            endpoint = resp.get("endpointAddress")
            if endpoint:
                print(f"Endpoint detectado: {endpoint}")
                return endpoint
        except Exception as e:
            print(f"[{attempt}] No se pudo descubrir el endpoint: {e}")
        time.sleep(backoff)
        backoff = min(backoff * 2, 30)
    raise SystemExit(
        "ERROR: no se pudo descubrir AWS_IOT_ENDPOINT tras varios intentos. "
        "Verifica que las credenciales AWS estén disponibles dentro del contenedor "
        "(`docker exec gateway-1 aws sts get-caller-identity`)."
    )

class MQTTGateway:
    def __init__(self, endpoint: str | None = None):
        resolved_endpoint = endpoint or AWS_ENDPOINT
        if not resolved_endpoint:
            raise SystemExit(
                "ERROR: AWS_IOT_ENDPOINT no está definido. "
                "Pásalo como argumento o exporta la variable de entorno."
            )

        # paho-mqtt 2.x requiere callback_api_version explícito
        self.local_client = mqtt.Client(
            callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
            client_id="gateway-subscriber",
        )
        self.local_client.on_connect = self.on_connect
        self.local_client.on_message = self.on_message
        self.local_client.on_disconnect = self.on_disconnect

        # Cliente para AWS IoT (opcional si usamos credenciales)
        self.dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
        self.s3 = boto3.client("s3", region_name=AWS_REGION)
        endpoint_url = f"https://{resolved_endpoint}"
        try:
            self.iot_data = boto3.client("iot-data", region_name=AWS_REGION, endpoint_url=endpoint_url)
            print(f"Gateway: cliente IoT Data inicializado en {endpoint_url}")
        except Exception as e:
            raise SystemExit(f"ERROR: no se pudo inicializar iot-data client: {e}")

    def on_connect(self, client, userdata, flags, reason_code, properties=None):
        if reason_code == 0:
            print("Gateway: Conectado a MQTT local")
            for topic in MQTT_TOPICS:
                self.local_client.subscribe(topic)
                print(f"Suscrito a: {topic}")
        else:
            print(f"Gateway: Error conexión {reason_code}")

    def on_message(self, client, userdata, message):
        payload = None
        try:
            payload = json.loads(message.payload.decode())
            print(f"Mensaje recibido de {message.topic}: {payload}")

            # Procesar según el tipo de sensor
            if "temperature" in message.topic:
                self.process_temperature(payload)
            elif "humidity" in message.topic:
                self.process_humidity(payload)
            elif "pressure" in message.topic:
                self.process_pressure(payload)

        except json.JSONDecodeError:
            print(f"Error decodificando JSON: {message.payload}")
        except Exception as e:
            print(f"Error procesando mensaje: {e}")
        finally:
            # Reenviar a AWS IoT (obligatorio)
            try:
                publish_payload = json.dumps(payload) if payload is not None else message.payload.decode()
                self.iot_data.publish(topic=message.topic, qos=0, payload=publish_payload)
                print(f"Reenviado a AWS IoT: {message.topic}")
            except Exception as e:
                print(f"Error publicando en AWS IoT: {e}")

    def on_disconnect(self, client, userdata, flags=None, reason_code=None, properties=None):
        if reason_code != 0:
            print(f"Gateway: Desconexión inesperada {reason_code}")
    
    def process_temperature(self, data):
        """Procesar datos de temperatura"""
        try:
            # Aquí puedes agregar lógica para guardar en DynamoDB, S3, etc.
            print(f"Procesando temperatura: {data['value']}°C")
            # Ejemplo: self.save_to_dynamodb("temperatures", data)
        except Exception as e:
            print(f"Error procesando temperatura: {e}")
    
    def process_humidity(self, data):
        """Procesar datos de humedad"""
        try:
            # Aquí puedes agregar lógica para guardar en DynamoDB, S3, etc.
            print(f"Procesando humedad: {data['value']}%")
            # Ejemplo: self.save_to_dynamodb("humidity", data)
        except Exception as e:
            print(f"Error procesando humedad: {e}")
    
    def process_pressure(self, data):
        """Procesar datos de presión"""
        try:
            # Aquí puedes agregar lógica para guardar en DynamoDB, S3, etc.
            print(f"Procesando presión: {data['value']} hPa")
            # Ejemplo: self.save_to_dynamodb("pressure", data)
        except Exception as e:
            print(f"Error procesando presión: {e}")
    
    def save_to_dynamodb(self, table_name, data):
        """Guardar datos en DynamoDB"""
        try:
            table = self.dynamodb.Table(table_name)
            item = {
                "timestamp": int(datetime.utcnow().timestamp()),
                "sensor_id": data.get("sensor_id"),
                "value": data.get("value"),
                "unit": data.get("unit"),
                "data": json.dumps(data)
            }
            table.put_item(Item=item)
            print(f"Datos guardados en {table_name}")
        except Exception as e:
            print(f"Error guardando en DynamoDB: {e}")
    
    def connect(self):
        try:
            self.local_client.connect(MQTT_BROKER, MQTT_PORT, keepalive=60)
            self.local_client.loop_forever()
        except Exception as e:
            print(f"Error al conectar: {e}")
    
    def disconnect(self):
        self.local_client.disconnect()

if __name__ == "__main__":
    AWS_ENDPOINT = discover_iot_endpoint()
    gateway = MQTTGateway(endpoint=AWS_ENDPOINT)
    try:
        gateway.connect()
    except KeyboardInterrupt:
        gateway.disconnect()
        print("Gateway desconectado")

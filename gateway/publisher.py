import paho.mqtt.client as mqtt
import json
import boto3
import os
from datetime import datetime

# Configuración MQTT Local
MQTT_BROKER = "mosquitto"
MQTT_PORT = 1883
MQTT_TOPICS = ["sensors/temperature", "sensors/humidity", "sensors/pressure"]

# Configuración AWS
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
AWS_ENDPOINT = os.getenv("AWS_IOT_ENDPOINT")
# Si no está definida, intentar descubrir el endpoint a través de las credenciales configuradas (aws configure)
if not AWS_ENDPOINT:
    try:
        print("Intentando descubrir AWS IoT endpoint usando las credenciales configuradas...")
        iot_client = boto3.client("iot", region_name=AWS_REGION)
        resp = iot_client.describe_endpoint(endpointType="iot:Data-ATS")
        AWS_ENDPOINT = resp.get("endpointAddress")
        if not AWS_ENDPOINT:
            raise Exception("describe_endpoint no devolvió endpointAddress")
        print(f"Endpoint detectado: {AWS_ENDPOINT}")
    except Exception as e:
        raise SystemExit(
            "ERROR: no se encontró AWS_IOT_ENDPOINT y no se pudo descubrir automáticamente. "
            "Asegúrate de haber ejecutado 'aws configure' con credenciales válidas y de que la IAM tenga permiso 'iot:DescribeEndpoint'. Detalle: " + str(e)
        )

class MQTTGateway:
    def __init__(self):
        self.local_client = mqtt.Client("gateway-subscriber")
        self.local_client.on_connect = self.on_connect
        self.local_client.on_message = self.on_message
        self.local_client.on_disconnect = self.on_disconnect
        
        # Cliente para AWS IoT (opcional si usamos credenciales)
        self.dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
        self.s3 = boto3.client("s3", region_name=AWS_REGION)
        endpoint_url = f"https://{AWS_ENDPOINT}"
        try:
            self.iot_data = boto3.client("iot-data", region_name=AWS_REGION, endpoint_url=endpoint_url)
            print(f"Gateway: cliente IoT Data inicializado en {endpoint_url}")
        except Exception as e:
            raise SystemExit(f"ERROR: no se pudo inicializar iot-data client: {e}")
        
    def on_connect(self, client, userdata, flags, rc):
        if rc == 0:
            print("Gateway: Conectado a MQTT local")
            for topic in MQTT_TOPICS:
                self.local_client.subscribe(topic)
                print(f"Suscrito a: {topic}")
        else:
            print(f"Gateway: Error conexión {rc}")
    
    def on_message(self, client, userdata, msg):
        payload = None
        try:
            payload = json.loads(msg.payload.decode())
            print(f"Mensaje recibido de {msg.topic}: {payload}")
            
            # Procesar según el tipo de sensor
            if "temperature" in msg.topic:
                self.process_temperature(payload)
            elif "humidity" in msg.topic:
                self.process_humidity(payload)
            elif "pressure" in msg.topic:
                self.process_pressure(payload)
                
        except json.JSONDecodeError:
            print(f"Error decodificando JSON: {msg.payload}")
        except Exception as e:
            print(f"Error procesando mensaje: {e}")
        finally:
            # Reenviar a AWS IoT (obligatorio)
            try:
                publish_payload = json.dumps(payload) if payload is not None else msg.payload.decode()
                self.iot_data.publish(topic=msg.topic, qos=0, payload=publish_payload)
                print(f"Reenviado a AWS IoT: {msg.topic}")
            except Exception as e:
                print(f"Error publicando en AWS IoT: {e}")
    
    def on_disconnect(self, client, userdata, rc):
        if rc != 0:
            print(f"Gateway: Desconexión inesperada {rc}")
    
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
    gateway = MQTTGateway()
    try:
        gateway.connect()
    except KeyboardInterrupt:
        gateway.disconnect()
        print("Gateway desconectado")

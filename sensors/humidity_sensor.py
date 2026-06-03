import paho.mqtt.client as mqtt
import json
import time
import random
from datetime import datetime

MQTT_BROKER = "mosquitto"
MQTT_PORT = 1883
MQTT_TOPIC = "sensors/humidity"

class HumiditySensor:
    def __init__(self):
        self.client = mqtt.Client()
        self.client.on_connect = self.on_connect
        self.client.on_disconnect = self.on_disconnect
        
    def on_connect(self, client, userdata, flags, rc):
        if rc == 0:
            print("Humedad Sensor: Conectado a MQTT")
        else:
            print(f"Humedad Sensor: Error conexión {rc}")
    
    def on_disconnect(self, client, userdata, rc):
        if rc != 0:
            print(f"Humedad Sensor: Desconexión inesperada {rc}")
    
    def connect(self):
        try:
            self.client.connect(MQTT_BROKER, MQTT_PORT, keepalive=60)
            self.client.loop_start()
        except Exception as e:
            print(f"Error al conectar: {e}")
    
    def publish_humidity(self):
        while True:
            try:
                # Simular lectura de sensor (entre 30% y 80%)
                humidity = round(30 + random.uniform(0, 50), 2)
                
                payload = {
                    "timestamp": datetime.utcnow().isoformat(),
                    "value": humidity,
                    "unit": "percent",
                    "sensor_id": "humidity-001"
                }
                
                self.client.publish(MQTT_TOPIC, json.dumps(payload))
                print(f"Publicado: {humidity}%")
                
                time.sleep(5)  # Publicar cada 5 segundos
            except Exception as e:
                print(f"Error al publicar: {e}")
                time.sleep(5)
    
    def disconnect(self):
        self.client.loop_stop()
        self.client.disconnect()

if __name__ == "__main__":
    sensor = HumiditySensor()
    sensor.connect()
    try:
        sensor.publish_humidity()
    except KeyboardInterrupt:
        sensor.disconnect()
        print("Sensor de humedad desconectado")

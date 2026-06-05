import paho.mqtt.client as mqtt
import json
import time
import random
from datetime import datetime

MQTT_BROKER = "mosquitto"
MQTT_PORT = 1883
MQTT_TOPIC = "sensors/pressure"

class PressureSensor:
    def __init__(self):
        self.client = mqtt.Client()
        self.client.on_connect = self.on_connect
        self.client.on_disconnect = self.on_disconnect
        
    def on_connect(self, client, userdata, flags, rc):
        if rc == 0:
            print("Presión Sensor: Conectado a MQTT")
        else:
            print(f"Presión Sensor: Error conexión {rc}")
    
    def on_disconnect(self, client, userdata, rc):
        if rc != 0:
            print(f"Presión Sensor: Desconexión inesperada {rc}")
    
    def connect(self):
        try:
            self.client.connect(MQTT_BROKER, MQTT_PORT, keepalive=60)
            self.client.loop_start()
        except Exception as e:
            print(f"Error al conectar: {e}")
    
    def publish_pressure(self):
        while True:
            try:
                # Simular lectura de sensor (entre 980 y 1040 hPa)
                pressure = round(980 + random.uniform(0, 60), 2)
                
                payload = {
                    "timestamp": datetime.utcnow().isoformat(),
                    "value": pressure,
                    "unit": "hPa",
                    "sensor_id": "pressure-001"
                }
                
                self.client.publish(MQTT_TOPIC, json.dumps(payload))
                print(f"Publicado: {pressure} hPa")
                
                time.sleep(5)  # Publicar cada 5 segundos
                
            except Exception as e:
                print(f"Error publicando: {e}")
                time.sleep(5)

def main():
    sensor = PressureSensor()
    sensor.connect()
    sensor.publish_pressure()

if __name__ == "__main__":
    main()

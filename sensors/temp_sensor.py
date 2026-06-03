import paho.mqtt.client as mqtt
import json
import time
import random
from datetime import datetime

MQTT_BROKER = "mosquitto"
MQTT_PORT = 1883
MQTT_TOPIC = "sensors/temperature"

class TemperatureSensor:
    def __init__(self):
        self.client = mqtt.Client()
        self.client.on_connect = self.on_connect
        self.client.on_disconnect = self.on_disconnect
        
    def on_connect(self, client, userdata, flags, rc):
        if rc == 0:
            print("Temperatura Sensor: Conectado a MQTT")
        else:
            print(f"Temperatura Sensor: Error conexión {rc}")
    
    def on_disconnect(self, client, userdata, rc):
        if rc != 0:
            print(f"Temperatura Sensor: Desconexión inesperada {rc}")
    
    def connect(self):
        try:
            self.client.connect(MQTT_BROKER, MQTT_PORT, keepalive=60)
            self.client.loop_start()
        except Exception as e:
            print(f"Error al conectar: {e}")
    
    def publish_temperature(self):
        while True:
            try:
                # Simular lectura de sensor (entre 15°C y 35°C)
                temperature = round(15 + random.uniform(0, 20), 2)
                
                payload = {
                    "timestamp": datetime.utcnow().isoformat(),
                    "value": temperature,
                    "unit": "celsius",
                    "sensor_id": "temp-001"
                }
                
                self.client.publish(MQTT_TOPIC, json.dumps(payload))
                print(f"Publicado: {temperature}°C")
                
                time.sleep(5)  # Publicar cada 5 segundos
            except Exception as e:
                print(f"Error al publicar: {e}")
                time.sleep(5)
    
    def disconnect(self):
        self.client.loop_stop()
        self.client.disconnect()

if __name__ == "__main__":
    sensor = TemperatureSensor()
    sensor.connect()
    try:
        sensor.publish_temperature()
    except KeyboardInterrupt:
        sensor.disconnect()
        print("Sensor de temperatura desconectado")

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import boto3
import os
from datetime import datetime, timedelta
from typing import Optional, List
from pydantic import BaseModel
import time

# Configuración
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
DYNAMODB_TABLE = os.getenv("DYNAMODB_TABLE", "sensor-data-dev")
ATHENA_WORKGROUP = os.getenv("ATHENA_WORKGROUP", "sensor-queries-dev")

app = FastAPI(title="IoT Sensors API")

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Modelos
class SensorReading(BaseModel):
    timestamp: str
    sensor_id: str
    value: float
    unit: str
    sensor_type: Optional[str] = None

class SensorData(BaseModel):
    temperature: Optional[float] = None
    humidity: Optional[float] = None
    timestamp: str

# Inicializar clientes
dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
s3_client = boto3.client("s3", region_name=AWS_REGION)
athena_client = boto3.client("athena", region_name=AWS_REGION)

# Tabla DynamoDB
table = dynamodb.Table(DYNAMODB_TABLE)

# Rutas
@app.get("/")
async def root():
    return {
        "message": "IoT Sensors API (DynamoDB backend)",
        "version": "2.0.0",
        "endpoints": {
            "sensors": "/sensors",
            "temperature": "/sensors/temperature",
            "humidity": "/sensors/humidity",
            "pressure": "/sensors/pressure",
            "current": "/sensors/current",
            "history": "/sensors/history",
            "sensor_by_id": "/sensors/{sensor_id}"
        }
    }

@app.get("/sensors")
async def get_all_sensors():
    """Obtener todos los sensores registrados"""
    try:
        # Scan de la tabla para obtener sensor_ids únicos
        response = table.scan(
            ProjectionExpression='sensor_id, sensor_type, #u',
            ExpressionAttributeNames={'#u': 'unit'}
        )
        
        sensors_dict = {}
        for item in response.get('Items', []):
            sensor_id = item.get('sensor_id', 'unknown')
            if sensor_id not in sensors_dict:
                sensors_dict[sensor_id] = {
                    "id": sensor_id,
                    "type": item.get('sensor_type', 'unknown'),
                    "unit": item.get('unit', '')
                }
        
        return {
            "sensors": list(sensors_dict.values()),
            "total": len(sensors_dict)
        }
    except Exception as e:
        print(f"Error obteniendo sensores: {e}")
        return {"error": str(e), "sensors": []}

@app.get("/sensors/{sensor_id}")
async def get_sensor_by_id(sensor_id: str, hours: int = 24):
    """Obtener datos de un sensor específico de las últimas N horas"""
    try:
        current_time = int(time.time())
        start_time = current_time - (hours * 3600)
        
        # Query DynamoDB
        response = table.query(
            KeyConditionExpression='sensor_id = :sid AND #ts BETWEEN :start AND :end',
            ExpressionAttributeNames={'#ts': 'timestamp'},
            ExpressionAttributeValues={
                ':sid': sensor_id,
                ':start': start_time,
                ':end': current_time
            },
            ScanIndexForward=False,  # Descendiente (más reciente primero)
            Limit=100
        )
        
        readings = []
        for item in response.get('Items', []):
            readings.append({
                "timestamp": item.get('timestamp'),
                "value": float(item.get('value', 0)),
                "unit": item.get('unit', ''),
                "sensor_id": item.get('sensor_id'),
                "sensor_type": item.get('sensor_type')
            })
        
        return {
            "sensor_id": sensor_id,
            "readings": readings,
            "count": len(readings)
        }
    except Exception as e:
        print(f"Error obteniendo sensor {sensor_id}: {e}")
        return {"error": str(e), "readings": []}

@app.get("/sensors/temperature")
async def get_temperature(hours: int = 24):
    """Obtener datos de temperatura de las últimas N horas"""
    try:
        current_time = int(time.time())
        start_time = current_time - (hours * 3600)
        
        # Scan con filtro por sensor_type
        response = table.scan(
            FilterExpression='sensor_type = :st AND #ts BETWEEN :start AND :end',
            ExpressionAttributeNames={'#ts': 'timestamp'},
            ExpressionAttributeValues={
                ':st': 'temperature',
                ':start': start_time,
                ':end': current_time
            },
            ProjectionExpression='timestamp, #v, #u, sensor_id, sensor_type',
            ExpressionAttributeNames={'#v': 'value', '#u': 'unit'},
            Limit=100
        )
        
        readings = []
        for item in response.get('Items', []):
            readings.append({
                "timestamp": item.get('timestamp'),
                "value": float(item.get('value', 0)),
                "unit": item.get('unit', 'celsius'),
                "sensor_id": item.get('sensor_id')
            })
        
        return {
            "sensor_id": "temp-001",
            "readings": readings,
            "count": len(readings)
        }
    except Exception as e:
        print(f"Error obteniendo temperatura: {e}")
        return {"error": str(e), "data": []}

@app.get("/sensors/humidity")
async def get_humidity(hours: int = 24):
    """Obtener datos de humedad de las últimas N horas"""
    try:
        current_time = int(time.time())
        start_time = current_time - (hours * 3600)
        
        # Scan con filtro por sensor_type
        response = table.scan(
            FilterExpression='sensor_type = :st AND #ts BETWEEN :start AND :end',
            ExpressionAttributeNames={'#ts': 'timestamp'},
            ExpressionAttributeValues={
                ':st': 'humidity',
                ':start': start_time,
                ':end': current_time
            },
            ProjectionExpression='timestamp, #v, #u, sensor_id, sensor_type',
            ExpressionAttributeNames={'#v': 'value', '#u': 'unit'},
            Limit=100
        )
        
        readings = []
        for item in response.get('Items', []):
            readings.append({
                "timestamp": item.get('timestamp'),
                "value": float(item.get('value', 0)),
                "unit": item.get('unit', 'percent'),
                "sensor_id": item.get('sensor_id')
            })
        
        return {
            "sensor_id": "humidity-001",
            "readings": readings,
            "count": len(readings)
        }
    except Exception as e:
        print(f"Error obteniendo humedad: {e}")
        return {"error": str(e), "data": []}

@app.get("/sensors/pressure")
async def get_pressure(hours: int = 24):
    """Obtener datos de presión de las últimas N horas"""
    try:
        current_time = int(time.time())
        start_time = current_time - (hours * 3600)
        
        # Scan con filtro por sensor_type
        response = table.scan(
            FilterExpression='sensor_type = :st AND #ts BETWEEN :start AND :end',
            ExpressionAttributeNames={'#ts': 'timestamp'},
            ExpressionAttributeValues={
                ':st': 'pressure',
                ':start': start_time,
                ':end': current_time
            },
            ProjectionExpression='timestamp, #v, #u, sensor_id, sensor_type',
            ExpressionAttributeNames={'#v': 'value', '#u': 'unit'},
            Limit=100
        )
        
        readings = []
        for item in response.get('Items', []):
            readings.append({
                "timestamp": item.get('timestamp'),
                "value": float(item.get('value', 0)),
                "unit": item.get('unit', 'hPa'),
                "sensor_id": item.get('sensor_id')
            })
        
        return {
            "sensor_id": "pressure-001",
            "readings": readings,
            "count": len(readings)
        }
    except Exception as e:
        print(f"Error obteniendo presión: {e}")
        return {"error": str(e), "data": []}

@app.get("/sensors/current")
async def get_current_reading():
    """Obtener lecturas actuales (última lectura de cada tipo de sensor)"""
    try:
        current_readings = {}
        
        # Obtener último de cada sensor_type haciendo scan
        for sensor_type in ['temperature', 'humidity', 'pressure']:
            response = table.scan(
                FilterExpression='sensor_type = :st',
                ExpressionAttributeValues={':st': sensor_type},
                ProjectionExpression='timestamp, #v, #u, sensor_id',
                ExpressionAttributeNames={'#v': 'value', '#u': 'unit'},
                Limit=1
            )
            
            if response.get('Items'):
                item = response['Items'][0]
                current_readings[sensor_type] = {
                    "value": float(item.get('value', 0)),
                    "timestamp": item.get('timestamp'),
                    "unit": item.get('unit'),
                    "sensor_id": item.get('sensor_id')
                }
        
        return {
            "temperature": current_readings.get('temperature'),
            "humidity": current_readings.get('humidity'),
            "pressure": current_readings.get('pressure'),
            "timestamp": datetime.utcnow().isoformat()
        }
    except Exception as e:
        print(f"Error obteniendo lecturas actuales: {e}")
        return {"error": str(e)}

@app.get("/sensors/history")
async def get_history(sensor_type: str = "temperature", limit: int = 100):
    """Obtener historial de sensores de un tipo específico"""
    try:
        response = table.scan(
            FilterExpression='sensor_type = :st',
            ExpressionAttributeValues={':st': sensor_type},
            ProjectionExpression='timestamp, #v, #u, sensor_id',
            ExpressionAttributeNames={'#v': 'value', '#u': 'unit'},
            Limit=limit
        )
        
        readings = []
        for item in response.get('Items', []):
            readings.append({
                "timestamp": item.get('timestamp'),
                "value": float(item.get('value', 0)),
                "unit": item.get('unit', ''),
                "sensor_id": item.get('sensor_id')
            })
        
        return {
            "sensor_type": sensor_type,
            "readings": readings,
            "count": len(readings)
        }
    except Exception as e:
        print(f"Error obteniendo historial: {e}")
        return {"error": str(e)}

@app.post("/sensors/reading")
async def post_reading(data: SensorReading):
    """Guardar una lectura de sensor en DynamoDB"""
    try:
        # Parsear timestamp si es string ISO
        if isinstance(data.timestamp, str):
            try:
                dt = datetime.fromisoformat(data.timestamp.replace('Z', '+00:00'))
                timestamp = int(dt.timestamp())
            except:
                timestamp = int(time.time())
        else:
            timestamp = int(data.timestamp) if data.timestamp else int(time.time())
        
        # Crear item
        item = {
            'sensor_id': data.sensor_id,
            'timestamp': timestamp,
            'value': float(data.value),
            'unit': data.unit,
            'sensor_type': data.sensor_type or 'unknown'
        }
        
        # TTL de 30 días
        item['expiration'] = int(time.time()) + (30 * 24 * 60 * 60)
        
        # Guardar en DynamoDB
        table.put_item(Item=item)
        
        return {
            "status": "ok",
            "message": "Lectura guardada",
            "timestamp": timestamp,
            "sensor_id": data.sensor_id
        }
    except Exception as e:
        print(f"Error guardando lectura: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health_check():
    """Health check"""
    try:
        # Verificar que se puede acceder a DynamoDB
        table.table_status
        return {
            "status": "healthy",
            "timestamp": datetime.utcnow().isoformat(),
            "dynamodb_table": DYNAMODB_TABLE
        }
    except Exception as e:
        print(f"Health check falló: {e}")
        return {
            "status": "degraded",
            "timestamp": datetime.utcnow().isoformat(),
            "error": str(e)
        }


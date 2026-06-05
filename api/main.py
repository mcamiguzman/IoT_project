from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import boto3
import psycopg2
import os
from datetime import datetime, timedelta
from typing import Optional, List
from pydantic import BaseModel

# Configuración
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_NAME = os.getenv("DB_NAME", "sensors_db")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "postgres")

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

class SensorData(BaseModel):
    temperature: Optional[float] = None
    humidity: Optional[float] = None
    timestamp: str

# Inicializar clientes
dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
s3_client = boto3.client("s3", region_name=AWS_REGION)

def get_db_connection():
    """Obtener conexión a PostgreSQL"""
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD
        )
        return conn
    except Exception as e:
        print(f"Error conectando a PostgreSQL: {e}")
        return None

# Rutas
@app.get("/")
async def root():
    return {
        "message": "IoT Sensors API",
        "version": "1.0.0",
        "endpoints": {
            "sensors": "/sensors",
            "temperature": "/sensors/temperature",
            "humidity": "/sensors/humidity",
            "pressure": "/sensors/pressure",
            "current": "/sensors/current",
            "history": "/sensors/history"
        }
    }

@app.get("/sensors")
async def get_all_sensors():
    """Obtener todos los sensores"""
    return {
        "sensors": [
            {"id": "temp-001", "type": "temperature", "unit": "celsius"},
            {"id": "humidity-001", "type": "humidity", "unit": "percent"},
            {"id": "pressure-001", "type": "pressure", "unit": "hPa"}
        ]
    }

@app.get("/sensors/temperature")
async def get_temperature(hours: int = 24):
    """Obtener datos de temperatura de las últimas N horas"""
    try:
        conn = get_db_connection()
        if not conn:
            return {"error": "No se pudo conectar a la base de datos", "data": []}
        
        cursor = conn.cursor()
        query = """
            SELECT timestamp, value, unit, sensor_id 
            FROM temperature_readings 
            WHERE timestamp > NOW() - INTERVAL '%s hours'
            ORDER BY timestamp DESC
            LIMIT 100
        """
        cursor.execute(query, (hours,))
        results = cursor.fetchall()
        cursor.close()
        conn.close()
        
        readings = [
            {
                "timestamp": str(row[0]),
                "value": row[1],
                "unit": row[2],
                "sensor_id": row[3]
            }
            for row in results
        ]
        
        return {"sensor_id": "temp-001", "readings": readings}
    except Exception as e:
        print(f"Error obteniendo temperatura: {e}")
        return {"error": str(e), "data": []}

@app.get("/sensors/humidity")
async def get_humidity(hours: int = 24):
    """Obtener datos de humedad de las últimas N horas"""
    try:
        conn = get_db_connection()
        if not conn:
            return {"error": "No se pudo conectar a la base de datos", "data": []}
        
        cursor = conn.cursor()
        query = """
            SELECT timestamp, value, unit, sensor_id 
            FROM humidity_readings 
            WHERE timestamp > NOW() - INTERVAL '%s hours'
            ORDER BY timestamp DESC
            LIMIT 100
        """
        cursor.execute(query, (hours,))
        results = cursor.fetchall()
        cursor.close()
        conn.close()
        
        readings = [
            {
                "timestamp": str(row[0]),
                "value": row[1],
                "unit": row[2],
                "sensor_id": row[3]
            }
            for row in results
        ]
        
        return {"sensor_id": "humidity-001", "readings": readings}
    except Exception as e:
        print(f"Error obteniendo humedad: {e}")
        return {"error": str(e), "data": []}

@app.get("/sensors/pressure")
async def get_pressure(hours: int = 24):
    """Obtener datos de presión de las últimas N horas"""
    try:
        conn = get_db_connection()
        if not conn:
            return {"error": "No se pudo conectar a la base de datos", "data": []}
        
        cursor = conn.cursor()
        query = """
            SELECT timestamp, value, unit, sensor_id 
            FROM pressure_readings 
            WHERE timestamp > NOW() - INTERVAL '%s hours'
            ORDER BY timestamp DESC
            LIMIT 100
        """
        cursor.execute(query, (hours,))
        results = cursor.fetchall()
        cursor.close()
        conn.close()
        
        readings = [
            {
                "timestamp": str(row[0]),
                "value": row[1],
                "unit": row[2],
                "sensor_id": row[3]
            }
            for row in results
        ]
        
        return {"sensor_id": "pressure-001", "readings": readings}
    except Exception as e:
        print(f"Error obteniendo presión: {e}")
        return {"error": str(e), "data": []}

@app.get("/sensors/current")
async def get_current_reading():
    """Obtener lecturas actuales"""
    try:
        conn = get_db_connection()
        if not conn:
            return {"error": "No se pudo conectar a la base de datos"}
        
        cursor = conn.cursor()
        
        # Última temperatura
        cursor.execute("""
            SELECT value, timestamp FROM temperature_readings 
            ORDER BY timestamp DESC LIMIT 1
        """)
        temp_row = cursor.fetchone()
        
        # Última humedad
        cursor.execute("""
            SELECT value, timestamp FROM humidity_readings 
            ORDER BY timestamp DESC LIMIT 1
        """)
        humidity_row = cursor.fetchone()
        
        # Última presión
        cursor.execute("""
            SELECT value, timestamp FROM pressure_readings 
            ORDER BY timestamp DESC LIMIT 1
        """)
        pressure_row = cursor.fetchone()
        
        cursor.close()
        conn.close()
        
        return {
            "temperature": {"value": temp_row[0], "timestamp": str(temp_row[1])} if temp_row else None,
            "humidity": {"value": humidity_row[0], "timestamp": str(humidity_row[1])} if humidity_row else None,
            "pressure": {"value": pressure_row[0], "timestamp": str(pressure_row[1])} if pressure_row else None
        }
    except Exception as e:
        print(f"Error obteniendo lecturas actuales: {e}")
        return {"error": str(e)}

@app.get("/sensors/history")
async def get_history(sensor_type: str = "temperature", limit: int = 100):
    """Obtener historial de sensores"""
    try:
        conn = get_db_connection()
        if not conn:
            return {"error": "No se pudo conectar a la base de datos"}
        
        cursor = conn.cursor()
        table_name = f"{sensor_type}_readings"
        
        query = f"""
            SELECT timestamp, value, unit, sensor_id 
            FROM {table_name} 
            ORDER BY timestamp DESC 
            LIMIT {limit}
        """
        cursor.execute(query)
        results = cursor.fetchall()
        cursor.close()
        conn.close()
        
        readings = [
            {
                "timestamp": str(row[0]),
                "value": row[1],
                "unit": row[2],
                "sensor_id": row[3]
            }
            for row in results
        ]
        
        return {"sensor_type": sensor_type, "readings": readings}
    except Exception as e:
        print(f"Error obteniendo historial: {e}")
        return {"error": str(e)}

@app.post("/sensors/reading")
async def post_reading(data: SensorReading):
    """Guardar una lectura de sensor"""
    try:
        conn = get_db_connection()
        if not conn:
            raise HTTPException(status_code=500, detail="No se pudo conectar a la base de datos")
        
        cursor = conn.cursor()
        
        # Determinar tabla según sensor_id
        if "temp" in data.sensor_id.lower():
            table_name = "temperature_readings"
        elif "humidity" in data.sensor_id.lower():
            table_name = "humidity_readings"
        elif "pressure" in data.sensor_id.lower():
            table_name = "pressure_readings"
        else:
            raise HTTPException(status_code=400, detail="sensor_id inválido")
        
        query = f"""
            INSERT INTO {table_name} (timestamp, value, unit, sensor_id)
            VALUES (%s, %s, %s, %s)
        """
        cursor.execute(query, (data.timestamp, data.value, data.unit, data.sensor_id))
        conn.commit()
        cursor.close()
        conn.close()
        
        return {"status": "ok", "message": "Lectura guardada"}
    except Exception as e:
        print(f"Error guardando lectura: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health_check():
    """Health check"""
    return {"status": "healthy", "timestamp": datetime.utcnow().isoformat()}

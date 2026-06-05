# IoT Project Template

Sistema IoT completo que incluye sensores de temperatura y humedad, gateway MQTT, API FastAPI e integración con AWS.

## Arquitectura

```
Sensores (Temp + Humedad) 
    ↓
MQTT Gateway (Mosquitto)
    ↓
AWS IoT Core
    ↓
DynamoDB + PostgreSQL + S3 + Lambda
```

## Estructura del Proyecto

```
├── api/                    # API FastAPI
│   ├── Dockerfile
│   ├── main.py
│   └── requirements.txt
├── gateway/               # Gateway MQTT → AWS
│   ├── Dockerfile
│   ├── publisher.py
│   └── requirements.txt
├── sensors/              # Sensores IoT
│   ├── Dockerfile
│   ├── temp_sensor.py
│   ├── humidity_sensor.py
│   └── requirements.txt
├── lambdas/              # Funciones AWS Lambda
│   ├── process_s3/       # Procesar S3 → PostgreSQL
│   ├── temperature_alert/ # Alertas de temperatura
│   └── cloudwatch_logs/  # Logs a CloudWatch
├── terraform/            # Infraestructura AWS
│   └── provider.tf
├── docker-compose.yml    # Orquestación
├── init-db.sql          # Esquema PostgreSQL
├── Makefile             # Automatización
└── README.md            # Este archivo
```

## Requisitos Previos

- Docker y Docker Compose
- Terraform (para AWS)
- AWS CLI configurado (opcional)
- Python 3.11+ (para desarrollo local)

## Inicio Rápido

### 1. Levantaringreso el proyecto localmente

```bash
# Subir todos los servicios
make up

# Ver logs
docker compose logs -f

# Detener servicios
make down
```

### 2. Verificar servicios

- **API**: http://localhost:8000
- **Adminer (PostgreSQL)**: http://localhost:8080
- **MQTT Broker**: localhost:1883

### 3. Endpoints de la API

```bash
# Obtener todos los sensores
curl http://localhost:8000/sensors

# Obtener datos de temperatura
curl http://localhost:8000/sensors/temperature

# Obtener datos de humedad
curl http://localhost:8000/sensors/humidity

# Obtener lecturas actuales
curl http://localhost:8000/sensors/current

# Health check
curl http://localhost:8000/health
```

## Configuración AWS

### 1. Inicializar Terraform

```bash
make tf-init
```

### 2. Aplicar configuración

```bash
make tf-apply
```

### 3. Recursos creados

- **DynamoDB Table**: `sensor-data-dev`
- **S3 Bucket**: `iot-sensor-archive-dev-<account-id>`
- **SQS Queue**: `iot-sensor-queue-dev`
- **IAM Role**: `iot-lambda-role-dev`
- **CloudWatch Log Group**: `/aws/iot/sensors/dev`

## Servicios

### Sensor de Temperatura
- Genera valores aleatorios entre 15°C y 35°C
- Publica cada 5 segundos en `sensors/temperature`
- Docker: `temp_sensor`

### Sensor de Humedad
- Genera valores aleatorios entre 30% y 80%
- Publica cada 5 segundos en `sensors/humidity`
- Docker: `humidity_sensor`

### Sensor de Presión Atmosférica
- Genera valores aleatorios entre 980pHa y 1040pHa
- Publica cada 5 segundos en `sensors/pressure`
- Docker: `pressure_sensor`

### Gateway MQTT
- Se suscribe a topics de sensores
- Reenvía datos a AWS (DynamoDB, S3, SQS)
- Docker: `gateway`

### API FastAPI
- Expone endpoints REST para consultar datos
- Se conecta a PostgreSQL
- Puerto: 8000
- Docker: `api`

### PostgreSQL
- Almacenamiento histórico de sensores
- Base de datos: `sensors_db`
- Usuario: `postgres`
- Contraseña: `postgres`
- Puerto: 5432

### Mosquitto MQTT
- Broker MQTT local
- Puerto MQTT: 1883
- Puerto WebSocket: 9001

## Desarrollo Local

### Setup del entorno Python

```bash
# Crear virtualenv
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# Instalar dependencias
pip install -r api/requirements.txt
pip install -r sensors/requirements.txt
pip install -r gateway/requirements.txt
```

### Ejecutar servicios localmente

```bash
# Terminal 1: MQTT Broker
docker compose up mosquitto

# Terminal 2: Sensor de temperatura
python sensors/temp_sensor.py

# Terminal 3: Sensor de humedad
python sensors/humidity_sensor.py

# Terminal 4: Gateway
python gateway/publisher.py

# Terminal 5: API
uvicorn api.main:app --reload
```

## Makefile Commands

```bash
make up            # Levantar todos los servicios
make down          # Bajar todos los servicios
make build-lambdas # Empaquetar funciones Lambda en .zip
make tf-init       # Inicializar Terraform
make tf-apply      # Aplicar configuración Terraform (incluye build-lambdas)
make deploy        # Deploy completo (tf-apply + up)
make clean         # Limpiar recursos locales
make destroy       # Destruir todo (AWS + Docker)
```

## AWS Lambda Functions

### 1. Lambda: Process S3 to PostgreSQL
- **Función**: `iot-process-s3-dev`
- **Trigger**: S3 ObjectCreated events
- **Acción**: Lee archivos JSON de S3, procesa datos y guarda en PostgreSQL
- **Runtime**: Python 3.11
- **Timeout**: 60 segundos
- **Dependencias**: boto3, psycopg2

### 2. Lambda: Temperature Alert
- **Función**: `iot-temperature-alert-dev`
- **Trigger**: DynamoDB Stream (cuando se inserta lectura de temperatura)
- **Acción**: Valida umbral de temperatura (default: 30°C) y envía alertas a SQS
- **Runtime**: Python 3.11
- **Timeout**: 30 segundos
- **Variables de entorno**:
  - `TEMP_THRESHOLD`: Umbral de temperatura en °C

### 3. Lambda: CloudWatch Logs
- **Función**: `iot-cloudwatch-logs-dev`
- **Trigger**: SQS Queue (lee mensajes de alertas)
- **Acción**: Procesa mensajes de alerta y escribe en CloudWatch Logs
- **Runtime**: Python 3.11
- **Timeout**: 30 segundos

### Desplegar Lambdas

```bash
# Las Lambdas se empaquetan automáticamente en .zip cuando ejecutas:
make tf-apply

# Si solo necesitas empaquetar sin desplegar:
make build-lambdas

# Los archivos .zip se generarán en:
# - lambdas/process_s3.zip
# - lambdas/temperature_alert.zip
# - lambdas/cloudwatch_logs.zip
```

## Variables de Entorno

### API
- `DB_HOST`: Host PostgreSQL (default: localhost)
- `DB_NAME`: Nombre base de datos (default: sensors_db)
- `DB_USER`: Usuario PostgreSQL (default: postgres)
- `DB_PASSWORD`: Contraseña PostgreSQL (default: postgres)
- `AWS_REGION`: Región AWS (default: us-east-1)

### Gateway
- `AWS_REGION`: Región AWS (default: us-east-1)
- `AWS_IOT_ENDPOINT`: Endpoint AWS IoT

### Terraform
- `aws_region`: Región AWS (default: us-east-1)
- `environment`: Nombre del ambiente (default: dev)

## Troubleshooting

### Los sensores no se conectan a MQTT
```bash
# Verificar que Mosquitto esté corriendo
docker compose logs mosquitto

# Reiniciar todos los servicios
make down
make up
```

### PostgreSQL no se conecta
```bash
# Ver logs de PostgreSQL
docker compose logs postgres

# Reiniciar base de datos
docker compose down
docker volume rm iot-project-template_postgres_data
docker compose up -d postgres
```

### API devuelve errores de base de datos
```bash
# Verificar conexión
curl http://localhost:8000/health

# Ver logs
docker compose logs api
```

## Monitoreo

### Verificar mensajes MQTT
```bash
# Suscribirse a topics
docker compose exec mosquitto mosquitto_sub -t "sensors/#" -h localhost
```

### Ver datos en PostgreSQL
```bash
# Conectarse a la BD
docker compose exec postgres psql -U postgres -d sensors_db

# Ver tablas
\dt

# Consultar datos
SELECT * FROM temperature_readings LIMIT 10;
SELECT * FROM humidity_readings LIMIT 10;
```

## Siguientes Pasos

- [ ] Configurar AWS IoT Core
- [ ] Implementar Lambda functions
- [ ] Configurar alertas CloudWatch
- [ ] Agregar autenticación a la API
- [ ] Implementar persistencia de credenciales MQTT
- [ ] Agregar frontend web
- [ ] Configurar CI/CD

## Licencia

MIT

## Soporte

Para reportar issues o sugerencias, contactar al equipo de desarrollo.

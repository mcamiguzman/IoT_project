# 📋 Guía de comandos útiles para el proyecto

### Asumiendo que:
- Estás en `/app/iot-project-p1` dentro del contenedor
- AWS CLI ya configurado (vimos que `aws s3 ls` funcionó)
- El host AWS es `us-east-1` con cuenta `665031542744` (Learner Lab)

---

## 🚀 FASE 1 — Inicio

### 1.1 Inicializar Terraform y desplegar en AWS 

Ran terminal command: make deploy

```bash
cd /app/iot-project-p1
make deploy
```

**Qué hace** (internamente):
- `cd terraform && terraform init` — descarga providers
- `pip install -r lambdas/process_s3/requirements.txt` — instala psycopg2
- `cd terraform && terraform apply -auto-approve` — crea 12 recursos en AWS
- `docker compose up -d --build` — levanta 7 contenedores

**Salida esperada al final:** `Apply complete! Resources: 12 added, 0 changed, 0 destroyed.`

**Si falla con `ResourceAlreadyExistsException`:**
```bash
cd terraform
# Importar el recurso huerfano (reemplaza el ID por el del mensaje de error)
terraform import aws_cloudwatch_log_group.iot_logs /aws/iot/sensors/dev
terraform import aws_lambda_event_source_mapping.sqs_to_lambda f3ea99a2-463c-4b87-9892-c061a990b991
cd ..
make deploy
```

### 1.2 Verificar que todo arrancó 

Ran terminal command: docker compose ps

```bash
docker compose ps
```

**Salida esperada:** 7 servicios en estado `Up` (algunos con `healthy`):
- `mosquitto` — puerto 1883
- `temp_sensor` y `humidity_sensor`
- gateway
- `postgres` — puerto 5432, healthy
- api — puerto 8000, healthy
- `adminer` — puerto 8080

### 1.3 Crear las tablas en Postgres (solo la primera vez)

El script init-db.sql no se ejecuta si el volumen ya existía: 

Ran terminal command: docker compose exec -T postgres psql -U postgres -d sensors_db < init-db.sql

```bash
docker compose exec -T postgres psql -U postgres -d sensors_db < init-db.sql
```

**Salida esperada:** `CREATE TABLE`, `CREATE INDEX` (repetido varias veces).

---

## 🧪 FASE 2 — Pruebas

### 2.1 Probar el flujo local de sensores

```bash
# 1) Ver JSONs que publica el sensor de temperatura
docker compose logs -f temp_sensor

# 2) Ver JSONs del sensor de humedad
docker compose logs -f humidity_sensor

# 3) Escuchar el broker MQTT directamente (Ctrl+C para salir)
docker compose exec mosquitto mosquitto_sub -h localhost -t "sensors/#" -v -C 5
```

**Salida esperada:** JSONs con `sensor_id`, `value`, `unit` cada pocos segundos.

### 2.2 Probar el gateway

```bash
docker compose logs -f gateway
```

**Salida esperada:** líneas tipo `Mensaje recibido de sensors/temperature: {...}` y `Procesando temperatura: 23.5°C`.

### 2.3 Probar la API

**Desde Windows (PowerShell fuera del contenedor):**
```powershell
curl http://localhost:8000/
curl http://localhost:8000/sensors
curl http://localhost:8000/sensors/temperature
curl http://localhost:8000/sensors/history
```

**O desde el navegador:** [http://localhost:8000/docs](http://localhost:8000/docs) (Swagger UI).

### 2.4 Probar la base de datos

```bash
# Ver tablas creadas
docker compose exec postgres psql -U postgres -d sensors_db -c "\dt"

# Contar registros
docker compose exec postgres psql -U postgres -d sensors_db -c "SELECT COUNT(*) FROM temperature_readings;"
docker compose exec postgres psql -U postgres -d sensors_db -c "SELECT COUNT(*) FROM humidity_readings;"

# Ver últimos 5 registros
docker compose exec postgres psql -U postgres -d sensors_db -c "SELECT * FROM temperature_readings ORDER BY timestamp DESC LIMIT 5;"
```

**O vía UI web:** [http://localhost:8080](http://localhost:8080) (Adminer). Login: servidor=`postgres`, usuario=`postgres`, password=`postgres`, db=`sensors_db`.

### 2.5 Probar la integración con AWS

```bash
# Ver outputs de Terraform (URLs, ARNs)
cd /app/iot-project-p1/terraform && terraform output

# Logs de la lambda cloudwatch_logs
aws logs tail /aws/iot/sensors/dev --follow

# Mensajes en SQS
aws sqs get-queue-attributes \
  --queue-url https://sqs.us-east-1.amazonaws.com/665031542744/iot-sensor-queue-dev \
  --attribute-names ApproximateNumberOfMessages

# Objetos en S3
aws s3 ls s3://iot-sensor-archive-dev-665031542744/ --recursive

# Items en DynamoDB
aws dynamodb scan --table-name sensor-data-dev --max-items 5
```

### 2.6 Disparar la lambda `process_s3` (S3 → Postgres)

```bash
# 1) Subir un JSON al bucket
echo '{"sensor_id":"manual-001","value":22.5,"unit":"celsius","timestamp":"2026-06-04T00:00:00Z"}' > /tmp/test.json
aws s3 cp /tmp/test.json s3://iot-sensor-archive-dev-665031542744/manual/test.json

# 2) Esperar 10-15s y ver logs de la lambda
aws logs tail /aws/lambda/iot-process-s3-dev --since 2m

# 3) Verificar que llegó a Postgres
docker compose exec postgres psql -U postgres -d sensors_db -c "SELECT * FROM sensor_readings WHERE sensor_id='manual-001';"
```

> ⚠️ La lambda usa `DB_HOST=postgres`, que solo resuelve dentro de Docker Compose. Para que funcione contra un Postgres real en AWS, usa RDS y cambia esa variable en lambda.tf.

### 2.7 Disparar la alerta de temperatura 

```bash
apt-get install -y python3-boto3 2>/dev/null ; pip install boto3 --quiet; python3 -c "
import boto3, time
ddb = boto3.resource('dynamodb', region_name='us-east-1')
table = ddb.Table('sensor-data-dev')
table.put_item(Item={'sensor_id': 'temp-001', 'timestamp': int(time.time()), 'value': 45.0, 'unit': 'celsius', 'expiration': int(time.time())+86400})
print('Inserted high-temp reading')
"
```

```bash
# Insertar lectura con temperatura alta (45°C) en DynamoDB
docker compose exec gateway python3 -c "
import boto3, time
ddb = boto3.resource('dynamodb', region_name='us-east-1')
table = ddb.Table('sensor-data-dev')
table.put_item(Item={
    'sensor_id': 'temp-001',
    'timestamp': int(time.time()),
    'value': 45.0,
    'unit': 'celsius',
    'expiration': int(time.time()) + 86400
})
print('Inserted high-temp reading')
"

# Esperar 5s y ver logs
sleep 5
aws logs tail /aws/lambda/iot-temperature-alert-dev --since 2m
```

**Salida esperada:** log mostrando que el threshold de 30°C se superó.

### 2.8 Verificación de salud (resumen)

| Componente | Comando | Estado esperado |
|---|---|---|
| Contenedores | `docker compose ps` | 7 servicios `Up` |
| Sensores | `docker compose logs temp_sensor` | Publicando JSONs |
| Broker MQTT | `mosquitto_sub -t "sensors/#"` | Recibe mensajes |
| Gateway | `docker compose logs gateway` | Procesando mensajes |
| API | `curl http://localhost:8000/` (desde Windows) | JSON con endpoints |
| Postgres | `SELECT COUNT(*) FROM temperature_readings` | ≥ 0 |
| S3 bucket | `aws s3 ls s3://iot-sensor-archive-dev-...` | Objetos listados |
| DynamoDB | `aws dynamodb scan --table-name sensor-data-dev` | Items |
| CloudWatch | `aws logs tail /aws/iot/sensors/dev` | Logs activos |
| Terraform | `cd terraform && terraform output` | Todas las salidas con valor |

---

## 🧹 FASE 3 — Limpieza y borrado total

### 3.1 Detener todo y borrar AWS

**Opción A — Todo de un golpe (recomendado):**
```bash
cd /app/iot-project-p1
make destroy
```

Internamente:
1. `make down` → `docker compose down`
2. `make tf-destroy` → `terraform destroy -auto-approve` (12 recursos)
3. `make clean` → `docker compose down -v` + elimina imágenes + borra `terraform.tfstate*`, `.terraform/`, `.zip`, `__pycache__`

**Opción B — Por pasos (más control):**
```bash
cd /app/iot-project-p1
make down            # Solo detiene contenedores
make tf-destroy      # Solo destruye AWS
make clean           # Solo limpia local
```

### 3.2 Si `terraform destroy` falla a mitad

```bash
cd /app/iot-project-p1/terraform

# Ver qué quedó en estado
terraform state list

# Reintentar (continúa desde donde falló)
terraform destroy -auto-approve

# Si un recurso no se puede borrar, sacarlo del estado
terraform state rm <nombre_recurso>

# Borrar manualmente desde la consola AWS (caso extremo)
```

**Errores comunes en Learner Lab y solución:**

| Error AWS | Solución |
|---|---|
| `BucketNotEmpty` en S3 | `aws s3 rm s3://iot-sensor-archive-dev-665031542744/ --recursive` y reintenta |
| `AccessDenied` en log group | Espera 2-3 min (propagación IAM) y reintenta |
| `DependencyViolation` en SQS | Espera 30s y reintenta |

### 3.3 Verificar que AWS quedó limpio 

Ran terminal command: echo "=== Recursos del proyecto en AWS ===" ; aws s3 ls | grep iot-sensor ; echo "✓ Sin buckets S3" ; aws dynamodb list-tables | grep sensor-data ; echo "✓ Sin tablas DynamoDB" ; aws sqs list-queues | grep iot-sensor ; echo "✓ Sin colas SQS" ; aws lambda list-functions | grep iot- ; echo "✓ Sin lambdas" ; aws logs describe-log-groups | grep iot ; echo "✓ Sin log groups"

```bash
cd /app/iot-project-p1
echo "=== Recursos del proyecto en AWS ==="
aws s3 ls | grep iot-sensor || echo "✓ Sin buckets S3"
aws dynamodb list-tables | grep sensor-data || echo "✓ Sin tablas DynamoDB"
aws sqs list-queues | grep iot-sensor || echo "✓ Sin colas SQS"
aws lambda list-functions | grep iot- || echo "✓ Sin lambdas"
aws logs describe-log-groups | grep iot || echo "✓ Sin log groups"
```

**Salida esperada:** todas las líneas con ✓ (limpio).

### 3.4 Verificar que Docker quedó limpio 

Ran terminal command: docker compose ps -a ; echo "---" ; docker images | grep iot-project ; echo "✓ Sin imágenes del proyecto" ; echo "---" ; docker volume ls | grep iot-project ; echo "✓ Sin volúmenes del proyecto"

```bash
cd /app/iot-project-p1
docker compose ps -a                     # No debe haber contenedores
docker images | grep iot-project         # No debe haber imágenes
docker volume ls | grep iot-project     # No debe haber volúmenes
```

**Salida esperada:** todos con `✓ Sin ...`.

---

## 🔄 FASE 4 — Próximo arranque

Después de un `make destroy` exitoso, para volver a empezar:

```bash
cd /app/iot-project-p1
make deploy
```

Luego repite el **Paso 1.3** (crear tablas en Postgres, solo la primera vez). El resto del flujo es idéntico a la Fase 2.

---

## 🆘 Comandos de emergencia

| Situación | Comando |
|---|---|
| Contenedor se cayó | `docker compose restart <servicio>` o `docker compose up -d` |
| Ver logs de un servicio | `docker compose logs -f <servicio>` |
| Entrar a un contenedor | `docker compose exec <servicio> bash` |
| Reconstruir imágenes | `docker compose build --no-cache` |
| Limpiar solo Docker (no AWS) | `make clean` |
| Re-aplicar cambios en Terraform | `cd terraform && terraform apply` |
| Ver qué pasa en AWS ahora | `cd terraform && terraform plan` |
| Salir del contenedor | `exit` |

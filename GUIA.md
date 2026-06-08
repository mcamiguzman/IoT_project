# 📋 Guía Completa: IoT Core Gateway + AWS Learner Lab

Esta guía te ayudará a desplegar el proyecto IoT desde cero hasta tener datos fluyendo de sensores locales → AWS IoT Core → DynamoDB/S3/CloudWatch.

---

## 🎯 Requisitos Previos

- **AWS Learner Lab**: Sesión activa con credenciales vigentes
- **Docker Desktop**: Instalado y en ejecución
- **AWS CLI v2**: Instalado (`aws --version`)
- **OpenSSL**: Disponible (`openssl version`)
- **Terraform**: Instalado (`terraform -v`)
- **Git**: Para clonar el repositorio
- **PowerShell o Bash**: Para ejecutar scripts

### Verificar Requisitos

```bash
aws --version
terraform -v
openssl version
docker --version
```

---

## 🔑 PASO 1: Exportar Credenciales AWS Learner Lab

**⚠️ CRÍTICO**: Sin esto, el gateway no puede conectarse a AWS IoT Core.

### En PowerShell (Windows):

```powershell
# Ir a AWS Learner Lab y copiar "AWS CLI"
# Debería verse algo como:
# export AWS_ACCESS_KEY_ID="ASIA..."
# export AWS_SECRET_ACCESS_KEY="..."
# export AWS_SESSION_TOKEN="..."

# En PowerShell, convertir a:
$env:AWS_ACCESS_KEY_ID="ASIA..."
$env:AWS_SECRET_ACCESS_KEY="..."
$env:AWS_SESSION_TOKEN="..."

# Verificar que funcionó:
aws sts get-caller-identity
# Debería mostrar tu Account ID, ARN, etc.
```

### En Bash (Linux/Mac):

```bash
# Copiar directamente del Learner Lab
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."

# Verificar
aws sts get-caller-identity
```

**Notas importantes:**
- El token expira típicamente en **4 horas**
- Si el gateway dice "No se pudo descubrir AWS_IOT_ENDPOINT", las credenciales probablemente expiraron
- Re-exporta credenciales si ves errores de `UnauthorizedOperation`

---

## 🔐 PASO 2: Provisionar Certificados X.509 para IoT

Los certificados son **obligatorios** para autenticar el gateway con AWS IoT Core (mutual-TLS).

### Ejecutar Script de Provisioning

**En PowerShell (Windows):**

```powershell
.\scripts\provision-iot-certificates.ps1 -ThingName "sensor-thing-dev" -Region "us-east-1"
```

**En Bash (Linux/Mac):**

```bash
bash scripts/provision-iot-certificates.sh -t "sensor-thing-dev" -r "us-east-1"
```

**Opciones disponibles:**
- `-t THING_NAME`: Nombre del Thing en IoT Core (default: sensor-thing-dev)
- `-r REGION`: Región AWS (default: us-east-1)
- `-d CERTS_DIR`: Directorio para certificados (default: ./certs)

**Ejemplo alternativo (valores por defecto):**
```bash
# PowerShell
.\scripts\provision-iot-certificates.ps1

# Bash
bash scripts/provision-iot-certificates.sh
```

**Qué hace el script:**
1. ✓ Genera clave privada RSA 2048-bit localmente
2. ✓ Crea Certificate Signing Request (CSR)
3. ✓ Registra CSR en AWS IoT Core
4. ✓ Descarga certificado de AWS
5. ✓ Descarga Amazon Root CA
6. ✓ Guarda todo en carpeta `./certs`

**Salida esperada:**
```
► Inicializando provisioning de certificados para AWS IoT Core...
► Generando clave privada y Certificate Signing Request (CSR)...
✓ Clave privada generada: ./certs/iot-device-key.pem
✓ CSR generado: ./certs/iot-device.csr
► Registrando CSR en AWS IoT Core...
✓ Certificado creado en AWS IoT Core
  ARN: arn:aws:iot:us-east-1:ACCOUNT_ID:cert/...
✓ Certificado descargado
✓ Amazon Root CA descargado
✓ Provisioning completado exitosamente
```

**Si falla:**
- ¿Credenciales AWS exportadas? Revisa PASO 1
- ¿Token expirado? Re-exporta desde Learner Lab
- ¿Permisos? Learner Lab debería permitir iot:CreateCertificate

---

## 🌐 PASO 3: Desplegar Infraestructura en AWS (Terraform)

### 3.1 Inicializar Terraform

```bash
cd terraform
terraform init
```

**Salida esperada:** "Terraform has been successfully configured!"

### 3.2 Aplicar Configuración (Crear Recursos AWS)

```bash
# Desde la raíz del proyecto
make tf-apply
```

**O manualmente:**

```bash
cd terraform
terraform apply -auto-approve
cd ..
```

**Recursos que se crean (15+ total):**
- ✓ AWS IoT Thing
- ✓ AWS IoT Policy
- ✓ 3 Topic Rules (SQS, DynamoDB, S3)
- ✓ DynamoDB Table (sensor-data-dev)
- ✓ S3 Bucket (sensor archive)
- ✓ SQS Queue
- ✓ RDS PostgreSQL (db.r5.large)
- ✓ 3 Lambda Functions (process_s3, temperature_alert, cloudwatch_logs)
- ✓ CloudWatch Log Group
- ✓ Security Groups, Subnets, IAM Roles

**Salida esperada:**
```
Apply complete! Resources: XX added, 0 changed, 0 destroyed.
```

### 3.3 Obtener Outputs Importantes

```bash
cd terraform
terraform output
```

**Outputs clave:**
- `iot_endpoint_command`: Comando para obtener el endpoint de IoT
- `rds_endpoint`: Host:Puerto de PostgreSQL
- `sqs_queue_url`: URL de la cola SQS
- `cloudwatch_log_group`: Nombre del grupo de logs

### 3.4 Obtener IoT Endpoint

```bash
aws iot describe-endpoint --endpoint-type iot:Data-ATS --query endpointAddress --output text
# Debería mostrar algo como: abc123xyz-ats.iot.us-east-1.amazonaws.com
```

**Guarda este endpoint**, lo necesitarás para debugging.

---

## 🐳 PASO 4: Levantar Docker Compose

### 4.1 Build y Up

```bash
docker compose up -d --build
```

**Servicios que se levantan:**
- ✓ Mosquitto (MQTT Broker local, puerto 1883)
- ✓ Sensor de Temperatura (publica cada 5s)
- ✓ Sensor de Humedad (publica cada 5s)
- ✓ Sensor de Presión (publica cada 5s)
- ✓ Gateway (reenvía de Mosquitto → AWS IoT)
- ✓ PostgreSQL (puerto 5432, para desarrollo local)

### 4.2 Verificar que Levantaron

```bash
docker compose ps
```

**Salida esperada:** 6 servicios en estado `Up`

---

## 🧪 PASO 5: Verificar el Flujo de Datos

### 5.1 Ver Logs del Gateway

```bash
docker compose logs -f gateway
```

**Buscas estas líneas (señal de éxito):**
```
✓ Conectado a MQTT local (mosquitto:1883)
  ├─ Suscrito a: sensors/temperature
  ├─ Suscrito a: sensors/humidity
  ├─ Suscrito a: sensors/pressure
✓ Conectado a AWS IoT Core (abc123xyz-ats.iot.us-east-1.amazonaws.com:8883)
  Certificados X.509 validados correctamente

[1] Mensaje recibido en 2024-06-07T10:30:45.123456
  Topic local: sensors/temperature
  Payload: {...}
  ✓ Reenviado a AWS IoT Core: sensors/temperature
```

**Si ves errores:**
- `ERROR: No se pudo descubrir AWS_IOT_ENDPOINT`: Credenciales no exportadas → PASO 1
- `ERROR: Certificados X.509 no encontrados`: Script provisioning fallo → PASO 2
- `Error publicando en AWS IoT`: Certificados inválidos o Topic Rule fallo → PASO 2 o 3

### 5.2 Ver Logs de Sensores

```bash
docker compose logs -f temp_sensor
docker compose logs -f humidity_sensor
docker compose logs -f pressure_sensor
```

**Salida esperada:** "Publicado: XX.XX°C" cada 5 segundos

### 5.3 Escuchar Mosquitto Local

```bash
docker compose exec mosquitto mosquitto_sub -h localhost -t "sensors/#" -v -C 5
```

**Salida esperada:** 5 mensajes JSON de sensores

---

## 📊 PASO 6: Verificar DynamoDB (Hot Data)

```bash
aws dynamodb scan \
  --table-name sensor-data-dev \
  --region us-east-1 \
  --limit 10
```

**Salida esperada:** Items con:
```json
{
  "sensor_id": { "S": "temp-001" },
  "timestamp": { "N": "1717760445123" },
  "value": { "N": "23.45" },
  "unit": { "S": "celsius" }
}
```

**Si está vacío:**
- ¿El gateway está conectado a AWS? Revisa logs del gateway (PASO 5.1)
- ¿DynamoDB Topic Rule existe? Revisa `terraform output | grep iot_topic_rule_dynamodb`

---

## 📦 PASO 7: Verificar S3 (Cold Data)

```bash
aws s3 ls s3://iot-sensor-archive-dev-${ACCOUNT_ID}/sensors/ --recursive
```

**Salida esperada:** Archivos con patrón:
```
sensors/2024/06/07/1030-gateway-iot-publisher.json
sensors/2024/06/07/1031-gateway-iot-publisher.json
```

**Si está vacío:**
- Espera 30 segundos (Topic Rule tiene latencia)
- Revisa que `iot_topic_rule_s3` existe en outputs

---

## 📝 PASO 8: Ver CloudWatch Logs

### 8.1 Seguir logs en tiempo real

```bash
make aws-logs LOG_GROUP=/aws/iot/sensors/dev
```

**Salida esperada:** Mensajes de IoT Core (CloudWatch Logs via Topic Rule)

### 8.2 Ver logs sin seguir (sin quedar trabado)

```bash
make aws-logs LOG_GROUP=/aws/iot/sensors/dev FOLLOW=no LIMIT=50
```

**Opciones disponibles:**
- `FOLLOW=no`: No sigue nuevos eventos, solo muestra últimos
- `LIMIT=50`: Limita a 50 líneas (default: 100)
- `SINCE=5m`: Muestra logs de últimos 5 minutos
- `PROFILE=lab`: Usa perfil AWS específico (si no es default)

---

## 🔥 Troubleshooting

### Gateway no se conecta a AWS IoT

**Síntoma:** 
```
ERROR: No se pudo descubrir AWS_IOT_ENDPOINT
```

**Soluciones:**
1. ✓ Exportar credenciales (PASO 1)
2. ✓ Verificar token no expirado: `aws sts get-caller-identity`
3. ✓ Verificar certificates: `ls ./certs`
4. ✓ Revisar logs: `docker compose logs gateway`

### DynamoDB o S3 vacío

**Síntoma:** Los datos del gateway no llegan a AWS

**Soluciones:**
1. ✓ ¿Gateway conectado? `docker compose logs gateway | grep "Conectado a AWS"`
2. ✓ ¿Mensajes siendo reenviados? `docker compose logs gateway | grep "Reenviado"`
3. ✓ ¿Topic Rules creadas? `terraform output | grep iot_topic_rule`
4. ✓ ¿DynamoDB table existe? `aws dynamodb describe-table --table-name sensor-data-dev`

### aws-logs se queda trabado

**Síntoma:**
```
siguiendo CloudWatch Logs...
(ninguna salida)
```

**Solución:**
```bash
# Usa FOLLOW=no
make aws-logs LOG_GROUP=/aws/iot/sensors/dev FOLLOW=no
```

### RDS PostgreSQL no accesible desde Lambda

**Síntoma:** Lambda falla con error de conexión a base de datos

**Soluciones:**
1. ✓ RDS disponible: `aws rds describe-db-instances --query 'DBInstances[0].DBInstanceStatus'`
2. ✓ Endpoint correcto: `terraform output rds_endpoint`
3. ✓ Security group permite acceso desde Lambdas

---

## 📋 Referencia de Comandos Útiles

```bash
# Ver recursos creados
make tf-apply

# Destruir todo (CUIDADO)
make tf-destroy

# Ver logs locales
docker compose logs -f

# Ver logs de componente específico
docker compose logs -f gateway
docker compose logs -f temp_sensor

# Listar recursos AWS
aws iot list-things
aws dynamodb list-tables
aws s3 ls
aws rds describe-db-instances

# Ver Topic Rules
aws iot list-topic-rules

# Verificar Lambda Functions
aws lambda list-functions --query 'Functions[?contains(FunctionName, `iot`)].FunctionName'

# Limpiar volúmenes Docker
docker compose down -v

# Re-exportar credenciales si expiraron
# (desde AWS Learner Lab: copiar nuevo comando export)
```

---

## 🎓 Arquitectura del Proyecto

```
[Sensores Locales] 
       ↓ MQTT
[Mosquitto Edge Gateway]
       ↓ MQTT + TLS (Certificados X.509)
[AWS IoT Core]
   ↓ ↓ ↓ (Topic Rules)
   │ ├→ [DynamoDB] ← Hot Data
   │ ├→ [S3] ← Cold Data
   │ └→ [SQS] ← Alerts
   ↓
[Lambda process_s3]
   ↓ SQL
[RDS PostgreSQL] ← Historical Data

[SQS Queue]
   ↓ Trigger
[Lambda cloudwatch_logs]
   ↓ Log
[CloudWatch Logs]
```

---

## 📞 Soporte

**Si algo falla:**
1. Revisa los logs: `docker compose logs`
2. Revisa logs de AWS: `make aws-logs LOG_GROUP=/aws/iot/sensors/dev FOLLOW=no`
3. Verifica credenciales: `aws sts get-caller-identity`
4. Consulta "Troubleshooting" arriba

---

**Última actualización**: Junio 2024
**Versión**: 2.0 (con certificados X.509 y RDS)

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

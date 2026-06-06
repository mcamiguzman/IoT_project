Read [](file:///c%3A/0_dev_environment/iot-project-p1/terraform/iam.tf)

Read [](file:///c%3A/0_dev_environment/iot-project-p1/terraform/LEARNER_LAB.md)

# 📘 Tutorial Detallado de los Archivos Terraform

Terraform es la herramienta de **infraestructura como código (IaC)** que crea y configura todos los recursos AWS. Te explico bloque por bloque.

---

## 📄 provider.tf

Define **con qué proveedor de nube** se trabaja y la configuración por defecto.

````hcl
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"   # Compatible con 5.x
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "IoT-Project"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
````

### 🔹 Bloque `terraform {}`
- `required_version = ">= 1.0"` — Obliga a usar Terraform 1.0 o superior
- `required_providers` — Declara de dónde descargar el plugin de AWS (`hashicorp/aws` desde el registry oficial), restringido a la versión 5.x

### 🔹 Bloque `provider "aws" {}`
- `region = var.aws_region` — Región AWS (leída de variables.tf, default `us-east-1`)
- `default_tags` — Etiquetas que **se aplican automáticamente a TODOS los recursos** que no especifiquen las suyas. Aquí se etiqueta el proyecto, entorno y que está gestionado por Terraform (útil para facturación y filtrado en la consola AWS)

---

## 📄 variables.tf

Define las **variables de entrada** que el usuario puede personalizar al aplicar Terraform.

````hcl
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "lambda_role_arn" {
  description = "ARN del rol IAM existente para Lambda (requerido en AWS Learner Lab)"
  type        = string
  default     = ""  # Dejar vacío si usas el rol por defecto de tu cuenta
}
````

### 🔹 `aws_region`
- Región donde se crearán los recursos
- Default: `us-east-1` (Virginia del Norte, la más barata y con más servicios)

### 🔹 `environment`
- Sufijo usado en todos los nombres de recursos (`sensor-data-dev`, `iot-sensor-queue-dev`, etc.)
- Permite desplegar varios entornos (dev, staging, prod) sin colisiones

### 🔹 `lambda_role_arn`
- ARN de un rol IAM pre-existente
- Necesario en **AWS Learner Lab** porque ahí no se pueden crear roles
- Si dejas vacío (`""`), se usará el `LabRole` pre-existente (ver iam.tf)

---

## 📄 data.tf

Los **data sources** son consultas de solo lectura a datos que ya existen en AWS (no crean nada).

````hcl
data "aws_caller_identity" "current" {}
````

### 🔹 `aws_caller_identity`
- Obtiene **metadatos de la cuenta AWS** con la que estás autenticado
- El más usado: `data.aws_caller_identity.current.account_id` (el ID de 12 dígitos)
- Se usa en s3.tf para hacer el nombre del bucket único: `iot-sensor-archive-{env}-{account_id}`

---

## 📄 dynamodb.tf

Crea la **tabla DynamoDB** que almacena los datos "calientes" (consultas rápidas) de los sensores.

````hcl
resource "aws_dynamodb_table" "sensor_data" {
  name         = "sensor-data-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "sensor_id"
  range_key    = "timestamp"
  ...
}
````

### 🔹 `name`
- Nombre de la tabla: `sensor-data-dev` (concatenando la variable)

### 🔹 `billing_mode = "PAY_PER_REQUEST"`
- **Pago por uso** (no se provisiona capacidad)
- Ideal para cargas variables o de baja frecuencia
- Alternativa: `PROVISIONED` (con `read_capacity` y `write_capacity` definidos)

### 🔹 `hash_key` y `range_key` — Clave primaria compuesta
- **Hash key** (clave de partición): `sensor_id` — determina en qué partición física se guarda el item
- **Range key** (clave de ordenamiento): `timestamp` — permite ordenar y consultar rangos dentro de la misma partición
- Esto permite consultas eficientes como "dame todas las lecturas del sensor X entre las 10:00 y las 11:00"

### 🔹 Streams
````hcl
stream_enabled   = true
stream_view_type = "NEW_AND_OLD_IMAGES"
````
- Habilita DynamoDB Streams: cada vez que se inserta/modifica un item, se genera un evento
- `NEW_AND_OLD_IMAGES` — El stream contiene tanto la imagen nueva como la anterior del item
- Usado por la Lambda `temperature_alert` para reaccionar a nuevas lecturas

### 🔹 Atributos (definidos explícitamente)
- `sensor_id` (S = String) y `timestamp` (N = Number) — Requeridos porque son parte de la clave primaria

### 🔹 TTL (Time To Live)
````hcl
ttl {
  attribute_name = "expiration"
  enabled        = true
}
````
- DynamoDB borrará automáticamente los items cuando el atributo `expiration` indique una fecha Unix pasada
- Ahorra costos borrando datos viejos automáticamente

---

## 📄 s3.tf

Crea el **bucket S3** para archivo histórico de sensores (data lake barato).

````hcl
resource "aws_s3_bucket" "sensor_archive" {
  bucket = "iot-sensor-archive-${var.environment}-${data.aws_caller_identity.current.account_id}"
  ...
}
````

### 🔹 Nombre del bucket
- `iot-sensor-archive-dev-123456789012`
- Se concatena con el `account_id` para garantizar **unicidad global** (los nombres de bucket S3 son únicos en todo el mundo)

### 🔹 Versionado
````hcl
resource "aws_s3_bucket_versioning" "sensor_archive" {
  bucket = aws_s3_bucket.sensor_archive.id
  versioning_configuration {
    status = "Enabled"
  }
}
````
- Activa el versionado: si subes un archivo con el mismo nombre, se conserva el anterior
- Útil para auditoría y recuperación ante errores

### 🔹 Lifecycle Configuration
````hcl
rule {
  transition {
    days          = 90
    storage_class = "GLACIER"
  }
  expiration {
    days = 365
  }
}
````
- **Día 90**: Los archivos se mueven automáticamente a **Glacier** (almacenamiento ultra-barato, ~$0.004/GB/mes, pero más lento de recuperar)
- **Día 365**: Se eliminan definitivamente
- Reduce costos en archivos que ya no se consultan frecuentemente

---

## 📄 `terraform/sqs.tf`

Crea la **cola SQS** que recibe los mensajes de alerta de temperatura.

````hcl
resource "aws_sqs_queue" "sensor_queue" {
  name                      = "iot-sensor-queue-${var.environment}"
  delay_seconds             = 0
  max_message_size          = 262144
  message_retention_seconds = 345600
  receive_wait_time_seconds = 0
  ...
}
````

### 🔹 `name`
- `iot-sensor-queue-dev`

### 🔹 `delay_seconds = 0`
- Los mensajes se entregan inmediatamente al consumidor (sin demora)

### 🔹 `max_message_size = 262144`
- Tamaño máximo por mensaje: 256 KB

### 🔹 `message_retention_seconds = 345600`
- Los mensajes no consumidos se eliminan tras **4 días** (345600 / 86400 = 4)

### 🔹 `receive_wait_time_seconds = 0`
- **Short polling**: las respuestas de `ReceiveMessage` vuelven inmediatamente (puede devolver vacío)
- Para long polling (más eficiente y barato) sería `1-20` segundos

---

## 📄 `terraform/cloudwatch.tf`

Crea el **log group** de CloudWatch para centralizar los logs.

````hcl
resource "aws_cloudwatch_log_group" "iot_logs" {
  name              = "/aws/iot/sensors/${var.environment}"
  retention_in_days = 14
  ...
}
````

### 🔹 `name`
- `/aws/iot/sensors/dev` — Convención jerárquica de AWS (similar a Linux)

### 🔹 `retention_in_days = 14`
- CloudWatch **borra automáticamente los logs** tras 14 días
- Configurable: 1, 3, 5, 7, 14, 30, 60, 90, etc.
- Reduce costos en cuentas de desarrollo

---

## 📄 iam.tf

Gestión de **roles y políticas IAM** (Identity and Access Management).

````hcl
data "aws_iam_role" "lab_role" {
  name = "LabRole"
}
````

### 🔹 `data "aws_iam_role"`
- **Solo consulta** el rol `LabRole` que ya existe en la cuenta
- Se usa en lambda.tf para asignar este rol a las Lambdas (en lugar de crear uno nuevo)

> ⚠️ El resto del archivo está **comentado** (precedido por `#`) porque en AWS Learner Lab no se permite crear roles IAM. En una cuenta AWS real, descomentarías:

````hcl
resource "aws_iam_role" "lambda_role" {
  name = "iot-lambda-role-${var.environment}"
  assume_role_policy = jsonencode({...})
}
````

- Crea un rol IAM llamado `iot-lambda-role-dev`
- `assume_role_policy` — Define **quién puede asumir este rol** (en este caso, el servicio `lambda.amazonaws.com`)
- `jsonencode` — Convierte el objeto HCL a JSON, que es el formato que requiere AWS

### 🔹 La policy comentada
Si se descomentara, otorgaría a las Lambdas permisos para:

| Permiso | Servicio | Acciones |
|---------|----------|----------|
| DynamoDB | Tabla + streams | `PutItem`, `GetItem`, `Query`, `GetRecords` (stream), etc. |
| S3 | Bucket + objetos | `PutObject`, `GetObject`, `ListBucket` |
| CloudWatch Logs | `*:*:*:*` (todos) | `CreateLogGroup`, `CreateLogStream`, `PutLogEvents` |
| SQS | Cola específica | `SendMessage`, `ReceiveMessage`, `DeleteMessage` |

Principio de **mínimo privilegio**: cada acción tiene un `Resource` específico (no `*` excepto para CloudWatch, donde es necesario).

---

## 📄 lambda.tf

**El archivo más importante.** Define las 3 funciones Lambda, sus triggers, permisos y el empaquetado.

### 🔹 Local values
````hcl
locals {
  lambda_role_arn = var.lambda_role_arn != "" ? var.lambda_role_arn : data.aws_iam_role.lab_role.arn
}
````
- **Variable local** reutilizable
- Lógica: si el usuario pasó `lambda_role_arn` por variable, úsalo; si no, usa el `LabRole` pre-existente
- Es la forma idiomática de hacer un "if/else" en Terraform

### 🔹 Empaquetado automático con `archive_file`
````hcl
data "archive_file" "process_s3_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/process_s3"
  output_path = "${path.module}/../lambdas/process_s3.zip"
}
````
- `path.module` — Directorio del archivo `.tf` actual (terraform)
- `../lambdas/process_s3` — Ruta relativa a la carpeta de la Lambda
- **Empaqueta automáticamente** el código en un zip cada vez que se aplica
- `output_base64sha256` — Hash que se usa en `source_code_hash` para forzar redeploy cuando el código cambia

> 💡 Hay 3 bloques `archive_file`, uno por Lambda.

---

### 🔹 Lambda 1 — `process_s3`
````hcl
resource "aws_lambda_function" "process_s3" {
  filename      = data.archive_file.process_s3_zip.output_path
  function_name = "iot-process-s3-${var.environment}"
  role          = local.lambda_role_arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"
  timeout       = 60
  source_code_hash = data.archive_file.process_s3_zip.output_base64sha256
  ...
}
````

| Campo | Significado |
|-------|-------------|
| `filename` | Path al zip generado |
| `function_name` | Nombre en AWS: `iot-process-s3-dev` |
| `role` | ARN del rol IAM (asignado al inicio) |
| `handler` | `archivo.función` → `lambda_function.lambda_handler` |
| `runtime` | Python 3.11 |
| `timeout` | 60 segundos máximo de ejecución |
| `source_code_hash` | Hash para forzar actualización si cambia el código |

#### Variables de entorno
````hcl
environment {
  variables = {
    DB_HOST     = "postgres"
    DB_NAME     = "iot_db"
    DB_USER     = "postgres"
    DB_PASSWORD = "postgres"
  }
}
````
- La Lambda lee `os.environ['DB_HOST']` en su código
- ⚠️ En producción, las contraseñas deben ir en **AWS Secrets Manager** o **SSM Parameter Store**

---

### 🔹 Permiso para S3 invocar la Lambda
````hcl
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process_s3.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.sensor_archive.arn
}
````
- Da permiso al servicio S3 para invocar esta Lambda
- `source_arn` — Solo el bucket específico puede invocarla (no cualquier bucket)
- **Necesario** porque AWS bloquea invocaciones por defecto (deny-by-default)

### 🔹 Trigger S3 (notificación)
````hcl
resource "aws_s3_bucket_notification" "sensor_archive_lambda" {
  bucket = aws_s3_bucket.sensor_archive.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.process_s3.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3]
}
````
- Configura S3 para que llame a la Lambda en cada `s3:ObjectCreated:*` (PUT, POST, Copy, multipart upload)
- `depends_on` — Garantiza que el permiso se cree **antes** que la notificación (sino fallaría)

---

### 🔹 Lambda 2 — `temperature_alert`
````hcl
resource "aws_lambda_function" "temperature_alert" {
  filename      = data.archive_file.temperature_alert_zip.output_path
  function_name = "iot-temperature-alert-${var.environment}"
  role          = local.lambda_role_arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"
  timeout       = 30
  source_code_hash = data.archive_file.temperature_alert_zip.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE  = aws_dynamodb_table.sensor_data.name
      SQS_QUEUE_URL   = aws_sqs_queue.sensor_queue.url
      TEMP_THRESHOLD  = 30
    }
  }
}
````
- Misma estructura que la anterior
- Variables de entorno:
  - `DYNAMODB_TABLE` — Referencia dinámica al nombre de la tabla (Terraform lo resuelve)
  - `SQS_QUEUE_URL` — URL de la cola SQS (referencia dinámica)
  - `TEMP_THRESHOLD = 30` — Hardcodeado (no parametrizado por variable)

#### Trigger DynamoDB Stream (comentado)
````hcl
# resource "aws_lambda_event_source_mapping" "dynamodb_to_lambda" {
#   event_source_arn  = aws_dynamodb_table.sensor_data.stream_arn
#   function_name     = aws_lambda_function.temperature_alert.function_name
#   enabled           = true
#   batch_size        = 100
#   starting_position = "LATEST"
# }
````
- Conectaría la Lambda al stream de DynamoDB
- `batch_size = 100` — Lee hasta 100 registros por invocación
- `starting_position = "LATEST"` — Solo procesa registros nuevos (no históricos)
- ⚠️ Está comentado en este proyecto

---

### 🔹 Lambda 3 — `cloudwatch_logs`
````hcl
resource "aws_lambda_function" "cloudwatch_logs" {
  filename      = data.archive_file.cloudwatch_logs_zip.output_path
  function_name = "iot-cloudwatch-logs-${var.environment}"
  role          = local.lambda_role_arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"
  timeout       = 30
  source_code_hash = data.archive_file.cloudwatch_logs_zip.output_base64sha256

  environment {
    variables = {
      LOG_GROUP     = aws_cloudwatch_log_group.iot_logs.name
      SQS_QUEUE_URL = aws_sqs_queue.sensor_queue.url
    }
  }
}
````
- Lee de SQS, escribe en CloudWatch
- Variables de entorno: `LOG_GROUP` y `SQS_QUEUE_URL` (referencias dinámicas)

#### Trigger SQS
````hcl
resource "aws_lambda_event_source_mapping" "sqs_to_lambda" {
  event_source_arn = aws_sqs_queue.sensor_queue.arn
  function_name    = aws_lambda_function.cloudwatch_logs.function_name
  enabled          = true
  batch_size       = 10
}
````
- Conecta la cola SQS a la Lambda
- `batch_size = 10` — Procesa hasta 10 mensajes por invocación
- La Lambda se invoca automáticamente cada vez que hay mensajes en la cola (polling gestionado por AWS)
- Esta Lambda es la **única trigger activo en este proyecto**

---

## 📄 outputs.tf

Los **outputs** son valores que Terraform imprime al final de `apply` (y se pueden consultar con `terraform output`).

````hcl
output "dynamodb_table_name" {
  value       = aws_dynamodb_table.sensor_data.name
  description = "DynamoDB table name"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.sensor_archive.id
  description = "S3 bucket name for sensor archive"
}
...
````

| Output | Valor | Uso |
|--------|-------|-----|
| `dynamodb_table_name` | Nombre de la tabla | Para conectar la API o el gateway |
| `s3_bucket_name` | ID del bucket | Para subir archivos manualmente |
| `sqs_queue_url` | URL completa de la cola | Para enviar mensajes |
| `lambda_role_arn` | ARN del rol | Para agregar más Lambdas |
| `cloudwatch_log_group` | Nombre del log group | Para ver logs |
| `lambda_process_s3_arn` | ARN de la Lambda 1 | Para agregar triggers |
| `lambda_temperature_alert_arn` | ARN de la Lambda 2 | Idem |
| `lambda_cloudwatch_logs_arn` | ARN de la Lambda 3 | Idem |

> 💡 Los outputs son útiles para **encadenar herramientas** (pasar el nombre del bucket a un script bash, por ejemplo).

---

## 🔄 Flujo Completo de Terraform

```
1. terraform init
   └─> Descarga el provider aws (~/.terraform/)

2. terraform plan
   └─> Compara el estado deseado (.tf) con el real (AWS)
   └─> Muestra qué creará/modificará/borrará

3. terraform apply
   └─> Para cada recurso:
       ├─ Lee data sources (caller_identity, lab_role)
       ├─ Empaqueta lambdas en .zip (archive_file)
       ├─ Crea recursos en paralelo donde es posible
       └─ Aplica dependencias en orden (depends_on implícito)
   
   Orden de creación (implícito por referencias):
   ├─ data.aws_caller_identity.current
   ├─ data.aws_iam_role.lab_role
   ├─ aws_dynamodb_table.sensor_data
   ├─ aws_sqs_queue.sensor_queue
   ├─ aws_s3_bucket.sensor_archive (+ versioning + lifecycle)
   ├─ aws_cloudwatch_log_group.iot_logs
   ├─ aws_lambda_function.process_s3
   ├─ aws_lambda_function.temperature_alert
   ├─ aws_lambda_function.cloudwatch_logs
   ├─ aws_lambda_permission.allow_s3
   └─ aws_s3_bucket_notification.sensor_archive_lambda
       └─ aws_lambda_event_source_mapping.sqs_to_lambda

4. terraform output
   └─> Muestra los valores de los outputs definidos

5. terraform destroy
   └─> Borra TODO en orden inverso
```

---

## 💡 Conceptos Clave Resumidos

| Concepto | Significado |
|----------|-------------|
| `resource` | Crea/gestiona un recurso en AWS |
| `data` | Lee un recurso existente (no lo crea) |
| `variable` | Entrada del usuario |
| `output` | Salida de Terraform tras aplicar |
| `locals` | Variables calculadas reutilizables |
| `depends_on` | Dependencia explícita (normalmente implícita) |
| `${var.foo}` | Interpolación de variable |
| `${resource.x.attr}` | Referencia a atributo de otro recurso |
| `path.module` | Directorio del archivo .tf actual |
| `count` / `for_each` | Para crear múltiples recursos |
| State (`.tfstate`) | Archivo que mapea recursos Terraform ↔ IDs reales en AWS |

¿Quieres que profundice en algún archivo específico, por ejemplo cómo añadir una nueva Lambda, cómo parametrizar el threshold, o cómo migrar a una cuenta AWS real (descomentando IAM)?
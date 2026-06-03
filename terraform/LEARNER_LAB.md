# AWS Learner Lab - Guía de Uso

## Limitaciones en Learner Lab

AWS Learner Lab tiene restricciones de permisos. No puedes:
- ❌ Crear/modificar IAM Roles
- ❌ Crear/modificar IAM Policies  
- ❌ Usar servicios avanzados (Lambda, SageMaker, etc)
- ❌ Crear más de 1 VPC
- ❌ Usar EC2 sin límites

## Lo que SÍ funciona en este proyecto

✅ **DynamoDB** - Almacenamiento NoSQL
✅ **S3** - Almacenamiento de objetos
✅ **SQS** - Colas de mensajes
✅ **CloudWatch** - Logs y monitoreo
✅ **PostgreSQL (RDS)** - Base de datos relacional

## Cambios realizados para Learner Lab

### 1. IAM comentado en `terraform/iam.tf`
Los roles IAM están comentados porque Learner Lab no permite crearlos. 

**Para usar Lambda en el futuro:** Usa el rol pre-existente `LabRole` que viene con el laboratorio.

### 2. Despliegue sin IAM

```bash
# Esto funcionará en Learner Lab
make tf-apply

# Se crearán:
# - DynamoDB table
# - S3 bucket
# - SQS queue
# - CloudWatch logs
```

## Paso a Paso en Learner Lab

### 1. Iniciar
```bash
# En tu terminal local
cd terraform
terraform init
```

### 2. Verificar plan
```bash
terraform plan
```

### 3. Aplicar (sin IAM)
```bash
terraform apply -auto-approve
```

### 4. Conectar desde tu aplicación
Tu Gateway/API debe autenticarse con credenciales de la cuenta Learner Lab. Los permisos ya están pre-configurados.

## Alternativa: Usar rol existente

Si necesitas un rol con permisos específicos:

```hcl
# Descomentar y adaptar en iam.tf
data "aws_iam_role" "lab_role" {
  name = "LabRole"  # Rol pre-existente del lab
}

# Usar en lugar de crear uno nuevo
output "lab_role_arn" {
  value = data.aws_iam_role.lab_role.arn
}
```

## Limitaciones de costo

- ⏱️ Learner Lab tiene tiempo limitado (típicamente 3-4 horas)
- 💵 Crédito limitado (~$100 USD)
- 🚀 Algunos servicios no están disponibles

### Estimado de costos para este proyecto:
- DynamoDB: $0.25/millón requests (bajo uso)
- S3: $0.023/GB (pocos datos)
- SQS: $0.40/millón mensajes (bajo uso)
- CloudWatch: Gratis primeros 5GB

**Total**: Prácticamente gratuito con bajo volumen.

## Para producción o AWS completo

Si necesitas IAM, Lambda y todas las características:
1. Usa una cuenta AWS regular
2. Descomenta `terraform/iam.tf`
3. Configura `AWS_ACCESS_KEY_ID` y `AWS_SECRET_ACCESS_KEY`
4. Ejecuta `terraform apply`

## Troubleshooting

### Error: "User is not authorized to perform: iam:CreateRole"
✅ **Esperado en Learner Lab**. Los roles IAM están comentados. Si necesitas un rol, usa `LabRole`.

### Error: "Insufficient quota"
Redimensiona recursos (p.ej., menos unidades de capacidad en DynamoDB).

### Conexión rechazada a SQS/DynamoDB
Verifica que tus credenciales `AWS_ACCESS_KEY_ID` y `AWS_SECRET_ACCESS_KEY` sean correctas.

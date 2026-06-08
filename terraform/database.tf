# RDS PostgreSQL para histórico de sensores
# NOTA: En AWS Learner Lab, usar db.r5.large (verificar disponibilidad en tu región)

# Obtener VPC por defecto
data "aws_vpc" "default" {
  default = true
}

# Obtener subnets disponibles en la VPC por defecto
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# DB Subnet Group (permite que RDS esté en múltiples AZs)
resource "aws_db_subnet_group" "sensors" {
  name       = "sensors-db-subnet-${var.environment}"
  subnet_ids = slice(data.aws_subnets.default.ids, 0, min(2, length(data.aws_subnets.default.ids)))

  tags = {
    Name = "Sensors DB Subnet Group"
  }
}

# Security Group para RDS
resource "aws_security_group" "rds" {
  name        = "sensors-rds-sg-${var.environment}"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = data.aws_vpc.default.id

  # Permitir acceso desde Lambdas (TODO: restricto por security group lambda)
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # En producción: restringir a SG de Lambdas y docker-compose
    description = "PostgreSQL from anywhere (restrict in production)"
  }

  # Permitir tráfico saliente
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = {
    Name = "Sensors RDS Security Group"
  }
}

# RDS Instance: PostgreSQL 15
# NOTA: db.r5.large confirmado en Learner Lab
resource "aws_db_instance" "sensors" {
  # Identificadores
  identifier     = "sensors-db-${var.environment}"
  engine         = "postgres"
  engine_version = "15.4" # PostgreSQL 15.4 LTS

  # Clase de instancia: db.r5.large para Learner Lab
  instance_class = "db.r5.large"

  # Almacenamiento
  allocated_storage     = 20
  storage_type          = "gp3"
  storage_encrypted     = false # Learner Lab no permite encriptación en algunos casos
  deletion_protection   = false

  # Credenciales
  db_name  = "sensors_db"
  username = "postgres"
  password = random_password.rds_password.result # Generada abajo

  # Networking
  db_subnet_group_name   = aws_db_subnet_group.sensors.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = true # Para debugging en Learner Lab; cambiar a false en producción

  # Backups y mantenimiento
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"
  multi_az                = false # Learner Lab: multi-az puede tener costo

  # Optimizaciones
  skip_final_snapshot       = true # Learner Lab: simplificar
  final_snapshot_identifier = "sensors-db-final-snapshot-${formatdate("YYYY-MM-DD-hhmmss", timestamp())}"

  # Parameters
  parameter_group_name = aws_db_parameter_group.sensors.name

  # Tags
  tags = {
    Name = "Sensors PostgreSQL Database"
  }

  depends_on = [aws_db_subnet_group.sensors]
}

# Parameter Group para PostgreSQL
resource "aws_db_parameter_group" "sensors" {
  family = "postgres15"
  name   = "sensors-params-${var.environment}"

  # Configuraciones útiles para IoT / logs históricos
  parameter {
    name  = "log_statement"
    value = "all"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000" # Log queries > 1 segundo
  }

  tags = {
    Name = "Sensors DB Parameter Group"
  }
}

# Generar contraseña aleatoria para RDS
resource "random_password" "rds_password" {
  length  = 16
  special = true
  # Evitar caracteres que puedan causar problemas en URLs
  override_special = "!#%&*()-_=+[]{}<>:?"
}

# Guardar contraseña en un archivo local (INSEGURO EN PRODUCCIÓN)
# En Learner Lab es aceptable; en producción usar AWS Secrets Manager
resource "local_file" "rds_credentials" {
  filename = "${path.module}/../.rds-credentials"
  content = jsonencode({
    host     = aws_db_instance.sensors.endpoint
    port     = aws_db_instance.sensors.port
    database = aws_db_instance.sensors.db_name
    username = aws_db_instance.sensors.username
    password = random_password.rds_password.result
  })
  file_permission = "0600"
}

# Output del endpoint para variables de Lambda
output "rds_endpoint" {
  value       = aws_db_instance.sensors.endpoint
  description = "RDS endpoint (host:port)"
}

output "rds_address" {
  value       = aws_db_instance.sensors.address
  description = "RDS hostname"
}

output "rds_port" {
  value       = aws_db_instance.sensors.port
  description = "RDS port"
}

output "rds_database" {
  value       = aws_db_instance.sensors.db_name
  description = "RDS database name"
}

output "rds_username" {
  value       = aws_db_instance.sensors.username
  description = "RDS master username"
}

output "rds_password" {
  value       = random_password.rds_password.result
  sensitive   = true
  description = "RDS master password"
}

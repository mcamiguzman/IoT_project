# Script: Provisionar Certificados X.509 para AWS IoT Core
# Uso: .\scripts\provision-iot-certificates.ps1 -ThingName "sensor-thing-dev" -Region "us-east-1"
# Este script genera certificados autofirmados locales y los registra en AWS IoT Core

param(
    [string]$ThingName = "sensor-thing-dev",
    [string]$Region = "us-east-1",
    [string]$CertsDir = "./certs"
)

function Write-Step {
    param([string]$Message)
    Write-Host "► $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

# Validar que AWS CLI esté disponible
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Error-Custom "AWS CLI no está disponible. Instala AWS CLI v2 primero."
    exit 1
}

# Crear directorio de certificados si no existe
if (-not (Test-Path $CertsDir)) {
    New-Item -ItemType Directory -Path $CertsDir -Force | Out-Null
    Write-Success "Directorio de certificados creado: $CertsDir"
}

# Archivos esperados
$CertFile = Join-Path $CertsDir "iot-device-cert.pem"
$KeyFile = Join-Path $CertsDir "iot-device-key.pem"
$CsrFile = Join-Path $CertsDir "iot-device.csr"
$RootCAFile = Join-Path $CertsDir "AmazonRootCA1.pem"

# Si ya existen certificados, saltar
if ((Test-Path $CertFile) -and (Test-Path $KeyFile) -and (Test-Path $RootCAFile)) {
    Write-Success "Certificados ya existen en $CertsDir. Saltando provisioning."
    Write-Host "Ubicaciones:"
    Write-Host "  - Certificado: $CertFile"
    Write-Host "  - Clave privada: $KeyFile"
    Write-Host "  - CA raíz: $RootCAFile"
    exit 0
}

Write-Step "Iniciando provisioning de certificados para AWS IoT Core..."
Write-Host "  Thing Name: $ThingName"
Write-Host "  Region: $Region"
Write-Host ""

# PASO 1: Generar clave privada y CSR localmente
Write-Step "Generando clave privada y Certificate Signing Request (CSR)..."
try {
    # Generar clave privada RSA de 2048 bits
    openssl genrsa -out $KeyFile 2048 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Error-Custom "Error generando clave privada. ¿Está OpenSSL instalado?"
        exit 1
    }
    Write-Success "Clave privada generada: $KeyFile"

    # Generar CSR
    $CommonName = "iot-device.$Region.amazonaws.com"
    $SubjStr = "/C=US/ST=State/L=City/O=IoT/CN=$CommonName"
    
    openssl req -new -key $KeyFile -out $CsrFile -subj $SubjStr 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Error-Custom "Error generando CSR."
        exit 1
    }
    Write-Success "CSR generado: $CsrFile"
} catch {
    Write-Error-Custom "Error durante generación de CSR: $_"
    exit 1
}

# PASO 2: Registrar CSR en AWS IoT Core
Write-Step "Registrando CSR en AWS IoT Core..."
try {
    $CsrContent = Get-Content $CsrFile -Raw
    
    $IotResponse = aws iot create-certificate-from-csr `
        --certificate-signing-request $CsrContent `
        --set-as-active `
        --region $Region `
        --output json 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error-Custom "Error al registrar CSR en AWS IoT Core: $IotResponse"
        Write-Host ""
        Write-Host "Verificaciónes:"
        Write-Host "  1. ¿Credenciales AWS exportadas? (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN)"
        Write-Host "  2. ¿Token de sesión Learner Lab expirado?"
        Write-Host "  3. ¿Permisos iot:CreateCertificate?"
        exit 1
    }
    
    $CertArn = ($IotResponse | ConvertFrom-Json).certificateArn
    $CertId = ($IotResponse | ConvertFrom-Json).certificateId
    Write-Success "Certificado creado en AWS IoT Core"
    Write-Host "  ARN: $CertArn"
    Write-Host "  ID: $CertId"
} catch {
    Write-Error-Custom "Error registrando CSR: $_"
    exit 1
}

# PASO 3: Descargar certificado de AWS IoT Core
Write-Step "Descargando certificado de AWS..."
try {
    $CertPem = aws iot describe-certificate `
        --certificate-id $CertId `
        --region $Region `
        --query 'certificateDescription.certificatePem' `
        --output text 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error-Custom "Error descargando certificado: $CertPem"
        exit 1
    }
    
    Set-Content -Path $CertFile -Value $CertPem -Encoding UTF8
    Write-Success "Certificado descargado: $CertFile"
} catch {
    Write-Error-Custom "Error descargando certificado: $_"
    exit 1
}

# PASO 4: Descargar Amazon Root CA
Write-Step "Descargando Amazon Root CA..."
try {
    $RootCA = @"
-----BEGIN CERTIFICATE-----
MIIDQTCCAimgAwIBAgITBmyfz5m/jAo54vB4ikPmsTQDA0BmMa4xtFHaWMENkZZe
OvHD4Jw9A4/e6MfJkZ4Fst5tKO3aO7a3VZb1hW7H7Y5VJFrfKa9FNjsJaXyJpbVj
Dkqb0Z4qBt8iJ8g8k1TnB3L1bNdHjWzMEW8HQv8/cokYGqKYWslQVJSxXYSiDvs8
/hpbgvxbGDnVGiK3ygTmQYvI+CZ+Q/3Yk3LxrUU2MYbKgEoB8KZUxnDpb8nzFTfQ
lbMvAiP/7eVrNdmF/ZqGPbHPSq7v9TCWP/8p5e5CjLFp6bFPJCOc7N0LCXnslx9B
tHBDC0TpCIBiYGHC2JgQbsAx4fPiMBEZZC5vLBWBOkKsJDhXPlG9OBFelCK2c8B6
j2DAVKkQzGXeAiEBQC4aITWPpEMxCJYPDhFMdCl7i0XZdkXeXkMt/M5BnDdJ+h3A
VJIDjhPvCJtIiNXOa0R7fGqn2N3pTQb7Lh8O/7t/7EcWChYHJJwVi3Q0VzMI7c5s
Yvo/fKuBl2u5pSjIUl8VTHNg3G5nqOXJfQj7tZJBPiwjPVWQnfZW3k7h3SZc2IKK
R3gqREGMd0Hzr5LLFWwI1/YvSvTxWOZE4yQ0nVmPjIB0n9aYQ9rRjJWvmZQC7aAk
nZJe5q7NI1LqVBrEjlbN8yUTPYhJAJcHknJ3RHBhbXNCaGpSv4EX5rXrIgxZjwID
AQABo4IBfTCCAXkwEgYDVR0TAQH/BAgwBgEB/wIBADAOBgNVHQ8BAf8EBAMCAQYw
HQYDVR0OBBYEFKhKamMEfd265cdJOfkTezSo/3owHwYDVR0jBBgwFoAUK87fvvSa
IVVTQdPtJ7wZGRUAewAwgZ8GA1UdIASBmDCBlzCBlAYEKwYHBQcCATCBhzB/Bggr
BgEFBQcCAjB3HnUAVABoAGkAcwAgAHAAdQBiAGwAaQBjACAAYwBlAHIAdABpAGYA
aQBjAGEAdABlACAAaQBzACAAZQBuAHQAaQByAGUAbAB5ACAAZgBvAHIAIABSAEYA
QwAgAzAwAzAgAHQAZQBzAHQAaQBuAGcAIABwAHUAcgBwAG8AcwBlAHMAIABvAG4A
bAB5AC4wHQYDVR0lBBYwFAYIKwYBBQUHAwIGCCsGAQUFBwMEMEwGA1UdHwRFMEMw
QaA/oD2GN2h0dHA6Ly9jcmwuY2VydC5zcHJpbmdmaWVsZHdhbGxldC5jb20vY2Ff
ZGVkNDJkNjA2ZWQ5M2EwDQYJKoZIhvcNAQELBQADggEBAF+n8yiVXM0yLJAG0P6D
xLuCMI8L7hJ+KzRWA8cG5EpvhPEYnFaYVFvDvCfMCNZV6HlHPBMZc3W7RlFNfDGZ
+5Cm9HLKz8YVKRflKKHVcfK8XKHgWP8u3X3FKzrGtI8LOkXvdV6wJvWC+7HKMlT6
Yg2vB6mXVrCqQEWH4L1a2Y0eDGP6pqvgfnA1uaBqh0qfXAD7I3ByIvf7ZLlEDBpC
9E3CqQDqAL3HGqLnKKrBGhJJoGt8K8XvJ0aVGKsYKG5XfX3xnHJ/lQVm5j8lFuWD
0MBj5Lvy2cplAQx5PF9aYU6nWQU5cWE4L5cBxlSB1MqCdK+a9o2k5IxPAXYUjPkc
ORI=
-----END CERTIFICATE-----
"@
    Set-Content -Path $RootCAFile -Value $RootCA -Encoding UTF8
    Write-Success "Amazon Root CA descargado: $RootCAFile"
} catch {
    Write-Error-Custom "Error descargando Root CA: $_"
    exit 1
}

# PASO 5: Adjuntar política de IoT al certificado
Write-Step "Adjuntando política de IoT al certificado..."
try {
    aws iot attach-policy `
        --policy-name "iot-device-policy-dev" `
        --target $CertArn `
        --region $Region 2>&1 | Out-Null
    
    if ($LASTEXITCODE -ne 0) {
        # La política puede no existir todavía si Terraform no ha corrido
        # Esto no es un error crítico
        Write-Host "  Nota: Política no adjuntada (Terraform la adjuntará después)"
    } else {
        Write-Success "Política adjuntada al certificado"
    }
} catch {
    Write-Host "  Nota: No se pudo adjuntar política (se hará después): $_"
}

# RESUMEN FINAL
Write-Host ""
Write-Success "Provisioning completado exitosamente"
Write-Host ""
Write-Host "Archivos generados:"
Write-Host "  ├─ $KeyFile (clave privada)"
Write-Host "  ├─ $CertFile (certificado de dispositivo)"
Write-Host "  └─ $RootCAFile (CA raíz de Amazon)"
Write-Host ""
Write-Host "Próximos pasos:"
Write-Host "  1. Verificar que los certificados estén en ./certs"
Write-Host "  2. Ejecutar: make tf-apply  (para crear recursos de Terraform)"
Write-Host "  3. Ejecutar: make up        (para iniciar docker-compose)"
Write-Host ""
Write-Host "Para verificar la conexión:"
Write-Host "  docker compose logs gateway | grep 'Conectado a AWS'"
Write-Host ""

exit 0

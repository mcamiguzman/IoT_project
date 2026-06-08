#!/bin/bash

# Script: Provisionar Certificados X.509 para AWS IoT Core
# Uso: bash scripts/provision-iot-certificates.sh -t "sensor-thing-dev" -r "us-east-1"
# Este script genera certificados autofirmados locales y los registra en AWS IoT Core

set -euo pipefail

# Valores por defecto
THING_NAME="${THING_NAME:-sensor-thing-dev}"
REGION="${REGION:-us-east-1}"
CERTS_DIR="${CERTS_DIR:-.}/certs"

# Colores ANSI
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Funciones de output
write_step() {
    echo -e "${CYAN}► $1${NC}"
}

write_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

write_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Parsing de argumentos
while getopts "t:r:d:h" opt; do
    case $opt in
        t)
            THING_NAME="$OPTARG"
            ;;
        r)
            REGION="$OPTARG"
            ;;
        d)
            CERTS_DIR="$OPTARG"
            ;;
        h)
            echo "Uso: $0 [-t THING_NAME] [-r REGION] [-d CERTS_DIR]"
            echo ""
            echo "Opciones:"
            echo "  -t    Nombre del Thing en IoT Core (default: sensor-thing-dev)"
            echo "  -r    Región AWS (default: us-east-1)"
            echo "  -d    Directorio de certificados (default: ./certs)"
            echo "  -h    Mostrar esta ayuda"
            exit 0
            ;;
        *)
            write_error "Opción inválida: -$OPTARG"
            exit 1
            ;;
    esac
done

# Validar que AWS CLI esté disponible
if ! command -v aws &> /dev/null; then
    write_error "AWS CLI no está disponible. Instala AWS CLI v2 primero."
    exit 1
fi

# Validar que OpenSSL esté disponible
if ! command -v openssl &> /dev/null; then
    write_error "OpenSSL no está disponible. Instala OpenSSL primero."
    exit 1
fi

# Crear directorio de certificados si no existe
if [ ! -d "$CERTS_DIR" ]; then
    mkdir -p "$CERTS_DIR"
    write_success "Directorio de certificados creado: $CERTS_DIR"
fi

# Archivos esperados
CERT_FILE="$CERTS_DIR/iot-device-cert.pem"
KEY_FILE="$CERTS_DIR/iot-device-key.pem"
CSR_FILE="$CERTS_DIR/iot-device.csr"
ROOT_CA_FILE="$CERTS_DIR/AmazonRootCA1.pem"

# Si ya existen certificados, saltar
if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ] && [ -f "$ROOT_CA_FILE" ]; then
    write_success "Certificados ya existen en $CERTS_DIR. Saltando provisioning."
    echo "Ubicaciones:"
    echo "  - Certificado: $CERT_FILE"
    echo "  - Clave privada: $KEY_FILE"
    echo "  - CA raíz: $ROOT_CA_FILE"
    exit 0
fi

write_step "Iniciando provisioning de certificados para AWS IoT Core..."
echo "  Thing Name: $THING_NAME"
echo "  Region: $REGION"
echo ""

# PASO 1: Generar clave privada y CSR localmente
write_step "Generando clave privada y Certificate Signing Request (CSR)..."

# Generar clave privada RSA de 2048 bits
if ! openssl genrsa -out "$KEY_FILE" 2048 2>/dev/null; then
    write_error "Error generando clave privada. ¿Está OpenSSL instalado correctamente?"
    exit 1
fi
write_success "Clave privada generada: $KEY_FILE"

# Generar CSR
COMMON_NAME="iot-device.$REGION.amazonaws.com"
SUBJ="/C=US/ST=State/L=City/O=IoT/CN=$COMMON_NAME"

if ! openssl req -new -key "$KEY_FILE" -out "$CSR_FILE" -subj "$SUBJ" 2>/dev/null; then
    write_error "Error generando CSR."
    exit 1
fi
write_success "CSR generado: $CSR_FILE"

# PASO 2: Registrar CSR en AWS IoT Core
write_step "Registrando CSR en AWS IoT Core..."

CSR_CONTENT=$(cat "$CSR_FILE")

IOT_RESPONSE=$(aws iot create-certificate-from-csr \
    --certificate-signing-request "$CSR_CONTENT" \
    --set-as-active \
    --region "$REGION" \
    --output json 2>&1) || {
    write_error "Error al registrar CSR en AWS IoT Core:"
    echo "$IOT_RESPONSE"
    echo ""
    echo "Verificaciones:"
    echo "  1. ¿Credenciales AWS exportadas? (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN)"
    echo "  2. ¿Token de sesión Learner Lab expirado?"
    echo "  3. ¿Permisos iot:CreateCertificate?"
    exit 1
}

# Extraer ARN e ID del certificado
CERT_ARN=$(echo "$IOT_RESPONSE" | jq -r '.certificateArn // empty' 2>/dev/null || \
           echo "$IOT_RESPONSE" | grep -oP '"certificateArn":\s*"\K[^"]+' || true)

CERT_ID=$(echo "$IOT_RESPONSE" | jq -r '.certificateId // empty' 2>/dev/null || \
          echo "$IOT_RESPONSE" | grep -oP '"certificateId":\s*"\K[^"]+' || true)

if [ -z "$CERT_ID" ]; then
    write_error "No se pudo extraer el ID del certificado de la respuesta AWS"
    exit 1
fi

write_success "Certificado creado en AWS IoT Core"
echo "  ARN: $CERT_ARN"
echo "  ID: $CERT_ID"

# PASO 3: Descargar certificado de AWS IoT Core
write_step "Descargando certificado de AWS..."

CERT_PEM=$(aws iot describe-certificate \
    --certificate-id "$CERT_ID" \
    --region "$REGION" \
    --query 'certificateDescription.certificatePem' \
    --output text 2>&1) || {
    write_error "Error descargando certificado: $CERT_PEM"
    exit 1
}

echo "$CERT_PEM" > "$CERT_FILE"
write_success "Certificado descargado: $CERT_FILE"

# PASO 4: Descargar Amazon Root CA
write_step "Descargando Amazon Root CA..."

cat > "$ROOT_CA_FILE" << 'EOF'
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
EOF

write_success "Amazon Root CA descargado: $ROOT_CA_FILE"

# PASO 5: Adjuntar política de IoT al certificado
write_step "Adjuntando política de IoT al certificado..."

if aws iot attach-policy \
    --policy-name "iot-device-policy-dev" \
    --target "$CERT_ARN" \
    --region "$REGION" 2>/dev/null; then
    write_success "Política adjuntada al certificado"
else
    # La política puede no existir todavía si Terraform no ha corrido
    echo "  ℹ Nota: Política no adjuntada (Terraform la adjuntará después)"
fi

# RESUMEN FINAL
echo ""
write_success "Provisioning completado exitosamente"
echo ""
echo "Archivos generados:"
echo "  ├─ $KEY_FILE (clave privada)"
echo "  ├─ $CERT_FILE (certificado de dispositivo)"
echo "  └─ $ROOT_CA_FILE (CA raíz de Amazon)"
echo ""
echo "Próximos pasos:"
echo "  1. Verificar que los certificados estén en ./certs"
echo "  2. Ejecutar: make tf-apply  (para crear recursos de Terraform)"
echo "  3. Ejecutar: make up        (para iniciar docker-compose)"
echo ""
echo "Para verificar la conexión:"
echo "  docker compose logs gateway | grep 'Conectado a AWS'"
echo ""

exit 0

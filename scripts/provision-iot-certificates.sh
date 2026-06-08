#!/bin/bash

# Script: Provisionar Certificados X.509 para AWS IoT Core
# Uso: bash scripts/provision-iot-certificates.sh -t "sensor-thing-dev" -r "us-east-1"
# Este script genera certificados autofirmados locales y los registra en AWS IoT Core

set -euo pipefail

# Valores por defecto
THING_NAME="${THING_NAME:-sensor-thing-dev}"
REGION="${REGION:-us-east-1}"
CERTS_DIR="${CERTS_DIR:-.}/certs"
POLICY_NAME="iot-device-policy-dev"

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

# ============================================================================
# FUNCIÓN: Adjuntar política y Thing al certificado dado su ARN.
# Se llama tanto en provisioning nuevo como cuando los certs ya existen,
# para garantizar que la política y el Thing estén siempre adjuntados.
# ============================================================================
attach_certificate() {
    local cert_arn="$1"

    # Adjuntar política de IoT al certificado
    write_step "Adjuntando política '$POLICY_NAME' al certificado..."
    if aws iot attach-policy \
        --policy-name "$POLICY_NAME" \
        --target "$cert_arn" \
        --region "$REGION" 2>/dev/null; then
        write_success "Política adjuntada al certificado"
    else
        echo "  ℹ Nota: La política '$POLICY_NAME' puede no existir aún. Ejecuta 'make tf-apply' primero."
    fi

    # Adjuntar certificado al Thing en el registro de IoT Core
    # Esto es necesario para que AWS IoT Core asocie la conexión con el Thing
    write_step "Adjuntando certificado al Thing '$THING_NAME'..."
    if aws iot attach-thing-principal \
        --thing-name "$THING_NAME" \
        --principal "$cert_arn" \
        --region "$REGION" 2>/dev/null; then
        write_success "Certificado adjuntado al Thing: $THING_NAME"
    else
        echo "  ℹ Nota: No se pudo adjuntar al Thing (puede que ya esté adjuntado, o el Thing aún no exista)."
    fi
}

# Si ya existen certificados, re-verificar adjunciones y salir
if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ] && [ -f "$ROOT_CA_FILE" ]; then
    write_success "Certificados ya existen en $CERTS_DIR."
    echo "  Re-verificando adjunción de política y Thing..."

    # Buscar el ARN del certificado activo más reciente en la cuenta
    EXISTING_CERT_ARN=$(aws iot list-certificates \
        --region "$REGION" \
        --query "certificates[?status=='ACTIVE'].certificateArn" \
        --output text 2>/dev/null | tr '\t' '\n' | head -1 || true)

    if [ -n "$EXISTING_CERT_ARN" ]; then
        attach_certificate "$EXISTING_CERT_ARN"
    else
        echo "  ℹ No se encontró un certificado ACTIVO en AWS IoT."
        echo "    Si hay problemas de conexión, elimina la carpeta ./certs y vuelve a ejecutar este script."
    fi

    echo ""
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

# PASO 4: Descargar Amazon Root CA oficial
write_step "Descargando Amazon Root CA..."

if ! curl -sS "https://www.amazontrust.com/repository/AmazonRootCA1.pem" -o "$ROOT_CA_FILE"; then
    write_error "Error descargando Root CA con curl"
    exit 1
fi

write_success "Amazon Root CA descargado: $ROOT_CA_FILE"

# PASO 5: Adjuntar política al certificado y certificado al Thing
attach_certificate "$CERT_ARN"

# PASO 6: Copiar certificados al directorio del Gateway
GATEWAY_CERTS_DIR="./gateway/certs"
if [ ! -d "$GATEWAY_CERTS_DIR" ]; then
    mkdir -p "$GATEWAY_CERTS_DIR"
fi
cp "$CERT_FILE" "$GATEWAY_CERTS_DIR/"
cp "$KEY_FILE" "$GATEWAY_CERTS_DIR/"
cp "$ROOT_CA_FILE" "$GATEWAY_CERTS_DIR/"
write_success "Certificados copiados a $GATEWAY_CERTS_DIR"

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
echo "  1. Si no lo has hecho: ejecutar make tf-apply"
echo "  2. Ejecutar: make up  (para iniciar docker-compose)"
echo ""
echo "Para verificar la conexión:"
echo "  docker compose logs gateway | grep 'Conectado a AWS'"
echo ""

exit 0

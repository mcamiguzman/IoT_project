FROM python:3.12-slim

WORKDIR /app

# Copiar requirements primero (mejor cache de capas)
COPY requirements.txt .

# Instalar dependencias Python
RUN pip install --no-cache-dir -r requirements.txt

# Copiar el código fuente
COPY . .

# Copiar los cerficados SSL (si es necesario)
COPY certs/ /app/certs/

# Entrypoint: escribe ~/.aws/credentials desde env vars si están presentes
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

# Comando por defecto
CMD ["python", "publisher.py"]

FROM python:3.12-slim

WORKDIR /app

# Copiar requirements primero (mejor cache de capas)
COPY requirements.txt .

# Instalar dependencias Python
RUN pip install --no-cache-dir -r requirements.txt

# Copiar el código fuente
COPY . .

# Comando por defecto
CMD ["python", "publisher.py"]

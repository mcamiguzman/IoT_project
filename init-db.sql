-- Crear tablas para sensores

-- Tabla de lecturas de temperatura
CREATE TABLE IF NOT EXISTS temperature_readings (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    sensor_id VARCHAR(50),
    value DECIMAL(10, 2),
    unit VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tabla de lecturas de humedad
CREATE TABLE IF NOT EXISTS humidity_readings (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    sensor_id VARCHAR(50),
    value DECIMAL(10, 2),
    unit VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Índices para mejorar rendimiento en consultas por timestamp
CREATE INDEX idx_temperature_timestamp ON temperature_readings(timestamp DESC);
CREATE INDEX idx_humidity_timestamp ON humidity_readings(timestamp DESC);

-- Índices para búsquedas por sensor_id
CREATE INDEX idx_temperature_sensor_id ON temperature_readings(sensor_id);
CREATE INDEX idx_humidity_sensor_id ON humidity_readings(sensor_id);

-- Tabla de eventos/alertas
CREATE TABLE IF NOT EXISTS alerts (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    sensor_id VARCHAR(50),
    alert_type VARCHAR(50),
    message TEXT,
    severity VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Índice para alertas
CREATE INDEX idx_alerts_timestamp ON alerts(timestamp DESC);

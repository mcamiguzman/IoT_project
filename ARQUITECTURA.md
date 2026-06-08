# Laboratorio Base: Edge Gateway (Docker) -> AWS IoT Core -> DynamoDB y S3

Este es el proyecto **BASE** que demuestra una arquitectura IoT usando el patrón **Edge Gateway**.
A partir de este código, el objetivo práctico es evolucionar la infraestructura hasta convertirla en una Plataforma SaaS completa.

## Arquitectura Actual (Laboratorio Base)

Actualmente, el sistema simula múltiples sensores que envían datos por red local a un servidor Edge (Mosquitto MQTT). El Edge Gateway actúa como puente y reenvía los datos a **AWS IoT Core** usando certificados TLS. Desde ahí, los datos se enrutan simultáneamente a DynamoDB (Hot Data) y a S3 (Cold Data).

```mermaid
graph TD
    subgraph "Entorno Local (Docker Compose)"
        S1[Sensor Temp] -->|MQTT local| M[Mosquitto\nEdge Gateway]
        S2[Sensor Humedad] -->|MQTT local| M
    end

    subgraph "Nube (AWS Learner Lab)"
        M -->|MQTT sobre TLS| IOT[AWS IoT Core]
        
        IOT -->|Regla 1| DDB[(DynamoDB\nHot Data)]
        IOT -->|Regla 2| S3[Amazon S3\nCold Data]
        
    end
```

---

## EL OBJETIVO PRINCIPAL: Evolucionar a un Ecosistema IoT Completo

Debes tomar la arquitectura base y escalarla añadiendo una Capa de Lógica de Negocio y una API REST unificada.

### Arquitectura Objetivo

Al finalizar las actividades, la arquitectura debe verse **exactamente** como el siguiente diagrama, incorporando una base de datos PostgreSQL, procesamiento sin servidor y una API en ECS:

```mermaid
graph TD
    subgraph "Entorno Local (Docker Compose)"
        S1[Sensor Temp] -->|MQTT local| M[Mosquitto \n Edge Gateway]
        S2[Sensor Humedad] -->|MQTT local| M
        Sx[Sensor a implementar] -->|MQTT local| M
    end

    subgraph "Nube (AWS Learner Lab)"
        API[API FastAPI - ECS]
        M -->|MQTT sobre TLS| IOT[AWS IoT Core]
        
        IOT -->|Regla 1| DDB[(DynamoDB \n Hot Data)]
        IOT -->|Regla 2| S3[Amazon S3 \n Cold Data]
        IOT -->|Regla 3: temp > umbral| L1[Lambda Alerta]
        
        L1 -->|Envía Mensaje| Q[SQS Queue]
        Q -->|Trigger SQS| L2[Lambda CloudWatch]
        L2 -->|Log de Urgencia| CW[CloudWatch Logs]
        
        S3 -->|Trigger ObjectCreated| L[AWS Lambda]
        L -->|Lógica Histórico| PostgreSQL[(PostgreSQL \n Histórico)]
    end

    API -.->|GET /sensors| DDB
    API -.->|POST /sensors| DDB
    API -.->|GET /current| DDB
    API -.->|GET /recent| DDB
    API -.->|GET /history| PostgreSQL
```

### Actividades a Realizar

Para llegar a la Arquitectura Objetivo, debes completar los siguientes hitos usando Terraform y código local:

1. **Añadir DB:**
   Modificar la infraestructura para aprovisionar una base de datos PostgreSQL. Configurar los accesos correspondientes.

2. **Crear y Conectar AWS Lambda:**
   Crear una función Lambda en Python que se active automáticamente cuando un nuevo archivo JSON llegue al bucket de S3 (Trigger `s3:ObjectCreated:*`).

3. **Lógica de Mantenimiento Histórico en Lambda:**
   Programar la Lambda para que lea el JSON de S3 y lo inserte en **PostgreSQL** para mantener el histórico completo de los eventos de cada sensor.

4. **Desarrollar una API REST Unificada:**
   Construir una API (por ejemplo, con FastAPI) que exponga los siguientes endpoints:
   - `GET /sensors`: Lista todos los sensores existentes.
   - `POST /sensors`: Agrega un nuevo sensor.
   - `GET /sensor/{id}/current`: Obtiene el dato en tiempo real consultando **DynamoDB**.
   - `GET /sensor/{id}/recent`: Obtiene los últimos 10 eventos consultando **DynamoDB**.
   - `GET /sensor/{id}/history`: Consulta el histórico completo en **PostgreSQL**.

5. **Desplegar la API en ECS (AWS):**
   Contenedorizar la API con un `Dockerfile` y modificar la infraestructura (Terraform) para desplegarla en AWS Elastic Container Service (ECS), asegurando que corra en la nube en lugar de usar el `docker-compose.yml` local.

6. **Implementar Sistema de Alertas de Urgencia:**
   - Crear una `Regla 3` en AWS IoT Core que evalúe si la temperatura reportada supera un umbral crítico definido por ustedes (ej. `value > 35`).
   - La regla debe disparar una **Lambda de Alerta**, la cual enviará un mensaje con el formato de emergencia a una **Cola SQS**.
   - Configurar la cola SQS como *trigger* de una segunda **Lambda**, la cual consumirá el mensaje y escribirá un log de urgencia en **CloudWatch Logs**.

7. **Agregar el Nuevo Tipo de Sensor:**
   - Modificar el script `python_device/sensor_simulator.py` para soportar un nuevo tipo de sensor (diferente a temperatura y humedad). Este debe generar otro tipo de variable que los otros sensores.
   - Adicionar el contenedor correspondiente al nuevo sensor al archivo `docker-compose.yml`.
   - Registrar el nuevo sensor en el sistema utilizando el endpoint `POST /sensors`.
   - Verificar la correcta ingesta de datos probando los endpoints de lectura (`GET /sensor/{id}/current`, etc.) para obtener sus valores.

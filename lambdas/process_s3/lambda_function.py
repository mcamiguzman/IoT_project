import json
import boto3
import psycopg2
import os
from datetime import datetime

s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    Lambda para procesar archivos de sensores de S3 e insertar en PostgreSQL.
    Trigger: ObjectCreated en S3 bucket
    """
    try:
        # Obtener información del evento S3
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = event['Records'][0]['s3']['object']['key']
        
        print(f"Procesando archivo: s3://{bucket}/{key}")
        
        # Descargar archivo de S3
        response = s3_client.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        # Parsear JSON
        sensor_data = json.loads(content)
        
        # Conectar a PostgreSQL
        conn = psycopg2.connect(
            host=os.environ.get('DB_HOST'),
            database=os.environ.get('DB_NAME'),
            user=os.environ.get('DB_USER'),
            password=os.environ.get('DB_PASSWORD'),
            port=5432
        )
        
        cur = conn.cursor()
        
        # Insertar en tabla histórica
        for reading in sensor_data:
            cur.execute("""
                INSERT INTO sensor_history 
                (sensor_id, sensor_type, value, timestamp)
                VALUES (%s, %s, %s, %s)
            """, (
                reading['sensor_id'],
                reading['sensor_type'],
                reading['value'],
                reading['timestamp']
            ))
        
        conn.commit()
        cur.close()
        conn.close()
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Datos procesados correctamente',
                'records': len(sensor_data)
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

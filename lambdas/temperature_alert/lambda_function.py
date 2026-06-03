import json
import boto3
import os
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
sqs_client = boto3.client('sqs')

def lambda_handler(event, context):
    """
    Lambda para monitorear temperatura y enviar alertas cuando supera umbral.
    Trigger: DynamoDB stream cuando se inserta nuevo lectura de temperatura
    """
    try:
        TEMP_THRESHOLD = int(os.environ.get('TEMP_THRESHOLD', 30))
        SQS_QUEUE_URL = os.environ.get('SQS_QUEUE_URL')
        
        table = dynamodb.Table(os.environ.get('DYNAMODB_TABLE'))
        
        # Procesar registros del stream
        for record in event['Records']:
            if record['eventName'] != 'INSERT':
                continue
            
            new_image = record['dynamodb'].get('NewImage', {})
            
            # Verificar si es lectura de temperatura
            if new_image.get('sensor_type', {}).get('S') != 'temperature':
                continue
            
            sensor_id = new_image.get('sensor_id', {}).get('S')
            temperature = float(new_image.get('value', {}).get('N', 0))
            timestamp = new_image.get('timestamp', {}).get('N')
            
            # Evaluar umbral
            if temperature > TEMP_THRESHOLD:
                alert_message = {
                    'alert_type': 'HIGH_TEMPERATURE',
                    'sensor_id': sensor_id,
                    'temperature': temperature,
                    'threshold': TEMP_THRESHOLD,
                    'timestamp': datetime.now().isoformat(),
                    'severity': 'HIGH' if temperature > (TEMP_THRESHOLD + 5) else 'MEDIUM'
                }
                
                # Enviar a SQS
                sqs_client.send_message(
                    QueueUrl=SQS_QUEUE_URL,
                    MessageBody=json.dumps(alert_message)
                )
                
                print(f"Alerta enviada: {alert_message}")
        
        return {
            'statusCode': 200,
            'body': json.dumps('Alertas procesadas')
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

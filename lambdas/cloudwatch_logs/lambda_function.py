import json
import boto3
import base64
import os
from datetime import datetime

logs_client = boto3.client('logs')
sqs_client = boto3.client('sqs')

def lambda_handler(event, context):
    """
    Lambda para procesar mensajes de SQS y escribir logs en CloudWatch.
    Trigger: SQS Queue
    """
    try:
        LOG_GROUP = os.environ.get('LOG_GROUP', '/aws/iot/sensors/dev')
        LOG_STREAM = 'alerts'
        
        # Crear stream si no existe
        try:
            logs_client.create_log_stream(
                logGroupName=LOG_GROUP,
                logStreamName=LOG_STREAM
            )
        except logs_client.exceptions.ResourceAlreadyExistsException:
            pass
        
        # Procesar mensajes de SQS
        messages = []
        for record in event['Records']:
            body = json.loads(record['body'])
            
            # Construir mensaje de log
            log_message = {
                'timestamp': datetime.now().isoformat(),
                'alert_type': body.get('alert_type'),
                'sensor_id': body.get('sensor_id'),
                'temperature': body.get('temperature'),
                'threshold': body.get('threshold'),
                'severity': body.get('severity', 'MEDIUM')
            }
            
            messages.append({
                'timestamp': int(datetime.now().timestamp() * 1000),
                'message': json.dumps(log_message)
            })
            
            print(f"Mensaje procesado: {log_message}")
        
        # Escribir en CloudWatch Logs
        if messages:
            logs_client.put_log_events(
                logGroupName=LOG_GROUP,
                logStreamName=LOG_STREAM,
                logEvents=messages
            )
        
        # Eliminar mensajes de SQS
        for record in event['Records']:
            sqs_client.delete_message(
                QueueUrl=os.environ.get('SQS_QUEUE_URL'),
                ReceiptHandle=record['receiptHandle']
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Procesados {len(messages)} registros')
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

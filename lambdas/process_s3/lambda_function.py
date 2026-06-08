import json
import boto3
import os
import time
from datetime import datetime
import io

s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    Lambda para procesar archivos de sensores de S3 e insertar en DynamoDB.
    También exporta datos a S3 en formato Parquet para análisis con Athena.
    Trigger: ObjectCreated en S3 bucket
    """
    try:
        dynamodb_table_name = os.environ.get('DYNAMODB_TABLE')
        s3_bucket_archive = os.environ.get('S3_BUCKET')
        
        if not dynamodb_table_name or not s3_bucket_archive:
            raise ValueError("DYNAMODB_TABLE y S3_BUCKET environment variables requeridas")
        
        table = dynamodb.Table(dynamodb_table_name)
        
        # Obtener información del evento S3
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = event['Records'][0]['s3']['object']['key']
        
        print(f"Procesando archivo: s3://{bucket}/{key}")
        
        # Descargar archivo de S3
        response = s3_client.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        # Parsear JSON
        sensor_data = json.loads(content)
        
        # Validar que es una lista
        if not isinstance(sensor_data, list):
            sensor_data = [sensor_data]
        
        # Insertar en DynamoDB
        inserted_count = 0
        for reading in sensor_data:
            try:
                # Asegurar que timestamp es numérico (epoch)
                if isinstance(reading.get('timestamp'), str):
                    # Intentar parsear como ISO datetime
                    dt = datetime.fromisoformat(reading['timestamp'].replace('Z', '+00:00'))
                    timestamp = int(dt.timestamp())
                else:
                    timestamp = int(reading.get('timestamp', time.time()))
                
                item = {
                    'sensor_id': reading.get('sensor_id', 'unknown'),
                    'timestamp': timestamp,
                    'sensor_type': reading.get('sensor_type', 'unknown'),
                    'value': float(reading.get('value', 0)),
                    'unit': reading.get('unit', ''),
                    'raw_data': json.dumps(reading)
                }
                
                # Opcional: agregar TTL (30 días) para auto-cleanup
                item['expiration'] = int(time.time()) + (30 * 24 * 60 * 60)
                
                table.put_item(Item=item)
                inserted_count += 1
                print(f"Insertado en DynamoDB: sensor_id={item['sensor_id']}, timestamp={timestamp}")
                
            except Exception as e:
                print(f"Error insertando item en DynamoDB: {str(e)}, item: {reading}")
        
        # Exportar a S3 en formato Parquet para Athena (opcional pero recomendado)
        try:
            import pyarrow.parquet as pq
            import pyarrow as pa
            
            if sensor_data:
                # Convertir a formato Parquet
                table_schema = pa.schema([
                    ('sensor_id', pa.string()),
                    ('timestamp', pa.int64()),
                    ('sensor_type', pa.string()),
                    ('value', pa.float64()),
                    ('unit', pa.string())
                ])
                
                records = []
                for reading in sensor_data:
                    if isinstance(reading.get('timestamp'), str):
                        dt = datetime.fromisoformat(reading['timestamp'].replace('Z', '+00:00'))
                        timestamp = int(dt.timestamp())
                    else:
                        timestamp = int(reading.get('timestamp', time.time()))
                    
                    records.append({
                        'sensor_id': reading.get('sensor_id', 'unknown'),
                        'timestamp': timestamp,
                        'sensor_type': reading.get('sensor_type', 'unknown'),
                        'value': float(reading.get('value', 0)),
                        'unit': reading.get('unit', '')
                    })
                
                table_pa = pa.Table.from_pylist(records, schema=table_schema)
                
                # Generar nombre de archivo Parquet
                timestamp_str = datetime.now().strftime('%Y/%m/%d/%H%M%S')
                parquet_key = f"parquet/{timestamp_str}/data.parquet"
                
                # Guardar en S3
                buffer = io.BytesIO()
                pq.write_table(table_pa, buffer)
                buffer.seek(0)
                
                s3_client.put_object(
                    Bucket=s3_bucket_archive,
                    Key=parquet_key,
                    Body=buffer.getvalue(),
                    ContentType='application/octet-stream'
                )
                print(f"Archivo Parquet guardado: s3://{s3_bucket_archive}/{parquet_key}")
        except ImportError:
            print("pyarrow no disponible, saltando exportación Parquet")
        except Exception as e:
            print(f"Advertencia: No se pudo exportar a Parquet: {str(e)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Datos procesados correctamente',
                'records_inserted': inserted_count,
                'total_records': len(sensor_data)
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

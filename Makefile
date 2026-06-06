.PHONY: up down tf-init tf-apply deploy clean destroy build-lambdas tf-import tf-import-existing aws-logs logs tf-logs run-gateway

AWS_REGION ?= us-east-1

up:
	docker compose up -d --build

down:
	docker compose down

clean:
	docker compose down -v
	docker system prune -f
	rm -rf terraform/.terraform
	rm -rf terraform/*.tfstate*
	rm -rf terraform/.lock.hcl
	rm -rf lambdas/*.zip
	find . -type d -name __pycache__ -exec rm -rf {} +
	find . -type f -name "*.pyc" -delete
	@echo "✓ Limpieza completada"

build-lambdas:
	@echo "📦 Instalando dependencias Lambda..."
	pip install -r lambdas/process_s3/requirements.txt -t lambdas/process_s3/lib
	@echo "✓ Dependencias instaladas (Terraform empaquetará automáticamente)"

tf-init:
	cd terraform && terraform init

tf-apply: build-lambdas
	cd terraform && terraform apply -auto-approve

tf-destroy:
	cd terraform && terraform destroy -auto-approve
	@echo "✓ Recursos AWS destruidos"

deploy: tf-init tf-apply up
	@echo "✓ Despliegue completado"
	@echo "✓ Despliegue completado"

destroy: down tf-destroy clean
	@echo "✓ Proyecto completamente destruido"

# Importa recursos huérfanos comunes (úsalo si un apply falla con ResourceAlreadyExistsException)
# Reemplaza los UUIDs/IDs por los que AWS devuelve en el mensaje de error.
tf-import:
	cd terraform && \
		terraform import aws_cloudwatch_log_group.iot_logs /aws/iot/sensors/dev || true
	@echo "✓ Si el log group ya estaba en el estado, el import se ignoró. Re-ejecuta 'make deploy'."

# Importar recursos ya existentes en la cuenta para evitar conflictos al aplicar
# cuando Terraform no tiene el estado presente pero el recurso ya existe.
tf-import-existing:
	@cd terraform && terraform import aws_cloudwatch_log_group.iot_logs /aws/iot/sensors/dev || true
	@cd terraform && terraform import aws_dynamodb_table.sensor_data sensor-data-dev || true
	@cd terraform && terraform import aws_s3_bucket.sensor_archive iot-sensor-archive-dev-665031542744 || true
	@cd terraform && terraform import aws_sqs_queue.sensor_queue iot-sensor-queue-dev || true
	@cd terraform && terraform import aws_lambda_function.process_s3 iot-process-s3-dev || true
	@cd terraform && terraform import aws_lambda_function.temperature_alert iot-temperature-alert-dev || true
	@cd terraform && terraform import aws_lambda_function.cloudwatch_logs iot-cloudwatch-logs-dev || true
	@cd terraform && terraform import aws_iot_thing.sensor sensor-thing-dev || true
	@cd terraform && terraform import aws_iot_policy.device_policy iot-device-policy-dev || true
	@cd terraform && terraform import aws_iot_topic_rule.to_sqs iot_rule_to_sqs_dev || true
	@UUID=$$(aws sts get-caller-identity --query Account --output text --region $(AWS_REGION) $(if $(PROFILE),--profile $(PROFILE),)); \
	QUEUE_ARN=$$(printf "arn:aws:sqs:%s:%s:iot-sensor-queue-dev" "$(AWS_REGION)" "$$UUID"); \
	MAPPING_ID=$$(aws lambda list-event-source-mappings --function-name iot-cloudwatch-logs-dev --event-source-arn "$$QUEUE_ARN" --query 'EventSourceMappings[0].UUID' --output text --region $(AWS_REGION) $(if $(PROFILE),--profile $(PROFILE),)); \
	if [ "$$MAPPING_ID" != "None" ] && [ -n "$$MAPPING_ID" ]; then \
		cd terraform && terraform import aws_lambda_event_source_mapping.sqs_to_lambda "$$MAPPING_ID" || true; \
	else \
		echo "Aviso: no se encontró Event Source Mapping para iot-cloudwatch-logs-dev"; \
	fi
	@echo "✓ Intento de importación completado. Revisa errores y vuelve a ejecutar 'make deploy'."

aws-logs:
	@echo "Siguiendo CloudWatch Logs (use LOG_GROUP, opcional PROFILE y AWS_REGION)."
	@if [ -z "$(LOG_GROUP)" ]; then \
		echo "ERROR: define LOG_GROUP. Ej: LOG_GROUP=/aws/iot/sensors/dev"; exit 1; \
	fi
	@aws logs tail "$(LOG_GROUP)" --follow --region $(AWS_REGION) $(if $(PROFILE),--profile $(PROFILE),)

logs: 
	docker compose logs -f

tf-logs: 
	aws-logs

run-gateway:
	@echo "Iniciando gateway: resolviendo AWS IoT endpoint..."
	@EP=""; \
	if command -v terraform >/dev/null 2>&1; then \
		EP=$$(cd terraform && terraform output -raw iot_endpoint 2>/dev/null || true); \
	fi; \
	if [ -z "$$EP" ]; then \
		EP=$$(aws iot describe-endpoint --endpoint-type iot:Data-ATS --query endpointAddress --output text --region $(AWS_REGION) $(if $(PROFILE),--profile $(PROFILE),) 2>/dev/null || true); \
	fi; \
	if [ -z "$$EP" ]; then \
		echo "ERROR: no se pudo determinar AWS IoT endpoint (ni terraform output ni aws cli)."; exit 1; \
	fi; \
	@echo "Usando endpoint: $$EP"; \
	AWS_IOT_ENDPOINT=$$EP AWS_REGION=$(AWS_REGION) python gateway/publisher.py

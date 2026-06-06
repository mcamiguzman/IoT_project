.PHONY: up down tf-init tf-apply deploy clean destroy build-lambdas tf-import run-gateway

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

aws-logs:
	@echo "Siguiendo CloudWatch Logs (use LOG_GROUP, opcional PROFILE y AWS_REGION)."
	@if [ -z "$(LOG_GROUP)" ]; then \
		echo "ERROR: define LOG_GROUP. Ej: LOG_GROUP=/aws/iot/sensors/dev"; exit 1; \
	fi
	@aws logs tail "$(LOG_GROUP)" --follow --region $(AWS_REGION) $(if $(PROFILE),--profile $(PROFILE),)

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

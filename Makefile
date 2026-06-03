.PHONY: up down tf-init tf-apply deploy clean destroy build-lambdas

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

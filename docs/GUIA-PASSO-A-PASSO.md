# Guia de Execucao e Validacao

> Autor: Christopher Amaral

---

## O que foi executado

```
[1] Helm Chart — lint + deploy + upgrade em cluster Kind local
[2] Terraform — validate + apply simulado (moto server) + provisionamento real na AWS
[3] GitHub Actions — pipeline CI/CD com lint e deploy
[4] Validacao — pod rodando na EC2 com mensagem customizada
```

---

## 1. Validacao do Helm Chart (Kind)

```bash
# Lint
helm lint ./charts/webapp --strict
# Resultado: 1 chart(s) linted, 0 chart(s) failed

# Cluster Kind
kind create cluster --name teste --wait 3m

# Deploy
helm install webapp ./charts/webapp \
  --set customMessage="Hello World da AsapTech - Teste local"

# Verificacao
kubectl get pods -l app.kubernetes.io/name=webapp    # 1/1 Running
kubectl get svc webapp                        # ClusterIP 80/TCP
helm list                                            # STATUS: deployed

# Upgrade (simula CI/CD)
helm upgrade webapp ./charts/webapp \
  --set customMessage="Hello World da AsapTech - Deploy via CI/CD (Commit: abc1234)" \
  --force --wait
helm history webapp                                  # 2 revisoes

# Teste HTTP
kubectl port-forward svc/webapp 8080:80 &
curl -s http://localhost:8080                         # HTML com mensagem customizada
```

---

## 2. Validacao do Terraform (local)

```bash
cd terraform

# Validacao estatica
terraform init -backend=false
terraform validate                                   # Success! The configuration is valid.
terraform fmt -check -recursive                      # Codigo formatado

# Simulacao com moto server (mock AWS via Docker)
docker run -d --name moto -p 5000:5000 motoserver/moto:latest

# Apply dos modulos simulados
terraform apply -var-file=inventories/dev/terraform.tfvars -target=module.storage -auto-approve
# Resultado: 5 resources created (S3 + versioning + encryption + public access block + DynamoDB)

terraform apply -var-file=inventories/dev/terraform.tfvars -target=module.networking -auto-approve
# Resultado: VPC + Subnet + IGW + Route Table

terraform apply -var-file=inventories/dev/terraform.tfvars -target=module.security -auto-approve
# Resultado: Security Groups com dynamic blocks

terraform apply -var-file=inventories/dev/terraform.tfvars -target=module.iam -auto-approve
# Resultado: IAM Roles + OIDC Provider
```

---

## 3. Provisionamento na AWS

### 3.1. Configuracao

```bash
aws configure
# Region: us-east-1

aws sts get-caller-identity
# Confirmacao de acesso a conta
```

### 3.2. Setup automatizado (um comando)

```bash
cd terraform
chmod +x setup.sh
./setup.sh dev
```

O script executa automaticamente:
1. Gera `backend.hcl` com bucket unico (inclui AWS account ID)
2. Cria S3 + DynamoDB com backend local
3. Migra state para S3
4. Provisiona toda a infraestrutura
5. Exporta chave SSH para `terraform/ssh-key-dev.pem`

### 3.3. Setup manual (alternativa)

```bash
cd terraform

# Gerar backend.hcl (substituir ACCOUNT_ID pelo seu)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
sed "s/<account_id>/$ACCOUNT_ID/; s/<project_name>/projeto-teste/" \
  inventories/dev/backend.hcl.example > inventories/dev/backend.hcl

# Bootstrap
mv backend.tf backend.tf.bak
terraform init
terraform apply -var-file=inventories/dev/terraform.tfvars -target=module.storage

# Migrar state para S3
mv backend.tf.bak backend.tf
terraform init -backend-config=inventories/dev/backend.hcl

# Provisionamento completo
terraform apply -var-file=inventories/dev/terraform.tfvars

# Exportar chave SSH
terraform output -raw ssh_private_key > ssh-key-dev.pem
chmod 600 ssh-key-dev.pem
```

### 3.4. Outputs

Apos o setup (automatico ou manual):

```bash
terraform output ec2_public_ip
terraform output ec2_instance_id
terraform output github_actions_role_arn
```

---

## 4. Validacao na EC2

```bash
# SSH (chave exportada pelo setup.sh)
ssh -i terraform/ssh-key-dev.pem ubuntu@<EC2_PUBLIC_IP>

# Cluster
kubectl get nodes                                     # Ready
kind get clusters                                     # dev-cluster

# Deploy manual
helm upgrade --install webapp /tmp/webapp-chart \
  --set customMessage="Hello World da AsapTech - Deploy manual" \
  --force --wait --timeout 120s

# Verificacao
kubectl get pods -l app.kubernetes.io/name=webapp     # 1/1 Running
kubectl port-forward svc/webapp 8080:80 &
curl -s http://localhost:8080                          # HTML com mensagem
```

---

## 5. GitHub Actions — Pipeline CI/CD

### 5.1. GitHub Secrets

| Secret | Valor |
|--------|-------|
| `AWS_ROLE_ARN` | `terraform output github_actions_role_arn` |
| `EC2_INSTANCE_ID` | `terraform output ec2_instance_id` |
| `EC2_SSH_HOST` | `terraform output ec2_public_ip` |
| `EC2_SSH_PRIVATE_KEY` | `terraform output -raw ssh_private_key` |

### 5.2. Trigger

```bash
# Qualquer push em charts/** na main dispara o pipeline
git add .
git commit -m "chore: trigger pipeline"
git push origin main
```

### 5.3. Resultado

- **Job Lint**: helm lint --strict + helm template (default + prod values)
- **Job Deploy**: OIDC auth + SSH + helm upgrade --install --force --wait + smoke test

---

## 6. Cleanup

```bash
cd terraform
chmod +x teardown.sh
./teardown.sh dev
```

---

## Resumo

| Item | Status |
|------|--------|
| Helm chart corrigido e funcional | Feito |
| Mensagem customizada com commit SHA | Feito |
| Terraform com modulos reusaveis | Feito |
| Inventories por ambiente (dev/homol/prod) | Feito |
| Provisionamento real na AWS | Feito |
| GitHub Actions CI/CD | Feito |
| Pod rodando na EC2 | Feito |
| Documentacao completa | Feito |

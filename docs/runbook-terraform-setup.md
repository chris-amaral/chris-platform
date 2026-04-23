# Runbook: Provisionamento de Infraestrutura com Terraform

> Ultima atualizacao: 2026-04 | Autor: Christopher Amaral

---

## TL;DR

Provisionamento completo da infraestrutura AWS (VPC, EC2 com Kind, S3, IAM com OIDC) utilizando Terraform com modulos reusaveis e inventories por ambiente. O state e armazenado remotamente em S3 com DynamoDB para locking.

---

## Pre-requisitos

| Ferramenta | Versao minima | Verificacao |
|------------|---------------|-------------|
| Terraform | >= 1.5.0 | `terraform version` |
| AWS CLI | v2 | `aws --version` |
| Credenciais AWS | IAM Admin | `aws sts get-caller-identity` |

> **Ponto importante**: Nas minhas experiênciass anteriores, trabalhei com Terraform 1.6+ e modules versionados em registry privado. Aqui optei por modules locais para simplificar, mas a estrutura e a mesma que usaria em produção com remote modules.

---

## Arquitetura dos Modulos

```
terraform/
├── setup.sh             # Bootstrap automatizado (um comando)
├── teardown.sh          # Destruir recursos
├── main.tf              # Orquestra todos os modulos (dependency injection)
├── variables.tf         # Variaveis de entrada do root
├── outputs.tf           # Outputs consolidados de todos os modulos
├── providers.tf         # Provider AWS com default_tags
├── backend.tf           # Backend parcial (S3) — preenchido via backend.hcl
│
├── inventories/         # Um diretorio por ambiente
│   ├── dev/
│   │   ├── terraform.tfvars    # Variaveis especificas de dev
│   │   └── backend.hcl.example # Template (gerado pelo setup.sh)
│   ├── homol/
│   └── prod/
│
└── modules/             # Modulos reusaveis e independentes
    ├── networking/      # VPC, Subnet, IGW, Route Table
    ├── compute/         # EC2, Key Pair, Elastic IP, User Data
    ├── security/        # Security Groups com dynamic blocks
    ├── storage/         # S3 (state com account ID unico) + DynamoDB (lock)
    └── iam/             # IAM Roles, Instance Profile, OIDC Provider
```

### Fluxo de dependencias entre modulos

```
networking (vpc_id, subnet_id)
     |
     v
security (sg_id)  <-- recebe vpc_id do networking
     |
     v
compute           <-- recebe subnet_id, sg_id, instance_profile
     ^
     |
iam (instance_profile, github_role_arn)  <-- independente
     ^
     |
storage (s3_bucket, dynamodb_table)      <-- independente
```

> **Ponto importante**: Esse pattern de dependency injection e o que costumo usar para compor infraestrutura de micro-servicos. Cada modulo e 100% independente — posso pegar o modulo `networking/` e usar em outro projeto sem alterar uma linha. Em projetos anteriores, os modulos ficavam em repositorios separados com versionamento semantico — aqui mantive local para simplificar a entrega.

---

## Procedimento

### 1. Personalizar variaveis (unico arquivo que precisa editar)

```bash
cd terraform
vi inventories/dev/terraform.tfvars
```

```hcl
project_name       = "meu-projeto"          # Prefixo de todos os recursos
owner              = "seu.nome"             # Tag Owner
github_repository  = "seu-user/seu-repo"    # OIDC trust policy
allowed_ssh_cidrs  = ["0.0.0.0/0"]          # Ou seu IP: ["SEU_IP/32"]
```

### 2. Setup automatizado (recomendado)

```bash
chmod +x setup.sh
./setup.sh dev
```

O script `setup.sh` executa automaticamente:

| Passo | O que faz |
|-------|-----------|
| 1 | Le `terraform.tfvars` e obtem AWS Account ID |
| 2 | Gera `backend.hcl` com bucket unico (`projeto-tfstate-<account_id>`) |
| 3 | Cria S3 + DynamoDB com backend local |
| 4 | Migra state para S3 |
| 5 | Provisiona toda a infraestrutura |
| 6 | Exporta chave SSH para `ssh-key-dev.pem` |

Ao final, exibe:
- IP da EC2 (Elastic IP fixo)
- Instance ID
- Role ARN para GitHub Actions
- Todos os GitHub Secrets necessarios
- Comando SSH pronto para copiar

> **Ponto importante**: O `setup.sh` resolve o classico "chicken and egg problem" do Terraform (precisa do S3 para state, mas o S3 e criado pelo Terraform). Em experiências anteriores, automatizei esse bootstrap com scripts similares. Aqui, basta rodar um comando.

### 3. Setup manual (alternativa)

Se preferir executar passo a passo:

```bash
# Gerar backend.hcl
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
PROJECT=$(grep 'project_name' inventories/dev/terraform.tfvars | sed 's/.*= *"//' | sed 's/".*//')
cat > inventories/dev/backend.hcl <<EOF
bucket         = "${PROJECT}-tfstate-${ACCOUNT_ID}"
key            = "dev/terraform.tfstate"
region         = "us-east-1"
encrypt        = true
dynamodb_table = "${PROJECT}-tfstate-lock"
EOF

# Bootstrap S3 + DynamoDB
mv backend.tf backend.tf.bak
terraform init
terraform apply -var-file=inventories/dev/terraform.tfvars -target=module.storage

# Migrar state para S3
mv backend.tf.bak backend.tf
terraform init -backend-config=inventories/dev/backend.hcl -migrate-state -force-copy

# Provisionamento completo
terraform apply -var-file=inventories/dev/terraform.tfvars

# Exportar chave SSH
terraform output -raw ssh_private_key > ssh-key-dev.pem
chmod 600 ssh-key-dev.pem
```

### 4. Trocar de ambiente

```bash
./setup.sh homol    # ou: ./setup.sh prod
```

> **Ponto importante**: Cada ambiente gera seu proprio `backend.hcl` com state isolado no S3. não ha risco de sobrescrever o state de outro ambiente.

---

## Variaveis do Inventory

| Variavel | Descricao | Dev | Homol | Prod |
|----------|-----------|-----|-------|------|
| `aws_region` | Regiao AWS | us-east-1 | us-east-1 | us-east-1 |
| `project_name` | Prefixo dos recursos | projeto-teste | projeto-teste | projeto-teste |
| `environment` | Ambiente | dev | homol | prod |
| `squad` | Squad responsavel | projeto-teste | projeto-teste | projeto-teste |
| `owner` | Responsavel (tag) | christopher.amaral | christopher.amaral | christopher.amaral |
| `instance_type` | Tipo EC2 | m7i-flex.large | m7i-flex.large | m7i-flex.xlarge |
| `vpc_cidr` | CIDR da VPC | 10.10.0.0/16 | 10.20.0.0/16 | 10.30.0.0/16 |
| `enable_nodeport_access` | NodePort no SG | true | false | false |

> **Ponto importante**: Cada ambiente tem um CIDR diferente (10.10, 10.20, 10.30). Isso e proposital — se um dia precisar fazer VPC Peering entre ambientes, não vai ter overlap de rede. Ja vivenciei situacoes onde dois ambientes com o mesmo CIDR impediram completamente o peering. Desde entao, sempre separo os ranges.

---

## Verificacao

```bash
# State atual
terraform show

# Listar recursos gerenciados
terraform state list

# Outputs
terraform output

# Na EC2: verificar bootstrap
ssh -i key ubuntu@<IP>
cat /var/log/bootstrap-status     # SUCCESS
cat /var/log/bootstrap-cluster.log # Log completo
kubectl get nodes                  # 1 node Ready
```

---

## Troubleshooting

| Problema | Comando de diagnostico | Solucao |
|----------|----------------------|---------|
| `terraform init` falha no backend | `aws s3 ls` | O bucket não existe. Execute o bootstrap (passo 2) |
| State lock preso | `terraform force-unlock <LOCK_ID>` | Alguem interrompeu um apply. Force unlock |
| EC2 não responde SSH | `telnet <IP> 22` | Verifique `allowed_ssh_cidrs` no tfvars e SG na console AWS |
| Kind não subiu | `cat /var/log/bootstrap-cluster.log` | Veja o log na EC2. Pode ser falta de memoria |
| AMI não encontrada | `aws ec2 describe-images --owners 099720109477` | Verifique regiao e filtros |
| Permissao negada na AWS | `aws sts get-caller-identity` | Verifique credenciais e policies IAM |

> **Ponto importante**: Pelos anos que trabalho com Terraform, 90% dos problemas que encontrei se resumem a: (1) credenciais erradas, (2) state lock preso, (3) dependencia circular entre resources. Se tiver duvida, `terraform state list` e seu melhor amigo.

---

## Destruicao

```bash
# Via script
chmod +x teardown.sh
./teardown.sh dev

# Ou manualmente
terraform destroy -var-file=inventories/dev/terraform.tfvars
```

---

## Links Uteis

- [Terraform S3 Backend](https://developer.hashicorp.com/terraform/language/settings/backends/s3)
- [Terraform Modules](https://developer.hashicorp.com/terraform/language/modules)
- [AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Kind Quick Start](https://kind.sigs.k8s.io/docs/user/quick-start/)

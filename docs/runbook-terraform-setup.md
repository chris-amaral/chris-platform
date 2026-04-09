# Runbook: Provisionamento de Infraestrutura com Terraform

> Ultima atualizacao: 2025-04 | Autor: Christopher Amaral

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
├── main.tf              # Orquestra todos os modulos (dependency injection)
├── variables.tf         # Variaveis de entrada do root
├── outputs.tf           # Outputs consolidados de todos os modulos
├── providers.tf         # Provider AWS com default_tags
├── backend.tf           # Backend parcial (S3) — preenchido via backend.hcl
│
├── inventories/         # Um diretorio por ambiente
│   ├── dev/
│   │   ├── terraform.tfvars    # Variaveis especificas de dev
│   │   └── backend.hcl         # Config do backend de dev
│   ├── homol/
│   └── prod/
│
└── modules/             # Modulos reusaveis e independentes
    ├── networking/      # VPC, Subnet, IGW, Route Table
    ├── compute/         # EC2, Key Pair, User Data (bootstrap)
    ├── security/        # Security Groups com dynamic blocks
    ├── storage/         # S3 (state) + DynamoDB (lock)
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

### 1. Configurar as variaveis do ambiente

```bash
cd terraform

# Edite o inventory do ambiente desejado
# IMPORTANTE: preencha allowed_ssh_cidrs com seu IP publico
vi inventories/dev/terraform.tfvars
```

Encontre seu IP publico:
```bash
curl -s https://ifconfig.me
# Coloque no tfvars: allowed_ssh_cidrs = ["SEU_IP/32"]
```

### 2. Bootstrap — criar S3 e DynamoDB (primeira vez)

> **Ponto importante**: Esse e o classico "chicken and egg problem" do Terraform — você precisa do S3 para guardar o state, mas o S3 e criado pelo Terraform. A solucao e criar com backend local primeiro e depois migrar. Em experiênciass anteriores, automatizei isso com um script de bootstrap dedicado.

```bash
# Desabilite temporariamente o backend remoto
mv backend.tf backend.tf.bak

# Init com backend local
terraform init

# Crie somente o modulo de storage
terraform apply \
  -var-file=inventories/dev/terraform.tfvars \
  -target=module.storage

# Confirme com "yes"
```

### 3. Migrar state para S3

```bash
# Restaure o backend
mv backend.tf.bak backend.tf

# Init com backend remoto
terraform init -backend-config=inventories/dev/backend.hcl

# Terraform vai perguntar se quer migrar: responda "yes"
```

### 4. Provisionamento completo

```bash
# SEMPRE faca plan antes de apply
terraform plan \
  -var-file=inventories/dev/terraform.tfvars \
  -out=dev.tfplan

# Revise o plan com atencao
# Apply
terraform apply dev.tfplan
```

> **Ponto importante**: NUNCA faco `terraform apply` sem `plan` salvo em arquivo. Isso evita que mudancas inesperadas sejam aplicadas se alguem alterar o codigo entre o plan e o apply. Nas equipes que participei, essa era uma regra inegociavel — e uma pratica que recomendo para qualquer ambiente.

### 5. Exportar outputs

```bash
# Ver todos os outputs
terraform output

# Salvar chave SSH (se auto-gerada)
terraform output -raw ssh_private_key > ~/.ssh/projeto-christopher-key
chmod 600 ~/.ssh/projeto-christopher-key

# Testar conexao
ssh -i ~/.ssh/projeto-christopher-key ubuntu@$(terraform output -raw ec2_public_ip)
```

### 6. Trocar de ambiente

```bash
# Para homologacao
terraform init -backend-config=inventories/homol/backend.hcl -reconfigure
terraform plan -var-file=inventories/homol/terraform.tfvars

# Para produção
terraform init -backend-config=inventories/prod/backend.hcl -reconfigure
terraform plan -var-file=inventories/prod/terraform.tfvars
```

> **Ponto importante**: O `-reconfigure` e essencial quando troca de backend. Sem ele, o Terraform tenta manter o state anterior e da conflito. Em projetos passados, eu abstraia isso com um Makefile: `make plan ENV=dev` — facilita demais o dia a dia.

---

## Variaveis do Inventory

| Variavel | Descricao | Dev | Homol | Prod |
|----------|-----------|-----|-------|------|
| `aws_region` | Regiao AWS | us-east-1 | us-east-1 | us-east-1 |
| `project_name` | Prefixo dos recursos | projeto-christopher | projeto-christopher | projeto-christopher |
| `environment` | Ambiente | dev | homol | prod |
| `squad` | Squad responsavel | projeto-christopher | projeto-christopher | projeto-christopher |
| `instance_type` | Tipo EC2 | t3.medium | t3.medium | t3.large |
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
# CUIDADO: destroi toda a infra do ambiente
terraform destroy -var-file=inventories/dev/terraform.tfvars

# O bucket S3 tem prevent_destroy — remova manualmente se necessario:
# aws s3 rb s3://projeto-christopher-tfstate --force
```

---

## Links Uteis

- [Terraform S3 Backend](https://developer.hashicorp.com/terraform/language/settings/backends/s3)
- [Terraform Modules](https://developer.hashicorp.com/terraform/language/modules)
- [AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Kind Quick Start](https://kind.sigs.k8s.io/docs/user/quick-start/)

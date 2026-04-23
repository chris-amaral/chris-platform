# DevOps-CICD

Infraestrutura como Codigo (IaC) e automacao de deploy para cluster Kubernetes na AWS.

Terraform modular provisiona EC2 com Kind cluster, Helm chart generico deploya aplicacoes, e GitHub Actions automatiza o ciclo completo com autenticacao OIDC (zero credenciais estaticas).

---

## Stack

| Ferramenta | Funcao |
|------------|--------|
| **Terraform** | Provisionamento AWS com modulos reusaveis, inventories por ambiente, Elastic IP |
| **Helm** | Chart generico `webapp` para deploy de qualquer aplicacao web |
| **Kind** | Cluster Kubernetes local (Docker-based) na EC2 |
| **GitHub Actions** | Pipeline CI/CD com autenticacao OIDC e suporte GitFlow |

---

## Estrutura do Projeto

```
.
├── .github/workflows/
│   └── ci-deploy-k8s.yml                # Pipeline CI/CD (lint + deploy)
│
├── charts/webapp/                        # Helm Chart generico
│   ├── Chart.yaml
│   ├── values.yaml                       # Valores padrao (dev)
│   ├── values-production.yaml            # Override para producao
│   └── templates/                        # Manifests K8s parametrizados
│
├── terraform/
│   ├── setup.sh                          # Bootstrap automatizado (um comando)
│   ├── teardown.sh                       # Destruir recursos
│   ├── main.tf                           # Orquestracao dos modulos
│   ├── inventories/                      # tfvars + backend.hcl.example por ambiente
│   │   ├── dev/
│   │   ├── homol/
│   │   └── prod/
│   └── modules/                          # Modulos reusaveis
│       ├── networking/                   # VPC, Subnet, IGW, Routes
│       ├── compute/                      # EC2, Key Pair, Elastic IP, bootstrap
│       ├── security/                     # Security Groups (dynamic blocks)
│       ├── storage/                      # S3 State + DynamoDB Lock (account ID unico)
│       └── iam/                          # IAM Roles, OIDC Provider
│
└── docs/                                 # Runbooks, Playbooks, ADR, Security
```

---

## Quick Start

### Pre-requisitos

- AWS CLI configurado (`aws configure`)
- Terraform >= 1.5.0
- Bash (Linux/macOS/WSL)

### Setup completo (um comando)

```bash
cd terraform
chmod +x setup.sh
./setup.sh dev
```

O script `setup.sh` automatiza todo o bootstrap:

1. Gera `backend.hcl` com nome de bucket unico (inclui AWS account ID)
2. Cria S3 + DynamoDB para state remoto
3. Migra o state para S3
4. Provisiona toda a infraestrutura (VPC, EC2, IAM, Security Groups)
5. Exporta a chave SSH para `terraform/ssh-key-dev.pem`

Ao final, exibe IP da EC2, chave SSH e todos os GitHub Secrets necessarios.

### Personalizar

Edite `terraform/inventories/dev/terraform.tfvars` antes de rodar o setup:

```hcl
project_name       = "meu-projeto"        # Prefixo dos recursos
environment        = "dev"
instance_type      = "m7i-flex.large"      # Free Tier eligible, 8GB RAM
github_repository  = "meu-user/meu-repo"  # Para OIDC trust policy
```

### Trocar de ambiente

```bash
./setup.sh homol    # ou: ./setup.sh prod
```

### Destruir recursos

```bash
chmod +x teardown.sh
./teardown.sh dev
```

> Detalhes em: [docs/runbook-terraform-setup.md](docs/runbook-terraform-setup.md)

---

## Como o GitHub Actions se Autentica

O pipeline **nao usa** credenciais estaticas. Toda autenticacao e via **OIDC (OpenID Connect)**:

```
GitHub Actions                       AWS STS
     |                                  |
     |-- 1. JWT assinado (repo+branch)->|
     |                                  |-- 2. Valida trust policy
     |<-- 3. Credenciais temporarias ---|
     |      (expiram em ~1h)            |
```

Apos autenticar na AWS, o pipeline conecta na EC2 via SSH, copia o chart com `scp` e executa `helm upgrade --install --force --wait`.

| Secret | Descricao |
|--------|-----------|
| `AWS_ROLE_ARN` | ARN da IAM Role OIDC |
| `EC2_INSTANCE_ID` | ID da EC2 |
| `EC2_SSH_HOST` | IP publico da EC2 |
| `EC2_SSH_PRIVATE_KEY` | Chave SSH privada |

> Detalhes em: [docs/runbook-ci-cd-pipeline.md](docs/runbook-ci-cd-pipeline.md)

---

## Validar que o Pod esta Rodando

```bash
# Na EC2
kubectl get pods -l app.kubernetes.io/name=webapp    # 1/1 Running
kubectl get svc webapp                                # ClusterIP 80/TCP
helm list                                            # STATUS: deployed

# Testar resposta HTTP
kubectl port-forward svc/webapp 8080:80 &
curl -s http://localhost:8080                         # HTML com commit SHA
```

> Detalhes em: [docs/runbook-validacao-deploy.md](docs/runbook-validacao-deploy.md)

---

## Evidencias

### Validacao Local (Kind)

Validacao completa do chart em cluster Kind — lint, deploy (REVISION 1 e 2), pods Running, Service ClusterIP e mensagem customizada:

![Validacao Helm Chart - Kind Cluster](docs/images/validacao-helm-chart.png)

### Terraform Validate

![Terraform Validate](docs/images/terraform-validate.png)

### Provisionamento AWS

![Terraform Apply](docs/images/terraform-apply.png)

### Pod Rodando na EC2

![Pod na EC2](docs/images/pod-ec2.png)

### Pipeline GitHub Actions

![GitHub Actions](docs/images/github-actions.png)

---

## Documentacao

| Tipo | Documento | Conteudo |
|------|-----------|----------|
| **Runbook** | [Terraform Setup](docs/runbook-terraform-setup.md) | Bootstrap, inventories, modulos, state |
| **Runbook** | [Helm Chart](docs/runbook-helm-chart.md) | Correcoes do chart original, parametros |
| **Runbook** | [CI/CD Pipeline](docs/runbook-ci-cd-pipeline.md) | Fluxo, OIDC, Secrets, mensagem customizada |
| **Runbook** | [Validacao de Deploy](docs/runbook-validacao-deploy.md) | Checklist pos-deploy |
| **Playbook** | [Incident Response](docs/playbook-incident-response.md) | Pod crashando, cluster down, deploy falhou |
| **Playbook** | [Rollback](docs/playbook-rollback.md) | Rollback Helm, Terraform e pipeline |
| **Playbook** | [Scaling](docs/playbook-scaling-performance.md) | HPA, vertical scaling, diagnostico |
| **Referencia** | [Decisoes Tecnicas (ADR)](docs/adr-001-decisoes-tecnicas.md) | Kind vs Minikube, SSH vs SSM, OIDC |
| **Referencia** | [Security Baseline](docs/security-baseline.md) | Controles de seguranca por camada |
| **Referencia** | [Links](docs/links-e-referencias.md) | Documentacao oficial AWS, Terraform, Helm, K8s |

---

## Diferenciais

### Extras solicitados na avaliacao

- **Abstracao**: Chart generico `webapp` que suporta qualquer imagem (nao apenas Nginx)
- **Recursos**: Resource limits e requests de CPU/Memoria em todos os pods
- **Seguranca OIDC**: Autenticacao via OpenID Connect — zero static keys

### Alem do solicitado

| Camada | Diferencial |
|--------|-------------|
| **Terraform** | 5 modulos reusaveis, inventories (dev/homol/prod), setup.sh one-command bootstrap, bucket S3 com account ID unico, tags padronizadas |
| **Helm** | NetworkPolicy, HPA (CPU + memoria), values de producao, probes configuraveis, checksum annotation |
| **CI/CD** | GitFlow (feature/develop/release/hotfix), concurrency control, path filter, smoke test pos-deploy |
| **Seguranca** | IMDSv2, EBS encriptado, S3 com 4 bloqueios de acesso publico, SG least-privilege |
| **Docs** | Runbooks, Playbooks, ADR, Security Baseline, anotacoes de experiencia profissional |

---

## Visao de Engenharia: Projetos em Escala

O que foi entregue atende o escopo do teste. Abaixo, registro como estruturo projetos em ambientes corporativos — visao que trago de mais de 6 anos como DevOps/SRE.

### Organization Templates

Em ambientes corporativos, o caminho para padronizacao e ter **template repositories** na Organization:

- `template-app-backend` — Dockerfile, Helm chart, workflows de CI/CD, CODEOWNERS
- `template-app-frontend` — adaptado para frontend (build de assets, CDN)
- `template-infra` — Terraform modules, inventories, workflows de plan/apply

Novo micro-servico nasce com **um clique**, ja com CI/CD, linting e seguranca configurados.

### Reusable Workflows

Templates consomem **reusable workflows** centralizados (ex: `org/shared-workflows`):

- Workflow de build/test/deploy em **um unico lugar**, chamado via `uses: org/shared-workflows/.github/workflows/ci-build.yml@v2`
- Melhorias propagadas automaticamente para todos os repositorios
- Times novos preenchem variaveis no template e tudo funciona

### GitHub App Token

Automacao cross-repo usa **GitHub App** instalado na Organization — mais seguro que PATs, com escopo granular, expiracao em 1h e auditoria vinculada ao App.

### RBAC por Squad

Cada squad tem sigla (ex: `squad-payments`) com teams escalonados:

| Team | Permissao |
|------|-----------|
| `squad-payments-read` | Read |
| `squad-payments-dev` | Write |
| `squad-payments-maintainer` | Maintain |
| `platform-sre` | Admin (cross) |

### GitFlow Adaptado

```
feature/* → develop (SonarQube + SAST) → release/* → main (producao)
```

> **Ponto importante**: A imagem Docker construida na `develop` e **promovida** para producao, nao reconstruida. Isso garante que o binario validado e exatamente o mesmo que vai para prod.

### Por que Isso Importa

Padronizacao de templates, reusable workflows e RBAC por squad se paga em menos de 3 meses — em velocidade de onboarding, reducao de incidentes e consistencia entre servicos.

---

**Autor**: Christopher Amaral | DevOps Engineer
**Contato**: christopheramaral1996@gmail.com
**LinkedIn**: [christopher-amaral](https://www.linkedin.com/in/christopher-amaral-6788b0359)

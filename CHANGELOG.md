# Changelog

Todas as mudancas relevantes do projeto estao documentadas aqui.

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

---

## [1.1.0] - 2026-04

### Adicionado

**Infraestrutura**
- Elastic IP para endereco fixo da EC2 (nao muda em stop/start)
- Suporte a OIDC claims por environment (`repo:owner/repo:environment:*`)

**CI/CD**
- Suporte GitFlow: branches `main`, `develop`, `feature/*`, `release/*`, `hotfix/*`
- Path filter expandido: `charts/**`, `terraform/**`, `.github/workflows/ci-deploy-k8s.yml`
- Lint roda em todas as branches; deploy somente na `main`

**Documentacao**
- Playbook: Incident Response
- Playbook: Rollback
- Playbook: Scaling e Performance
- Guia de Execucao Passo a Passo
- Links e Referencias

### Alterado

**Infraestrutura**
- Instance type: `t3.medium` → `m7i-flex.large` (8GB RAM, Free Tier eligible)
- Resources do chart reduzidos para ambiente dev: 50m/32Mi requests, 100m/64Mi limits

**CI/CD**
- Deploy strategy: `--atomic` → `--force --wait` (compativel com primeiro install)
- Service name corrigido: `webapp-webapp` → `webapp`
- Indentacao dos heredoc SSH corrigida nos steps do workflow

**Documentacao**
- Todas as datas atualizadas para 2026-04
- ADR-001 atualizado com decisoes reais (instance type, deploy strategy)
- Todos os runbooks e playbooks corrigidos com service name e flags atuais

---

## [1.0.0] - 2026-04

### Adicionado

**Terraform**
- Modulos reusaveis: `networking`, `compute`, `security`, `storage`, `iam`
- Inventories por ambiente: `dev`, `homol`, `prod`
- Backend S3 com partial config (`backend.hcl` por ambiente)
- OIDC Provider para GitHub Actions (zero credenciais estaticas)
- EC2 com bootstrap automatico (Docker + Kind + kubectl + Helm)
- IMDSv2 enforced, EBS encriptado
- S3 com versionamento, encriptacao e acesso publico bloqueado
- DynamoDB para state locking
- Tags padronizadas (Project, Environment, Squad, Owner, ManagedBy)

**Helm Chart (webapp)**
- Correcao de todas as inconsistencias do chart original
- Chart generico que suporta qualquer imagem de container
- ConfigMap parametrizavel para `index.html` via `customMessage`
- Service ClusterIP
- Resource limits e requests (CPU/memoria)
- Liveness e readiness probes
- HorizontalPodAutoscaler (HPA)
- NetworkPolicy
- Values de produção separados (`values-production.yaml`)

**CI/CD (GitHub Actions)**
- Pipeline `ci-deploy-k8s.yml` com lint + deploy
- Autenticacao AWS via OIDC
- Deploy via SSH com `helm upgrade --install`
- Injecao de mensagem com commit SHA
- Concurrency control (um deploy por vez)
- Path filter (charts/** e terraform/**)
- Smoke test pos-deploy

**Documentacao**
- Runbook: Terraform Setup
- Runbook: Helm Chart
- Runbook: CI/CD Pipeline
- Runbook: Validacao de Deploy
- ADR-001: Decisoes Tecnicas
- Security Baseline

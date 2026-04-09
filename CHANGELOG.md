# Changelog

Todas as mudancas relevantes do projeto estao documentadas aqui.

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

---

## [1.0.0] - 2025-04

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
- Deploy via SSH com `helm upgrade --install --atomic`
- Injecao de mensagem com commit SHA
- Concurrency control (um deploy por vez)
- Path filter (so executa quando `charts/**` muda)
- Smoke test pos-deploy

**Documentacao**
- Runbook: Terraform Setup
- Runbook: Helm Chart
- Runbook: CI/CD Pipeline
- Runbook: Validacao de Deploy
- ADR-001: Decisoes Tecnicas
- Security Baseline

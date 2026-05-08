# Changelog

Todas as mudancas relevantes do projeto estao documentadas aqui.

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

---

## [1.4.2] - 2026-04-30

### Alterado

- `cost-report.yml`: schedule diario (`cron: 0 9 * * *`) desativado intencionalmente. O workflow agora roda apenas via `workflow_dispatch` (manual) — mantido como demonstracao da automacao Python via OIDC, sem gerar custo de runner recorrente
- README e `docs/architecture.md` atualizados para refletir que o cost-report e modo demo/manual

---

## [1.4.1] - 2026-04-30

### Alterado

**Documentacao — descricao generica de experiencia profissional**

- Mencoes a empresas anteriores substituidas por descricoes genericas do segmento (varejista, fintech de pagamento de delivery, consultoria de TI, banco de varejo da America Latina). Mantem o storytelling tecnico e a credibilidade da experiencia, sem expor nomes proprios

**Documentacao — Airflow + IA**

- README "Sobre o autor": menciona iniciativas com Apache Airflow (DAGs operacionais) e IA aplicada a operacao (deteccao de anomalia, classificacao de incidente, ChatOps)
- README tabela "Stack": duas linhas novas como roadmap — `Apache Airflow` e `LLM em pipeline`
- `docs/architecture.md`: tabela "Onde isto se conecta com o CV" recebeu Airflow e IA como blocos do roadmap
- `docs/runbook-observability.md`: roadmap ampliado com tres itens novos — Airflow ao lado da stack, IA aplicada a observabilidade (classificador LLM de causa raiz) e ChatOps

---

## [1.4.0] - 2026-04-30

### Adicionado

**Seguranca**

- `security-scan` job no `ci-deploy-k8s.yml` com Trivy (imagem + IaC), output SARIF publicado em GitHub Security
- `.pre-commit-config.yaml` com terraform_fmt/validate/tflint, helmlint, yamllint, shellcheck, gitleaks e checks de higiene de repo

**Self-Healing**

- Novo template `charts/webapp/templates/self-healing.yaml`: CronJob + ServiceAccount + Role com permissoes minimas
- Detecta pods em CrashLoopBackOff (ou com restartCount acima de threshold) e os deleta para forcar recriacao
- Configuravel via `selfHealing.*` no values; ligado por default em `values-production.yaml`

**Observabilidade**

- `argocd/applications/kube-prometheus-stack.yaml` — Prometheus + Grafana + Alertmanager via Helm chart oficial, NodePort 30090
- `argocd/applications/loki-stack.yaml` — Loki + Promtail no mesmo namespace `monitoring`
- AppProject `chris-platform` ampliado com novos sourceRepos (prometheus-community, grafana) e namespace `monitoring`
- `docs/runbook-observability.md` com TL;DR, dashboards uteis, alerta de exemplo, custos e troubleshooting

**Automacao Python**

- `scripts/aws_cost_report.py` — consulta Cost Explorer, agrupa por Service e tag Project, devolve resumo + JSON
- `.github/workflows/cost-report.yml` — agenda diaria 09:00 UTC + workflow_dispatch, autenticado via OIDC, publica JSON como artifact

**Disaster Recovery**

- `docs/playbook-disaster-recovery.md` com 4 cenarios (state, cluster, SSH, conta inteira) com RTO/RPO e plano de teste regular

**Arquitetura visual**

- `docs/architecture.md` com 4 diagramas Mermaid (visao geral, fluxo push vs pull, dependency injection Terraform, estados do pod)

### Alterado

- README principal: tabela "Stack" expandida com observabilidade, Self-Healing, automacao Python e disciplina (pre-commit)
- Estrutura do repositorio no README atualizada com `scripts/`, novas Applications ArgoCD e workflows
- `docs/README.md` indice atualizado com Arquitetura, Observabilidade e Disaster Recovery
- AppProject `chris-platform`: `clusterResourceWhitelist` ampliado para suportar instalacoes Helm que criam ClusterRoles

---

## [1.3.0] - 2026-04-30

### Adicionado

**GitOps com ArgoCD**

- Pasta `argocd/` com AppProject `chris-platform`, Application `webapp` e App-of-Apps raiz
- `argocd/install.sh` idempotente para reinstalacao manual
- Bootstrap automatico do ArgoCD no `bootstrap-cluster.sh` (user-data da EC2)
- ArgoCD UI exposta via NodePort 30080, modo `server.insecure` para HTTP no Kind
- Workflow `argocd-bootstrap.yml` (manual) que aplica os manifestos via OIDC + SSH
- Novo runbook `docs/runbook-argocd.md` com troubleshooting e roadmap GitOps
- Novo indice `docs/README.md` mapeando toda a documentacao tecnica

### Alterado

- README principal reescrito com tom pessoal/profissional, referenciando `docs/`
- `customMessage` default atualizado para identificar o autor e o projeto
- `setup.sh` agora limpa `.terraform/` antes de iniciar (evita conflito de provider)
- `.gitignore` reforcado: `*.pem`, `ssh-key-*.pem` e `.terraform.lock.hcl` ignorados

### Seguranca

- ArgoCD habilita evolucao para deploys 100% pull-based, eliminando SSH no pipeline

---

## [1.2.0] - 2026-04

### Adicionado

**Execucao por terceiros**

- `setup.sh`: Script de bootstrap automatizado — um comando provisiona tudo
- `teardown.sh`: Script para destruir recursos com confirmacao
- `backend.hcl.example` em cada inventory (dev/homol/prod)
- Bucket S3 com AWS account ID no nome (evita colisao global)
- Chave SSH exportada automaticamente para arquivo pelo setup.sh

### Alterado

- Removido `prevent_destroy` do S3 bucket (facilita teardown em ambiente de teste)
- `backend.hcl` agora e gerado dinamicamente pelo `setup.sh` (nao versionado)
- README reescrito com secao "Quick Start" — setup completo em um comando

### Corrigido

- Bucket S3 com nome fixo impedia execucao em outras contas AWS
- Key pair inacessivel para terceiros (agora exportada automaticamente)
- `backend.hcl` desacoplado do `terraform.tfvars` — setup.sh gera ambos consistentes

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

# chris-platform — DevOps & GitOps na AWS

---

## Por que esse repositorio existe

Trabalho com infraestrutura desde 2017 em ambientes diversos: grande varejista nacional, fintech de meios de pagamento em marketplace de delivery, integradora/consultoria de TI e banco de varejo com grande escalabilidade na America Latina. Ja entreguei plataformas de pagamento com milhares de microservicos, pipelines de CI/CD do zero, observabilidade centralizada, automacao com Apache Airflow para orquestracao de jobs operacionais e iniciativas de IA aplicadas a operacao (ChatOps, deteccao de anomalia em log e classificacao de incidentes). Mas todo profissional de SRE sabe: o curriculo conta a historia, **Segue meu projeto pessoal**.

Esse projeto e a versao "publicavel" do que vejo no dia a dia: um cluster Kubernetes provisionado por Terraform, um chart Helm generico que serve para 80% dos casos, um pipeline CI/CD de GitHub Actions com OIDC (zero credencial estatica) e — para fechar o ciclo — **ArgoCD** entregando GitOps de verdade. Tudo escrito do jeito que eu gostaria de encontrar quando entro em uma squad nova: simples de subir, simples de derrubar, com runbooks honestos para quando algo quebrar.

Se voce for CTO, gerente, tech lead ou apenas curioso, toda a documentacao detalhada esta em **[docs/](docs/)** — comece por **[docs/README.md](docs/README.md)** que serve de mapa.

---

## O que essa plataforma faz, em uma frase

Provisiona uma EC2 na AWS, sobe um cluster Kubernetes (Kind), instala ArgoCD e entrega uma aplicacao web — tudo com um comando, sem credencial estatica e com dois caminhos de deploy (push via GitHub Actions e pull via ArgoCD) coexistindo de forma intencional.

```text
+---------------------------+         +---------------------------+
|       GitHub Actions       |  push   |      AWS (us-east-1)      |
|  ci-deploy-k8s.yml         | ------> |                           |
|   1. helm lint --strict    |  OIDC   |   EC2 m7i-flex.large      |
|   2. AWS OIDC AssumeRole   | ======> |   +-----------------+     |
|   3. SSH na EC2            |   SSH   |   |  Kind cluster   |     |
|   4. helm upgrade --install| ------> |   |  +-----------+  |     |
+---------------------------+          |   |  |  ArgoCD   |  |     |
                                       |   |  |  (GitOps) |  |     |
       repo Git ---- pull ------------>|   |  +-----------+  |     |
                                       |   |  webapp (Helm)  |     |
                                       |   +-----------------+     |
                                       +---------------------------+
```

---

## A Stack — escolhas e motivos

| Camada | Tecnologia | Por que essa? |
|--------|-----------|---------------|
| IaC | **Terraform** | 5 modulos reusaveis, inventories por ambiente, backend S3 com lock em DynamoDB. Modulos viram repositorios separados quando o projeto cresce. |
| Cluster | **Kind sobre EC2** | Free Tier eligible, sobe em ~30s, ideal para validar o ciclo completo. Em produção, leia-se EKS. |
| Chart | **Helm 3 (chart `webapp`)** | Generico, aceita qualquer imagem, com HPA, NetworkPolicy, probes, checksum annotation e Self-Healing opcional. |
| CI/CD push | **GitHub Actions + OIDC** | Lint estrito + Trivy scan + deploy via SSH com OIDC AssumeRole. Zero `AWS_ACCESS_KEY_ID` em qualquer lugar. |
| CI/CD pull | **ArgoCD (App-of-Apps)** | GitOps real: cluster reconcilia o estado a partir do Git, com `prune` e `selfHeal` ligados. |
| Observabilidade | **Prometheus + Grafana + Loki** | Stack completa via ArgoCD App. Metricas, alertas, dashboards e logs centralizados — desligavel para Kind pequeno. |
| Self-Healing | **CronJob no chart** | Detecta CrashLoopBackOff e deleta o pod para o ReplicaSet recriar. Espelha um sistema de auto-cura que entreguei numa fintech de meios de pagamento. |
| Automacao | **Python + boto3** | `aws_cost_report.py` agendado via Actions: relatorio diario de custo agrupado por tag e servico. |
| Orquestracao (roadmap) | **Apache Airflow** | DAG planejada para encadear o cost report + scan de drift Terraform + checagem de saude do cluster + envio para Slack. Espelha automacoes que entreguei em banco de varejo. |
| IA aplicada (roadmap) | **LLM em pipeline** | Iniciativas planejadas: classificador de severidade de log via LLM, ChatOps para `kubectl describe` em linguagem natural, sumarizacao automatica de PR/incidente. Tema que ja toquei em equipes anteriores. |
| Seguranca | IMDSv2, EBS encrypted, S3 bloqueado, SG least-privilege, OIDC trust por branch, **Trivy** em CVE de imagem e IaC, **gitleaks** em pre-commit | Cada controle existe para responder a um incidente real que vivi ou estudei (ver [docs/security-baseline.md](docs/security-baseline.md)). |
| Disciplina | **pre-commit** com tflint, helmlint, yamllint, shellcheck, gitleaks | Pega bug antes do CI, evita gastar minuto de runner com erro de linter. |

---

## Subindo o ambiente do zero

Pre-requisitos: AWS CLI configurado (`aws configure`), Terraform >= 1.5, Bash (Linux/macOS/WSL).

```bash
# 1. Personalize seu inventory
vi terraform/inventories/dev/terraform.tfvars
#    project_name, owner, github_repository

# 2. Provisione tudo (um comando faz S3+DynamoDB, depois VPC+EC2+IAM+Kind+ArgoCD)
cd terraform && chmod +x setup.sh && ./setup.sh dev

# 3. Configure os 4 GitHub Secrets que o setup.sh imprime no final
#    (AWS_ROLE_ARN, EC2_INSTANCE_ID, EC2_SSH_HOST, EC2_SSH_PRIVATE_KEY)

# 4. Trigger o pipeline (qualquer mudanca em charts/** ou terraform/**)
git commit --allow-empty -m "chore: trigger pipeline" && git push origin main
```

O passo a passo completo, com troubleshooting, esta em **[docs/runbook-terraform-setup.md](docs/runbook-terraform-setup.md)**.

Para destruir tudo: `cd terraform && ./teardown.sh dev`.

---

## Os dois caminhos de deploy (e por que ambos existem)

### Caminho A — Push (CI dispara)

`.github/workflows/ci-deploy-k8s.yml` faz `helm upgrade --install --force --wait` via SSH na EC2. E o caminho que **prova que o pipeline funciona** e e o exigido na avaliacao do projeto. Cada commit em `main` que toque `charts/**` ou `terraform/**` triggera lint -> deploy -> smoke test.

### Caminho B — Pull (ArgoCD reconcilia)

`argocd/applications/webapp.yaml` contem um `Application` que aponta para `charts/webapp` neste mesmo repositorio. Com `automated.prune` e `selfHeal` ligados, o cluster sempre converge para o que esta no Git.

Os dois caminhos coexistem de proposito: o caminho A e a ferramenta de ensino do "como funciona um pipeline imperativo" e o caminho B mostra para onde a industria caminhou. Em uma plataforma real, **eu manteria apenas o B** (push deveria virar pull) — a discussao completa esta em [docs/adr-001-decisoes-tecnicas.md](docs/adr-001-decisoes-tecnicas.md#decisao-2--ssh-vs-self-hosted-runner-vs-ssm).

---

## Documentacao — onde ler o que

A pasta [docs/](docs/) e o coracao do projeto. Cada documento foi escrito para ser util quando voce esta com pressa (TL;DR no topo) e quando voce quer aprofundar (`Pontos importantes` ao longo do texto, com historias reais de bastidor).

| Documento | Para que serve |
|-----------|---------------|
| **[Indice da documentacao](docs/README.md)** | Mapa de tudo que existe em docs/ |
| [Arquitetura (diagramas Mermaid)](docs/architecture.md) | Visao geral, fluxo de deploy, modulos Terraform |
| [Guia passo a passo](docs/GUIA-PASSO-A-PASSO.md) | Da clonagem ate a EC2 entregando trafego |
| [Runbook — Terraform](docs/runbook-terraform-setup.md) | Como esta organizado o IaC e por que |
| [Runbook — Helm chart](docs/runbook-helm-chart.md) | Decisoes do chart `webapp` e parametros |
| [Runbook — CI/CD pipeline](docs/runbook-ci-cd-pipeline.md) | Como o GitHub Actions opera com OIDC e SSH |
| [Runbook — ArgoCD](docs/runbook-argocd.md) | Instalacao, App-of-Apps e fluxo GitOps |
| [Runbook — Observabilidade](docs/runbook-observability.md) | Prometheus + Grafana + Loki via ArgoCD |
| [Runbook — Validacao de deploy](docs/runbook-validacao-deploy.md) | Checklist completo apos o deploy |
| [Playbook — Resposta a incidentes](docs/playbook-incident-response.md) | Detectar -> mitigar -> resolver -> documentar |
| [Playbook — Rollback](docs/playbook-rollback.md) | Helm, Terraform e pipeline |
| [Playbook — Scaling & performance](docs/playbook-scaling-performance.md) | HPA, vertical scaling, diagnostico |
| [Playbook — Disaster Recovery](docs/playbook-disaster-recovery.md) | 4 cenarios com RTO/RPO + plano de teste |
| [ADR-001 — Decisoes tecnicas](docs/adr-001-decisoes-tecnicas.md) | Kind vs Minikube, OIDC vs Access Keys, etc. |
| [Security Baseline](docs/security-baseline.md) | Controles de seguranca por camada |
| [Links e referencias](docs/links-e-referencias.md) | Pagina curada de links que abro toda semana |

---

---

## Estrutura do repositorio

```text
.
├── .github/workflows/
│   ├── ci-deploy-k8s.yml             # Pipeline CI/CD (lint + Trivy + deploy)
│   ├── argocd-bootstrap.yml          # Aplica os manifestos ArgoCD (manual)
│   └── cost-report.yml               # Relatorio diario de custo AWS via OIDC
├── argocd/
│   ├── projects/chris-platform.yaml      # AppProject que isola as apps deste lab
│   ├── applications/
│   │   ├── webapp.yaml                   # webapp via Helm (this repo)
│   │   ├── kube-prometheus-stack.yaml    # Prometheus + Grafana + Alertmanager
│   │   └── loki-stack.yaml               # Loki + Promtail (logs)
│   ├── bootstrap.yaml                # App-of-Apps (raiz)
│   └── install.sh                    # Instalador manual idempotente
├── charts/webapp/                    # Chart Helm + Self-Healing CronJob
├── scripts/
│   ├── aws_cost_report.py            # Cost Explorer -> JSON via OIDC
│   └── requirements.txt
├── docs/                             # Runbooks, playbooks, ADR, baseline, arquitetura
├── .pre-commit-config.yaml           # tflint, helmlint, gitleaks, yamllint, shellcheck
└── terraform/
    ├── setup.sh                      # Bootstrap completo em um comando
    ├── teardown.sh                   # Destrutor com confirmacao explicita
    ├── inventories/dev|homol|prod
    └── modules/                      # networking | compute | security | storage | iam
```

---

## Sobre o autor

**Christopher Amaral** — Engenheiro de infraestrutura (DevOps/SRE/PSE) com 6+ anos em ambientes de alta disponibilidade. Passou por uma grande operacao de varejo brasileiro, fintech de meios de pagamento em marketplace de delivery, integradora/consultoria de TI e banco de varejo com grande escalabilidade na America Latina. Atuou em iniciativas de orquestracao com **Apache Airflow** (DAGs operacionais para ETL/automacao recorrente) e em projetos de **IA aplicada a operacao** (deteccao de anomalia em log, classificacao de incidente, ChatOps). Cursando Engenharia da Computacao e tecnico em Analise/Desenvolvimento, Eletrotecnica e Eletronica.

LinkedIn: [christopher-amaral](https://www.linkedin.com/in/christopher-amaral-6788b0359)

> Esse projeto e mantido em horario de laboratorio pessoal. Se voce viu algo que pode melhorar, abra uma issue ou me chame no LinkedIn — feedback honesto e como eu evoluo o trabalho.

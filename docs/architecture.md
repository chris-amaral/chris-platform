# Arquitetura — chris-platform

> Diagramas Mermaid renderizados nativamente pelo GitHub. Mantenedor: chris-amaral

---

## Visao geral (camadas)

```mermaid
flowchart LR
  subgraph DEV["Workstation do desenvolvedor"]
    GIT[Git push em main]
    CLI[terraform / helm / kubectl]
  end

  subgraph GH["GitHub"]
    REPO[(chris-amaral/DevOps-CICD)]
    ACT["GitHub Actions<br/>ci-deploy-k8s.yml<br/>argocd-bootstrap.yml<br/>cost-report.yml"]
  end

  subgraph AWS["AWS — us-east-1"]
    direction TB
    OIDC{{OIDC Provider}}
    S3[(S3 tfstate<br/>+ versionamento)]
    DDB[(DynamoDB<br/>state lock)]

    subgraph VPC["VPC 10.10.0.0/16"]
      EC2[EC2 m7i-flex.large<br/>Ubuntu 22.04 + IMDSv2]
      subgraph KIND["Kind cluster"]
        ARGO[ArgoCD]
        APP[webapp]
        SH[Self-Healing<br/>CronJob]
        PROM[kube-prometheus-stack]
        LOKI[Loki + Promtail]
      end
    end
  end

  subgraph USR["Usuarios"]
    BROWSER[Browser]
  end

  GIT --> REPO
  REPO --> ACT
  ACT -->|JWT OIDC| OIDC
  OIDC -->|AssumeRole| EC2
  ACT -->|SSH push| EC2
  REPO -->|Helm pull| ARGO
  ARGO -->|sync| APP
  ARGO -->|sync| PROM
  ARGO -->|sync| LOKI
  CLI -->|terraform| S3
  CLI --> DDB
  BROWSER -->|:30080| ARGO
  BROWSER -->|:30090| PROM
  PROM -.->|scrape| APP
  LOKI -.->|coleta logs| APP
  SH -.->|kubectl delete pod| APP
```

---

## Fluxo de deploy (push vs pull)

```mermaid
sequenceDiagram
  autonumber
  actor Dev
  participant Git as GitHub repo
  participant CI as GitHub Actions
  participant STS as AWS STS
  participant EC2 as EC2/Kind
  participant Argo as ArgoCD

  Dev->>Git: git push (charts/** ou terraform/**)
  Git->>CI: webhook -> ci-deploy-k8s.yml

  rect rgb(230, 242, 255)
    note over CI,EC2: Caminho A — push
    CI->>CI: helm lint --strict<br/>trivy scan
    CI->>STS: JWT (audience=sts.amazonaws.com)
    STS-->>CI: credenciais temporarias
    CI->>EC2: SSH + helm upgrade --install
    EC2-->>CI: smoke test OK
  end

  rect rgb(232, 255, 232)
    note over Git,Argo: Caminho B — pull (paralelo)
    Argo->>Git: poll /charts/webapp (3 min)
    Git-->>Argo: novo SHA
    Argo->>EC2: kubectl apply (server-side)
    Argo->>Argo: marca app como Synced
  end
```

---

## Modulos Terraform — dependency injection

```mermaid
flowchart TD
  ROOT[main.tf<br/>orquestrador] --> NET[networking<br/>VPC, Subnet, IGW]
  ROOT --> SEC[security<br/>Security Groups]
  ROOT --> STO[storage<br/>S3 + DynamoDB]
  ROOT --> IAM[iam<br/>OIDC + Roles]
  ROOT --> CMP[compute<br/>EC2 + Key Pair + EIP]

  NET -->|vpc_id| SEC
  NET -->|subnet_id| CMP
  SEC -->|sg_id| CMP
  IAM -->|instance_profile| CMP
```

---

## Estados do pod webapp (com self-healing ativo)

```mermaid
stateDiagram-v2
  [*] --> Pending: kubectl apply
  Pending --> Running: pull ok + probes ok
  Running --> CrashLoopBackOff: liveness fails > N
  CrashLoopBackOff --> Pending: kubelet retry
  CrashLoopBackOff --> Deleted: self-healing CronJob<br/>(restartCount > maxRestartsBeforeAction)
  Deleted --> Pending: ReplicaSet recria
  Running --> [*]: helm uninstall
```

---

## Onde isto se conecta com o CV

| Bloco do diagrama | Item do CV reproduzido |
|-------------------|------------------------|
| OIDC + IAM Roles | Itau Latam — provisionamento AWS com OIDC |
| ArgoCD + App-of-Apps | iFood/Zoop — auditoria de deploy via Git |
| Self-Healing CronJob | iFood/Zoop — sistema de Self-Healing reduzindo MTTR |
| kube-prometheus-stack + Loki | Datadog/Grafana/Prometheus/Loki/Graylog (varios) |
| Cost Report (Python) | Itau Latam — automacoes em Python no GitHub Actions |
| DR Playbook | EDCS — jobs de backup/restore SQL Server |

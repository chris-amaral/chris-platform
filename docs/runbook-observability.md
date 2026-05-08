# Runbook: Observabilidade (Prometheus + Grafana + Loki)

> Ultima atualizacao: 2026-04 | Mantenedor: chris-amaral

---

## TL;DR

A pasta [`argocd/applications/`](../argocd/applications/) contem duas Applications: `kube-prometheus-stack` (metricas + alertas + dashboards) e `loki-stack` (logs centralizados). As duas instalam no namespace `monitoring`, ficam expostas atraves do Grafana em `:30090` (NodePort) e sao ligaveis sob demanda — porque consomem ~1GB no Kind do laboratorio.

Reproduz, em escala de bancada, stacks de observabilidade que entreguei em uma integradora/consultoria de TI (Graylog) e que mantive em fintech de meios de pagamento (Datadog/Prometheus/Loki).

---

## Quando ligar essa stack

- Sempre que quiser demonstrar o ciclo completo de telemetria (metric -> dashboard -> alerta).
- Antes de um deploy de mudanca grande (ter baseline visivel ajuda no rollback).
- **Nao** habilite em EC2 com menos de 8GB RAM — vai trocar Kind por OOMKill.

---

## Como ativar

```bash
# Via ArgoCD UI: clique nas Applications -> Sync
# Ou via CLI:
kubectl apply -f argocd/applications/kube-prometheus-stack.yaml
kubectl apply -f argocd/applications/loki-stack.yaml

# Aguardar tudo Ready (~3-5 min na primeira vez, baixa imagens)
kubectl -n monitoring wait --for=condition=available deployment --all --timeout=10m
```

## Como acessar

### Grafana (dashboard principal)

```bash
# Pegar a senha admin auto-gerada
kubectl -n monitoring get secret kube-prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d

# Abrir
open http://<EC2_PUBLIC_IP>:30090
# user: admin / pass: (saida acima)
```

### Prometheus (queries diretas)

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
# http://localhost:9090
```

### Loki (queries via Grafana)

Loki nao tem UI propria — adicionado automaticamente como datasource no Grafana. Em **Explore -> Loki** rode queries como:

```
{namespace="default", app_kubernetes_io_instance="webapp"}
```

---

## Dashboards uteis (importar pelo ID)

| ID | Nome | Para que serve |
|----|------|----------------|
| 315 | Kubernetes cluster monitoring | Visao geral do cluster |
| 6417 | Kubernetes / Cluster | Pods, deployments, recursos |
| 13639 | Logs / App | Logs por aplicacao via Loki |
| 7249 | Helm releases overview | Releases ativos |

```bash
# Em Grafana > Dashboards > New > Import > digite o ID
```

> **Ponto importante**: Em projetos serios, nunca confio em dashboard "do balcao" sem entender as queries. Antes de validar com o time, abro cada painel, leio o PromQL e confirmo se a metrica corresponde ao que a app expoe. Dashboards padrao sao ponto de partida — nao verdade absoluta.

---

## Alertas (exemplo basico)

O kube-prometheus-stack ja vem com regras default cobrindo: CPU/memoria de node, status de pods, etcd, etc. Para um alerta custom da webapp:

```yaml
# salvar em charts/webapp/templates/prometheusrule.yaml (nao incluido por default)
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: webapp-alerts
  labels:
    release: kube-prometheus-stack   # match com o selector do Operator
spec:
  groups:
    - name: webapp.rules
      rules:
        - alert: WebappPodNotReady
          expr: kube_pod_status_ready{namespace="default", pod=~"webapp-.*", condition="true"} == 0
          for: 2m
          labels:
            severity: warning
          annotations:
            summary: "Pod webapp nao pronto ha 2 minutos"
            runbook: "https://github.com/chris-amaral/chris-platform/blob/main/docs/playbook-incident-response.md"
```

> **Ponto importante**: Toda regra de alerta deve apontar para um runbook. Vi muitas equipes onde o alerta diz "PodNotReady" e ninguem sabe o que fazer. O `runbook` annotation e o que fecha o ciclo entre observabilidade e operacao.

---

## Custos e overhead

Em ambiente de laboratorio (m7i-flex.large, 8GB RAM):

| Componente | RAM tipica | CPU tipica | Disco |
|-----------|------------|------------|-------|
| Prometheus | 256-512Mi | 50-200m | 5Gi (PV) |
| Grafana | 64-128Mi | 20-50m | - |
| Alertmanager | 32-64Mi | 5-20m | - |
| Loki | 128-256Mi | 30-100m | 5Gi (PV) |
| Promtail (DS) | 32-64Mi | 10-30m | - |
| **Total** | **~1GB** | **~400m** | **10Gi** |

> **Ponto importante**: Em qualquer deploy de observabilidade voce esta gastando 5-10% dos recursos do cluster com instrumentacao. Custo real, em troca de visibilidade. Em equipes que entendem isso, observability vira parte do orcamento da plataforma — nao item opcional.

---

## Troubleshooting

| Sintoma | Diagnostico | Solucao |
|---------|-------------|---------|
| Application `Degraded` no ArgoCD | `kubectl -n monitoring get pods` | Provavel falta de memoria — reduzir resources nos values |
| Grafana sem datasource | `kubectl -n monitoring get cm` | Reinstalar Application (datasources sao via ConfigMap) |
| Loki sem logs | `kubectl -n monitoring logs ds/promtail` | Promtail sem permissao — checar ClusterRole |
| Dashboards vazios | Prometheus targets DOWN | Em Prometheus -> Status -> Targets, ver erros de scrape |
| `OOMKilled` no Prometheus | `kubectl describe pod` | Reduzir retention (`prometheusSpec.retention: 3d`) |

---

## Roadmap

- [ ] PrometheusRule + Alertmanager → Slack via webhook
- [ ] Tempo (tracing distribuido) — fechar a tripla metrics + logs + traces
- [ ] Recording rules para queries custosas
- [ ] kube-prometheus-stack com remote_write para Mimir/Thanos quando o lab evoluir
- [ ] **Apache Airflow** ao lado da stack: DAGs operacionais (snapshot diario do estado do cluster, scan de drift Terraform, geracao de relatorios de SLO). Em projetos anteriores, o Airflow era o "orquestrador de tarefas chatas" que liberava o time para tocar o que importa.
- [ ] **IA aplicada a observabilidade**: classificador LLM que recebe o log da janela do alerta + o YAML do recurso e devolve hipotese de causa raiz no canal de plantao. Tema que toquei em equipes de plataforma — combina logs estruturados + RAG no runbook + LLM para sumarizar.
- [ ] **ChatOps com LLM**: bot que aceita "qual o status da webapp?" e retorna `kubectl describe + helm history + ultimas linhas do log` ja resumidas em portugues.

---

## Links uteis

- [kube-prometheus-stack chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Loki helm](https://github.com/grafana/helm-charts/tree/main/charts/loki-stack)
- [PromQL cheatsheet](https://promlabs.com/promql-cheat-sheet/)
- [LogQL docs](https://grafana.com/docs/loki/latest/logql/)

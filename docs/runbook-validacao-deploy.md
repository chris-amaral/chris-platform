# Runbook: Validacao de Deploy

> Ultima atualizacao: 2026-04 | Autor: Christopher Amaral

---

## TL;DR

Checklist completo para validar que a infraestrutura foi provisionada, o cluster Kind esta funcional, e a aplicacao esta rodando e respondendo corretamente na EC2.

---

## Pre-requisitos

| Item | Como obter |
|------|------------|
| IP da EC2 | `terraform output ec2_public_ip` |
| Chave SSH | `terraform output -raw ssh_private_key` |
| SSH liberado no SG | `allowed_ssh_cidrs` no tfvars |

---

## Procedimento

### 1. Conectar na EC2

```bash
ssh -i ssh-key-dev.pem ubuntu@<EC2_PUBLIC_IP>
```

### 2. Validar provisionamento (bootstrap)

```bash
# Status do bootstrap
cat /var/log/bootstrap-status
# Esperado: SUCCESS

# Se ainda não terminou (RUNNING ou arquivo ausente):
tail -f /var/log/bootstrap-cluster.log

# Tempo medio de bootstrap: 5-8 minutos na m7i-flex.large
```

> **Ponto importante**: Se o status não muda de RUNNING depois de 15 minutos, algo travou. Os pontos mais comuns de falha sao: (1) Docker não instalou (repositorio indisponivel), (2) Kind não criou o cluster (memoria insuficiente). Sempre cheque o log completo antes de recriar a EC2.

### 3. Validar Docker

```bash
docker --version
# Esperado: Docker version 2X.x.x

docker ps
# Esperado: containers do Kind (control-plane)

docker images | head
# Esperado: kindest/node
```

### 4. Validar cluster Kubernetes

```bash
kubectl get nodes -o wide
# Esperado: dev-cluster-control-plane   Ready   control-plane

kubectl cluster-info
# Esperado: Kubernetes control plane is running at https://...

kubectl get pods -n kube-system
# Esperado: coredns, etcd, kube-apiserver, etc - tudo Running
```

### 5. Validar ferramentas

```bash
kubectl version --client --output=yaml | head -5
helm version --short
kind version
kind get clusters
# Esperado: dev-cluster
```

### 6. Validar aplicacao (apos deploy)

```bash
# Pods
kubectl get pods -l app.kubernetes.io/name=webapp -o wide
# Esperado: 1/1 Running, 0 restarts

# Detalhes (events, conditions)
kubectl describe pod -l app.kubernetes.io/name=webapp

# Logs (ultimas 30 linhas, sem erros)
kubectl logs -l app.kubernetes.io/name=webapp --tail=30

# Service
kubectl get svc | grep webapp
# Esperado: webapp   ClusterIP   10.x.x.x   80/TCP

# Testar HTTP
kubectl port-forward svc/webapp 8080:80 &
curl -s http://localhost:8080
# Esperado: HTML com customMessage
kill %1
```

### 7. Validar Helm release

```bash
helm list
# Esperado: webapp   default   1   deployed   webapp-1.0.0

helm get values webapp
# Esperado: customMessage com texto do ultimo deploy

helm history webapp
# Esperado: historico de todas as revisoes
```

---

## Checklist Rapido

Use este checklist para validacao pos-deploy:

```
INFRAESTRUTURA
[ ] EC2 acessivel via SSH
[ ] bootstrap-status = SUCCESS
[ ] Docker rodando (docker ps mostra containers Kind)

CLUSTER
[ ] kubectl get nodes = 1 node Ready
[ ] kube-system pods todos Running
[ ] kubectl, helm, kind instalados e funcionais

APLICACAO
[ ] Pod webapp 1/1 Running, 0 restarts
[ ] Service webapp criado (ClusterIP)
[ ] curl retorna HTML com customMessage
[ ] Helm release status = deployed

CI/CD (se deploy via pipeline)
[ ] Job Lint passou sem erros
[ ] Job Deploy completou sem timeout
[ ] Post-deploy summary mostra pods Running
[ ] customMessage contem commit SHA
```

> **Ponto importante**: Em projetos passados, mantinhamos um checklist parecido em uma wiki do Confluence. Cada deploy de produção precisava ter TODOS os itens marcados por 2 pessoas (autor + revisor). Para dev, eu faco sozinho, mas o habito de ter o checklist evita esquecer algo.

---

## Troubleshooting

| Sintoma | Primeiro comando | Provavel causa | Solucao |
|---------|-----------------|----------------|---------|
| SSH timeout | `telnet <IP> 22` | SG sem seu IP | Adicione seu IP no tfvars e `terraform apply` |
| bootstrap não terminou | `cloud-init status` | Ainda executando | Aguarde ou verifique o log |
| Node NotReady | `kubectl describe node` | Kind container caiu | `docker ps -a`, `kind create cluster` |
| Pod CrashLoopBackOff | `kubectl logs <pod> --previous` | Imagem ou porta errada | Verifique `image` e `targetPort` |
| Pod Pending | `kubectl describe pod <pod>` | Sem recursos no node | Reduza limits ou use instance maior |
| Pod ImagePullBackOff | `kubectl describe pod <pod>` | Imagem não existe | Verifique `image.repository:tag` |
| Service sem endpoint | `kubectl get endpoints webapp` | Labels não batem | Compare labels do pod com selector do service |
| curl retorna 404 | `kubectl exec <pod> -- ls /usr/share/nginx/html` | ConfigMap não montou | Verifique `configMap.enabled` |

> **Ponto importante**: O pattern que sigo para debug de pods e sempre o mesmo: `get pods` -> `describe pod` -> `logs` -> `exec`. Nessa ordem. 95% dos problemas aparecem no `describe` (events) ou nos `logs`. So use `exec` quando precisa investigar o filesystem do container.

---

## Metricas e Observabilidade

```bash
# Events recentes do cluster (problemas aparecem aqui)
kubectl get events --sort-by='.lastTimestamp' | tail -20

# Uso de recursos (requer metrics-server)
kubectl top nodes
kubectl top pods

# Helm release info detalhada
helm get all webapp
```

> **Ponto importante**: Em um ambiente real, eu integraria Prometheus + Grafana para metricas e Loki para logs centralizados. Ao longo da carreira, ja trabalhei com Datadog, New Relic e Splunk em diferentes contextos. Para este escopo de dev, kubectl + eventos e suficiente. Mas em produção, sem observabilidade você esta voando cego.

---

## Links Uteis

- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/quick-reference/)
- [Debug Running Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/)
- [Kind Debugging](https://kind.sigs.k8s.io/docs/user/quick-start/#debugging)
- [Helm Troubleshooting](https://helm.sh/docs/faq/troubleshooting/)

# Playbook: Scaling e Performance

> Ultima atualizacao: 2025-04 | Autor: Christopher Amaral

---

## TL;DR

Guia para escalar a aplicacao horizontalmente (mais replicas) e verticalmente (mais recursos), diagnosticar problemas de performance, e configurar autoscaling automatico.

---

## Quando Escalar?

| Sinal | Metrica | Acao |
|-------|---------|------|
| Resposta lenta (latencia alta) | `kubectl top pods` mostra CPU perto do limit | Aumentar replicas ou CPU limit |
| Pods reiniciando (OOMKill) | `kubectl describe pod` mostra `OOMKilled` | Aumentar memory limit |
| Pods Pending | `kubectl describe pod` mostra `Insufficient cpu/memory` | Escalar o node (instance type maior) |
| Muitas requests (throughput) | HPA mostra CPU > target | Habilitar autoscaling |

> **Ponto importante**: Em experiênciass anteriores, a regra era escalar horizontal primeiro (mais replicas) porque e mais rapido e mais barato. Escalar vertical (mais CPU/memoria por pod) so quando horizontal não resolve — geralmente em apps stateful ou com locks de thread.

---

## Escalamento Horizontal (mais replicas)

### Manual

```bash
# Aumentar para 3 replicas
helm upgrade webapp ./charts/webapp \
  --set replicaCount=3

# Ou via kubectl direto (temporario, Helm sobrescreve no proximo upgrade)
kubectl scale deployment webapp-webapp --replicas=3
```

### Automatico (HPA)

O chart ja inclui HPA — basta ativar:

```bash
helm upgrade webapp ./charts/webapp \
  --set autoscaling.enabled=true \
  --set autoscaling.minReplicas=2 \
  --set autoscaling.maxReplicas=8 \
  --set autoscaling.targetCPUUtilizationPercentage=70
```

Verificar HPA:
```bash
kubectl get hpa
# NAME            REFERENCE             TARGETS   MINPODS   MAXPODS   REPLICAS
# webapp-webapp   Deployment/webapp..   45%/70%   2         8         3
```

> **Ponto importante**: O HPA precisa do metrics-server instalado no cluster para funcionar. Kind não inclui por padrao. Para instalar: `kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml`. Em projetos que participei, usavamos KEDA para autoscaling baseado em metricas custom (fila SQS, latencia do endpoint, etc).

### Usando values de produção

O arquivo `values-production.yaml` ja vem com HPA configurado:

```bash
helm upgrade --install webapp ./charts/webapp \
  -f ./charts/webapp/values-production.yaml
```

Valores de produção:
- 3 replicas minimas, 10 maximas
- HPA ativo com target CPU 70%, memoria 75%
- NetworkPolicy habilitada
- Resources maiores (250m-500m CPU, 256Mi-512Mi memoria)

---

## Escalamento Vertical (mais recursos por pod)

```bash
# Aumentar resources
helm upgrade webapp ./charts/webapp \
  --set resources.requests.cpu=250m \
  --set resources.limits.cpu=500m \
  --set resources.requests.memory=256Mi \
  --set resources.limits.memory=512Mi
```

> **Ponto importante**: CUIDADO com limits muito altos. Se o limit de memoria e 2Gi mas o request e 128Mi, o scheduler coloca o pod em um node que tem 128Mi livre, mas o pod pode consumir ate 2Gi e matar outros pods por OOMKill. Mantenha a razao limits/requests em no maximo 2:1 para evitar surpresas.

---

## Escalamento do Node (EC2)

Se todos os pods estao Pending por `Insufficient resources`:

```bash
# No terraform, altere o instance_type no inventory
vi terraform/inventories/dev/terraform.tfvars
# instance_type = "t3.large"  # 2 vCPU, 8GB RAM

terraform plan -var-file=inventories/dev/terraform.tfvars
terraform apply -var-file=inventories/dev/terraform.tfvars
```

| Instance | vCPU | RAM | Pods estimados |
|----------|------|-----|----------------|
| t3.medium | 2 | 4GB | ~8-10 pods (leves) |
| t3.large | 2 | 8GB | ~15-20 pods |
| t3.xlarge | 4 | 16GB | ~30-40 pods |

> **Ponto importante**: Para Kind em dev, `t3.medium` atende bem ate ~10 pods. Se precisar de mais, considere `t3.large`. Para produção real, a conversa muda completamente — usaria EKS com node groups auto-scaling. Mas para o escopo desse teste, uma EC2 com Kind e suficiente.

---

## Diagnostico de Performance

### Comandos essenciais

```bash
# Uso de recursos dos pods (requer metrics-server)
kubectl top pods

# Uso de recursos dos nodes
kubectl top nodes

# Events do cluster (problemas recentes)
kubectl get events --sort-by='.lastTimestamp' | tail -20

# Detalhes de resource usage de um pod
kubectl describe pod <pod-name> | grep -A 5 "Resources:"

# Verificar throttling de CPU
kubectl exec <pod> -- cat /sys/fs/cgroup/cpu/cpu.stat
```

### Sinais de problema

| Metrica | Saudavel | Alerta | Critico |
|---------|----------|--------|---------|
| CPU usage vs request | < 70% | 70-90% | > 90% |
| Memory usage vs limit | < 60% | 60-80% | > 80% |
| Pod restarts | 0 | 1-3 | > 3 |
| Pending pods | 0 | 1 | > 1 |

> **Ponto importante**: Em ambientes de produção que atuei, os thresholds de alerta eram: CPU > 70% por 5 minutos = warning, > 90% por 2 minutos = critical. Esses valores funcionam bem como ponto de partida. Ajuste conforme o perfil da aplicacao (CPU-bound vs memory-bound vs IO-bound).

---

## Links Uteis

- [Horizontal Pod Autoscaling](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [Resource Management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Metrics Server](https://github.com/kubernetes-sigs/metrics-server)
- [AWS EC2 Instance Types](https://aws.amazon.com/ec2/instance-types/)
- [KEDA - Event-driven Autoscaling](https://keda.sh/)

# Playbook: Resposta a Incidentes

> Ultima atualizacao: 2026-04 | Autor: Christopher Amaral

---

## TL;DR

Guia de resposta rapida para os cenarios mais comuns de falha: pod crashando, cluster inacessivel, deploy falhou e EC2 fora do ar. Cada cenario tem diagnostico, acao imediata e causa raiz.

> **Ponto importante**: Todo playbook de incidente segue o mesmo principio que aprendi na minha vivência profissional — DETECTAR, MITIGAR, RESOLVER, DOCUMENTAR. Primeiro você para o sangramento (mitigar), depois investiga a causa raiz. Nunca ao contrario.

---

## Cenario 1: Pod em CrashLoopBackOff

### Severidade: Media

### Detectar
```bash
kubectl get pods -l app.kubernetes.io/name=webapp
# STATUS: CrashLoopBackOff, RESTARTS > 3
```

### Mitigar (acao imediata)
```bash
# 1. Ver logs da instancia que morreu
kubectl logs -l app.kubernetes.io/name=webapp --previous --tail=50

# 2. Ver events do pod
kubectl describe pod -l app.kubernetes.io/name=webapp | grep -A 20 "Events:"

# 3. Se o deploy anterior estava funcionando, faca rollback
helm rollback webapp 0
# (0 = ultima revisao estavel)
```

### Resolver (causa raiz)

| Causa comum | Evidencia no log | Solucao |
|-------------|-----------------|---------|
| Imagem errada | `ImagePullBackOff` ou `ErrImagePull` | Corrija `image.repository` e `image.tag` |
| Porta errada | `connection refused` no probe | Corrija `service.targetPort` |
| Falta de memoria | `OOMKilled` no describe | Aumente `resources.limits.memory` |
| ConfigMap ausente | `mount failed` | Verifique `configMap.enabled` |
| Permissao de filesystem | `permission denied` | Verifique `securityContext` |

### Documentar
Registre no historico do Helm:
```bash
helm history webapp
# A revisao do rollback aparece automaticamente
```

> **Ponto importante**: Em experiênciass anteriores, 70% dos CrashLoopBackOff que investiguei eram OOMKill. O container comecava, consumia mais memoria que o limit, era morto pelo kernel, reiniciava, repetia. A solucao rapida e aumentar o limit; a solucao real e investigar por que a app consome tanta memoria (leak, cache sem TTL, etc).

---

## Cenario 2: Cluster Kind Inacessivel

### Severidade: Alta

### Detectar
```bash
kubectl get nodes
# Error: connection refused / Unable to connect to the server
```

### Mitigar
```bash
# 1. Verificar se os containers Docker do Kind estao rodando
docker ps -a | grep kind

# 2. Se o container existe mas esta parado:
docker start dev-cluster-control-plane

# 3. Se o container não existe, recriar o cluster:
kind create cluster --name dev-cluster --config /tmp/kind-cluster.yaml --wait 5m
mkdir -p ~/.kube && kind get kubeconfig --name dev-cluster > ~/.kube/config

# 4. Redeployar a aplicacao
helm upgrade --install webapp /tmp/webapp-chart \
  --set customMessage="Redeploy apos recovery"
```

### Resolver (causa raiz)

| Causa | Diagnostico | Prevencao |
|-------|-------------|-----------|
| EC2 reiniciou | `uptime` mostra pouco tempo | Kind não persiste entre reboots — adicionar ao rc.local |
| Docker reiniciou | `systemctl status docker` | Verificar logs: `journalctl -u docker` |
| Disco cheio | `df -h` | Limpar imagens: `docker system prune -a` |
| Memoria insuficiente | `free -m`, `dmesg \| grep oom` | Usar instance maior ou reduzir workloads |

> **Ponto importante**: Kind por natureza não sobrevive reboot da maquina host. Em ambientes de dev isso e aceitavel — o cluster e recriado em 30 segundos. Para persistencia, a solucao seria usar `systemd` para recriar o cluster no boot, ou migrar para EKS/k3s para cenarios mais robustos.

---

## Cenario 3: Deploy via Pipeline Falhou

### Severidade: Media

### Detectar
```
GitHub Actions > CI - Deploy K8s > Job: Deploy > Status: Failed
```

### Mitigar
```bash
# Helm rollback para versao anterior
# Verifique que a versao anterior esta rodando:
ssh -i key ubuntu@<EC2_IP>
helm list
kubectl get pods
```

### Resolver

| Passo no pipeline | Erro | Solucao |
|-------------------|------|---------|
| AWS OIDC auth | `Not authorized` | Verifique `github_repository` no tfvars do Terraform |
| SSH connection | `Connection refused` | SG não permite IP do runner. Veja [GitHub IP ranges](https://api.github.com/meta) |
| SSH auth | `Permission denied` | Chave SSH no secret esta completa? Incluindo `-----BEGIN/END-----` |
| EC2 health check | `Waiter InstanceStatusOk failed` | EC2 parada. `aws ec2 start-instances` |
| Helm upgrade | `timed out waiting` | Pod não fica Ready. Verifique resources e probes |
| Smoke test | `curl failed` | Aplicacao respondendo em outra porta? Verifique `targetPort` |

> **Ponto importante**: Em caso de falha no deploy, use `helm rollback webapp <revision>` para voltar ao estado anterior. O pipeline usa `--force --wait` que garante que o deploy funcione tanto no primeiro install quanto em upgrades. Para produção com releases estabelecidas, `--atomic` e recomendado para rollback automatico. Nas equipes que trabalhei, rollback manual com `helm rollback` era o procedimento padrao, com alertas automaticos no Slack/PagerDuty.

---

## Cenario 4: EC2 Inacessivel

### Severidade: Critica

### Detectar
```bash
ssh -i key ubuntu@<IP>
# Connection timed out / No route to host
```

### Mitigar
```bash
# 1. Verificar estado da EC2
aws ec2 describe-instances --instance-ids <ID> \
  --query 'Reservations[0].Instances[0].State.Name'

# 2. Se stopped, iniciar:
aws ec2 start-instances --instance-ids <ID>
aws ec2 wait instance-status-ok --instance-ids <ID>

# 3. Se terminated, reprovisionar:
cd terraform
terraform apply -var-file=inventories/dev/terraform.tfvars

# 4. IP pode ter mudado! Atualize o GitHub Secret EC2_SSH_HOST
terraform output ec2_public_ip
```

### Resolver

| Estado | Causa provavel | Acao |
|--------|----------------|------|
| `running` mas sem SSH | SG ou NACL bloqueando | Verifique SG, seu IP mudou? |
| `stopped` | Parada manual ou spot interruption | `aws ec2 start-instances` |
| `terminated` | Terminada por engano ou lifecycle | `terraform apply` recria |
| `pending` | Acabou de iniciar | Aguarde 2-3 minutos |

> **Ponto importante**: Se você esta trabalhando de casa e seu IP publico muda (ISP dinamico), o SG vai bloquear seu SSH. Solucao rapida: `curl ifconfig.me`, atualize o tfvars e `terraform apply`. Solucao melhor: use AWS SSM Session Manager que não precisa de SG inbound.

---

## Processo Pos-Incidente

Depois de resolver qualquer incidente:

1. **Documente** o que aconteceu e o que foi feito
2. **Verifique** que a aplicacao esta respondendo corretamente (runbook-validacao-deploy.md)
3. **Identifique** se existe uma prevencao (alarme, validacao, automation)
4. **Comunique** o time se o incidente afetou outros

---

## Links Uteis

- [Kubernetes Troubleshooting](https://kubernetes.io/docs/tasks/debug/)
- [Kind Known Issues](https://kind.sigs.k8s.io/docs/user/known-issues/)
- [AWS EC2 Instance States](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-lifecycle.html)
- [Helm Rollback](https://helm.sh/docs/helm/helm_rollback/)

# Runbook: Helm Chart — webapp

> Ultima atualizacao: 2025-04 | Autor: Christopher Amaral

---

## TL;DR

Chart Helm generico chamado `webapp` que deploya qualquer imagem de container no Kubernetes. Por padrao usa Nginx com pagina HTML customizavel via `customMessage`. Inclui resource limits, health probes, HPA, NetworkPolicy e values de produção.

---

## Pre-requisitos

| Ferramenta | Versao minima | Verificacao |
|------------|---------------|-------------|
| Helm | >= 3.12 | `helm version --short` |
| kubectl | >= 1.27 | `kubectl version --client` |
| Cluster K8s | Ready | `kubectl get nodes` |

---

## Inconsistencias Corrigidas no Chart Original

O chart fornecido na avaliacao possuia os seguintes problemas:

| # | Problema encontrado | Onde | O que fiz |
|---|---------------------|------|-----------|
| 1 | Indentacao YAML quebrada | `deployment.yaml` | Reestruturei toda a hierarquia YAML |
| 2 | `spec` do Pod no nivel de `metadata` | `deployment.yaml:13` | Movi `spec` para dentro de `template` (2 niveis abaixo) |
| 3 | `containers` dentro de `labels` | `deployment.yaml:17` | Movi para dentro de `spec` do Pod |
| 4 | `containerPort: 8080` | `deployment.yaml:21` | Nginx escuta na 80, não 8080. Corrigi e parametrizei |
| 5 | Service não existia | - | Criei `service.yaml` com tipo ClusterIP |
| 6 | Sem mecanismo para customizar index.html | - | Criei `configmap.yaml` com variavel `customMessage` |
| 7 | Labels não seguiam convencao K8s | `deployment.yaml:5-6` | Implementei `_helpers.tpl` com `app.kubernetes.io/*` |
| 8 | Sem resource limits | `values.yaml:7` | `resources: {}` trocado por limits e requests reais |

> **Ponto importante**: O erro #2 e #3 sao classicos quando se edita YAML sem linter. Nas equipes que participei, usamos pre-commit hooks com `yamllint` e `helm lint --strict` que pegam isso antes de chegar no PR. Recomendo fortemente configurar isso em qualquer projeto.

---

## Procedimento

### Deploy basico

```bash
# Instalar com valores padrao
helm install webapp ./charts/webapp

# Instalar com mensagem customizada
helm install webapp ./charts/webapp \
  --set customMessage="Hello World da AsapTech"

# Upgrade (atualizar mensagem)
helm upgrade webapp ./charts/webapp \
  --set customMessage="Nova mensagem - Deploy via CI/CD (Commit: abc1234)"
```

### Deploy com values de produção

```bash
helm upgrade --install webapp ./charts/webapp \
  -f ./charts/webapp/values-production.yaml \
  --set customMessage="produção - v1.0"
```

> **Ponto importante**: O `--install` no `upgrade` e essencial para idempotencia — se a release não existe, ele cria; se existe, atualiza. No pipeline uso sempre `upgrade --install --atomic` para garantir rollback automatico em caso de falha.

### Usar com outra imagem (chart generico)

O chart não e acoplado ao Nginx. Pode deployar qualquer imagem:

```bash
# httpd (Apache)
helm install meu-app ./charts/webapp \
  --set image.repository=httpd \
  --set image.tag=2.4-alpine \
  --set configMap.enabled=false

# Aplicacao Node.js custom
helm install meu-app ./charts/webapp \
  --set image.repository=meu-registry/node-api \
  --set image.tag=v2.1.0 \
  --set service.targetPort=3000 \
  --set configMap.enabled=false

# Python Flask
helm install meu-app ./charts/webapp \
  --set image.repository=meu-registry/flask-app \
  --set image.tag=latest \
  --set service.targetPort=5000 \
  --set configMap.enabled=false
```

> **Ponto importante**: Em experiênciass anteriores, trabalhei com charts genericos que cobriam 80% dos micro-servicos da empresa. Os 20% restantes (Kafka consumers, batch jobs, etc) tinham charts dedicados. Essa abordagem economiza muito tempo de manutencao e padroniza os deploys.

---

## Parametros Principais

| Parametro | Descricao | Default | produção |
|-----------|-----------|---------|----------|
| `replicaCount` | Numero de replicas | `1` | `3` |
| `image.repository` | Imagem do container | `nginx` | - |
| `image.tag` | Tag da imagem | `1.27-alpine` | - |
| `service.type` | Tipo do Service | `ClusterIP` | `ClusterIP` |
| `service.port` | Porta do Service | `80` | `80` |
| `service.targetPort` | Porta do container | `80` | `80` |
| `customMessage` | Mensagem no index.html | `Hello World da AsapTech` | - |
| `configMap.enabled` | Montar HTML customizado | `true` | `true` |
| `resources.requests.cpu` | Request de CPU | `100m` | `250m` |
| `resources.limits.cpu` | Limite de CPU | `250m` | `500m` |
| `resources.requests.memory` | Request de memoria | `128Mi` | `256Mi` |
| `resources.limits.memory` | Limite de memoria | `256Mi` | `512Mi` |
| `autoscaling.enabled` | HPA ativo | `false` | `true` |
| `autoscaling.minReplicas` | Minimo de replicas | `1` | `3` |
| `autoscaling.maxReplicas` | Maximo de replicas | `5` | `10` |
| `networkPolicy.enabled` | Network isolation | `false` | `true` |

> **Ponto importante**: Defino resources SEMPRE, mesmo em dev. Ja vivenciei cenarios onde um pod sem limits consumiu toda a memoria do node e matou outros pods por OOMKill. O `requests` define o scheduling; o `limits` define o teto. não confunda os dois.

---

## Verificacao

```bash
# Lint (validacao de sintaxe e boas praticas)
helm lint ./charts/webapp --strict

# Template (gerar manifests sem aplicar)
helm template webapp ./charts/webapp --debug

# Status dos pods
kubectl get pods -l app.kubernetes.io/name=webapp -o wide

# Logs
kubectl logs -l app.kubernetes.io/name=webapp --tail=20

# Testar resposta HTTP
kubectl port-forward svc/webapp-webapp 8080:80 &
curl -s http://localhost:8080
kill %1

# Helm release
helm list
helm get values webapp
helm history webapp
```

---

## Troubleshooting

| Problema | Diagnostico | Solucao |
|----------|-------------|---------|
| Pod CrashLoopBackOff | `kubectl logs <pod> --previous` | Porta errada? Imagem errada? Verifique `image` e `targetPort` |
| Readiness probe failing | `kubectl describe pod <pod>` | Cheque `probes.readiness.path` — o endpoint existe na imagem? |
| Pod Pending | `kubectl describe pod <pod>` | Resources insuficientes no node. Reduza limits ou use node maior |
| ConfigMap não atualiza | Verifique annotation | O checksum no deployment forca restart automatico no `upgrade` |
| `helm lint` falha | Rode `helm template --debug` | Mostra a linha exata do erro de template |
| HPA não escala | `kubectl get apiservices \| grep metrics` | metrics-server precisa estar instalado no cluster |

> **Ponto importante**: Quando um pod fica em CrashLoopBackOff, o primeiro comando e SEMPRE `kubectl logs <pod> --previous`. O `--previous` mostra o log da instancia que morreu, não da que esta tentando subir. Isso salva horas de debugging.

---

## Links Uteis

- [Helm Best Practices](https://helm.sh/docs/chart_best_practices/)
- [Kubernetes Labels Convention](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/#recommended-labels)
- [Resource Management for Pods](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Helm Template Functions](https://helm.sh/docs/chart_template_guide/function_list/)

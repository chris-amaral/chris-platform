# Runbook: ArgoCD — GitOps na chris-platform

> Ultima atualizacao: 2026-04 | Mantenedor: Christopher Amaral

---

## TL;DR

ArgoCD esta instalado no cluster Kind como parte do `bootstrap-cluster.sh` (user-data da EC2). A pasta [`argocd/`](../argocd/) contem o **AppProject** `chris-platform`, a **Application** `webapp` e o **App-of-Apps** raiz. Apos o setup inicial da infraestrutura, basta aplicar `argocd/applications/webapp.yaml` (manualmente ou pelo workflow `argocd-bootstrap.yml`) e o ArgoCD passa a reconciliar o release a partir do Git.

UI default: `http://<EC2_PUBLIC_IP>:30080`, usuario `admin`, senha extraida do secret `argocd-initial-admin-secret`.

---

## Por que ArgoCD esta aqui

Trabalhei em squads onde o deploy era o ponto mais frio do pipeline: tudo passava ate o `helm upgrade --install`, e ali a auditoria sumia. Quando o problema aparecia em produção a meia-noite, era o velho "quem fez esse deploy?" — e o Slack de plantao virava arqueologia.

GitOps, na pratica, resolve isso. Cada deploy vira um commit, cada commit tem dono, autor e diff. Adicionei ArgoCD nesse projeto justamente para dar para quem ler o repo a chance de comparar **lado a lado** o caminho push (CI faz `helm upgrade`) com o caminho pull (cluster reconcilia o Git). Os dois funcionam, mas a evolucao natural e migrar 100% para o segundo.

> **Ponto importante**: Esse modelo (push + pull coexistindo) e didatico de proposito. Em uma plataforma real, eu manteria SOMENTE pull. O motivo: eliminar SSH no pipeline, eliminar credencial sensivel no runner, e reduzir radicalmente a superficie de ataque. Em uma das empresas que passei, a adocao de ArgoCD foi o que destravou a certificacao de compliance — porque o auditor consegue ver, em um `git log`, exatamente o que entrou em produção e quando.

---

## Pre-requisitos

| Item | Como obter |
|------|------------|
| Cluster Kind rodando na EC2 | `terraform/setup.sh dev` finalizado e bootstrap `SUCCESS` |
| `kubectl` apontando para o cluster | Nativo da EC2, ou kubeconfig copiado para sua maquina |
| Acesso a porta 30080 da EC2 | Liberar no Security Group via `enable_nodeport_access = true` |

---

## Arquitetura GitOps deste projeto

```text
              GitHub (chris-amaral/chris-platform)
                       |
                       | repoURL + targetRevision: main
                       v
+----------------------+----------------------+
|              ArgoCD (no Kind)               |
|                                              |
|  AppProject: chris-platform                  |
|     ├── repos permitidos                     |
|     └── namespaces de destino                |
|                                              |
|  Application: webapp                         |
|     ├── source.path = charts/webapp          |
|     ├── helm.parameters.customMessage        |
|     └── syncPolicy: prune + selfHeal         |
+----------------------------------------------+
                       |
                       | kubectl apply (server-side)
                       v
              Cluster Kind (default ns)
              └── webapp Deployment + Service + ConfigMap
```

### Por que App-of-Apps?

O `argocd/bootstrap.yaml` e uma `Application` que aponta para a propria pasta `argocd/`. Ele descobre os manifestos dentro de `projects/` e `applications/` e os aplica como filhos. Resultado: o ArgoCD passa a se gerenciar — adicionar uma nova app no futuro vira "criar arquivo em `argocd/applications/` e dar push".

> **Ponto importante**: O App-of-Apps e uma das primeiras coisas que aprendi sobre GitOps em escala. Sem ele, voce vira um humano aplicando manifest a mao, e isso deixa de ser GitOps. Ja vi squads que tinham 200+ Applications em ArgoCD gerenciadas individualmente — toda mudanca virava um ticket. Com o pattern certo, e um arquivo .yaml em PR.

---

## Procedimento

### Cenario 1 — Bootstrap automatico (caminho normal)

```bash
# 1. Subir a infraestrutura
cd terraform && ./setup.sh dev

# 2. Aguardar o bootstrap (5-8 min). O ArgoCD ja sobe junto.
ssh -i ssh-key-dev.pem ubuntu@<EC2_IP> 'cat /var/log/bootstrap-status'
# SUCCESS = pronto

# 3. Aplicar a Application webapp (uma vez)
ssh -i ssh-key-dev.pem ubuntu@<EC2_IP> '
  kubectl apply -f https://raw.githubusercontent.com/chris-amaral/chris-platform/main/argocd/projects/chris-platform.yaml
  kubectl apply -f https://raw.githubusercontent.com/chris-amaral/chris-platform/main/argocd/applications/webapp.yaml
'
```

Ou rode o workflow manual `ArgoCD - Bootstrap (manual)` em **Actions** do GitHub, que faz exatamente isso via OIDC + SSH.

### Cenario 2 — Instalacao manual (recovery)

Se o user-data falhou por algum motivo (rede instavel no provisionamento, registry indisponivel), instale na mao:

```bash
# Na EC2
git clone https://github.com/chris-amaral/chris-platform.git
cd chris-platform
chmod +x argocd/install.sh
./argocd/install.sh
```

O `install.sh` e idempotente — rodar duas vezes nao quebra nada.

### Cenario 3 — Acessar a UI

```bash
# Pegar a senha admin
ssh -i ssh-key-dev.pem ubuntu@<EC2_IP> \
  'kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d'

# Abrir no browser
open http://<EC2_PUBLIC_IP>:30080
# Login: admin / (senha acima)
```

> **Ponto importante**: A senha inicial fica num Secret chamado `argocd-initial-admin-secret`. Em qualquer ambiente que nao seja laboratorio, eu trocaria essa senha pela autenticacao SSO/OIDC do Okta/Google da empresa, e deletaria o secret depois (`kubectl -n argocd delete secret argocd-initial-admin-secret`). Senha admin local e atalho de dev — nao deve sobreviver ate prod.

### Cenario 4 — Forcar sync manual

```bash
# Via CLI (instale com: brew install argocd)
argocd login <EC2_PUBLIC_IP>:30080 --username admin --password <SENHA> --insecure
argocd app sync webapp
argocd app wait webapp --health

# Ou via kubectl (anotacao que dispara sync)
kubectl -n argocd patch application webapp \
  --type merge \
  -p '{"operation":{"sync":{"syncStrategy":{"hook":{}},"prune":true}}}'
```

### Cenario 5 — Drift detectado

Se voce der `kubectl edit deployment webapp` na mao, o ArgoCD vai mostrar a aplicacao como **OutOfSync** e — como `selfHeal` esta ligado — em segundos restaura o estado declarado no Git.

```bash
# Ver o drift
argocd app diff webapp

# Desligar selfHeal temporariamente para investigar (NAO recomendado em prod)
kubectl -n argocd patch application webapp --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":false}}}}'
```

> **Ponto importante**: Em equipes maduras, `selfHeal` e regra. Mas existe um ritual saudavel: antes de habilitar, ja teve que ter uma boa cultura de "tudo pelo Git". Sem isso, voce gera frustracao — gente edita um pod a mao para investigar, ArgoCD reseta, gente reclama. A solucao e treino + comunicacao + entender que o Git e a fonte da verdade.

---

## Verificacao

```bash
# Status das Applications
kubectl -n argocd get applications.argoproj.io

# Saude e sync
argocd app get webapp

# Eventos recentes
kubectl -n argocd get events --sort-by='.lastTimestamp' | tail -20

# Logs do controller (se algo nao sincroniza)
kubectl -n argocd logs deploy/argocd-application-controller --tail=100
```

---

## Troubleshooting

| Sintoma | Diagnostico | Solucao |
|---------|-------------|---------|
| UI nao abre em :30080 | `kubectl -n argocd get svc argocd-server` | Confirme o NodePort e que `enable_nodeport_access = true` |
| App `Unknown` no ArgoCD | `argocd app get webapp` | Repo URL errada ou branch nao existe — confira o `targetRevision` |
| Sync travado em `OutOfSync` | `kubectl -n argocd describe application webapp` | Erro de schema, recurso imutavel — leia o `message` no status |
| `selfHeal` nao restaura drift | `automated.selfHeal: true` no spec? | Verifique syncPolicy — pode ter sido patcheado por engano |
| Senha admin perdida | Reset manual | `kubectl -n argocd patch secret argocd-secret -p '{"stringData":{"admin.password":"<bcrypt-hash>"}}'` |
| ArgoCD nao reconcilia novo commit | `pollingIntervalSeconds` (default 3min) | Use `argocd app sync webapp` ou configure webhook do Git |

> **Ponto importante**: O bug mais comum em GitOps e configurar `targetRevision: HEAD` quando o repo nao tem branch default `HEAD` — sempre uso explicito `targetRevision: main`. Pequena coisa, evita 30 minutos debugando "por que nao sincroniza".

---

## Roadmap GitOps neste lab

- [ ] Webhook do GitHub para o ArgoCD reconciliar imediatamente em vez de polling de 3 min
- [ ] Argo Image Updater para promocao automatica de tags entre dev/homol/prod
- [ ] Sealed Secrets ou External Secrets Operator (ESO) para credenciais no Git
- [ ] PR de promocao automatica entre ambientes via Argo Workflows
- [ ] Notificacoes de sync no Slack via `argocd-notifications`

---

## Links uteis

- [ArgoCD Docs](https://argo-cd.readthedocs.io/en/stable/)
- [App of Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [Sync Options](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/)
- [GitOps Principles](https://opengitops.dev/)

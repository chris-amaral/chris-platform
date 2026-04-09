# Runbook: Pipeline CI/CD — GitHub Actions

> Ultima atualizacao: 2025-04 | Autor: Christopher Amaral

---

## TL;DR

Pipeline automatizado que valida o Helm chart (lint + template dry-run), autentica na AWS via OIDC, conecta na EC2 via SSH e executa `helm upgrade --install --atomic` com a mensagem customizada contendo o commit SHA.

---

## Pre-requisitos

| Item | Obtido de |
|------|-----------|
| EC2 provisionada e com Kind rodando | `runbook-terraform-setup.md` |
| GitHub Secrets configurados | Tabela abaixo |
| OIDC Provider ativo na AWS | Modulo `iam` do Terraform |
| Repositorio com branch `main` | - |

---

## Fluxo do Pipeline

```
  Push/PR na main (somente quando charts/** muda)
       |
       v
  +---------------------+
  |    JOB: LINT         |
  |                     |
  |  1. Checkout code    |
  |  2. Setup Helm       |
  |  3. helm lint        |
  |     --strict         |
  |  4. helm template    |
  |     (default values) |
  |  5. helm template    |
  |     (prod values)    |
  +---------------------+
       |
       | (somente push na main, não PR)
       v
  +---------------------+
  |    JOB: DEPLOY       |
  |                     |
  |  1. Checkout         |
  |  2. AWS OIDC auth    |
  |  3. Setup SSH key    |
  |  4. EC2 health check |
  |  5. scp chart -> EC2 |
  |  6. ssh: helm upgrade|
  |     --install        |
  |     --atomic         |
  |  7. Rollout status   |
  |  8. Smoke test       |
  |  9. Cleanup          |
  +---------------------+
       |
       v
  +---------------------+
  |   POST-DEPLOY        |
  |  Summary (always)    |
  |  - helm list         |
  |  - kubectl get pods  |
  |  - kubectl get svc   |
  +---------------------+
```

### Quando executa o que?

| Evento | Lint | Deploy |
|--------|------|--------|
| Pull Request para `main` | Sim | não |
| Push na `main` (charts mudou) | Sim | Sim |
| Push na `main` (so terraform mudou) | não | não |
| Push em feature branch | não | não |

> **Ponto importante**: O path filter (`paths: charts/**`) e intencional. Se so o Terraform mudou, não faz sentido redeployar a aplicacao. Em projetos maiores, costumo separar workflows por tipo de mudanca — infra, app, docs. Aqui simplifiquei em um so workflow focado no chart.

---

## Autenticacao: Como Funciona

### AWS — OIDC (OpenID Connect)

não usamos `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` em nenhum lugar.

```
GitHub Actions                        AWS STS
     |                                   |
     |-- 1. JWT assinado pelo GitHub --> |
     |      (contém: repo, branch,       |
     |       audience, issuer)           |
     |                                   |-- 2. Valida JWT contra
     |                                   |      trust policy da Role
     |                                   |
     |<-- 3. Credenciais temporarias --- |
     |      (AccessKeyId, SecretKey,     |
     |       SessionToken - 1h max)      |
```

A IAM Role so aceita tokens que:
- Vem do OIDC Provider do GitHub (`token.actions.githubusercontent.com`)
- Tem audience `sts.amazonaws.com`
- Sao do repositorio configurado (`repo:owner/repo:ref:refs/heads/*`)

> **Ponto importante**: OIDC e o padrao que adoto em todas as pipelines que construo. Credenciais estaticas (access keys) representam um risco real — não expiram, podem vazar em logs, e sao dificeis de rotacionar em escala. Com OIDC, mesmo que alguem clone o workflow, não consegue assumir a role de outro repositorio. Em experiênciass anteriores, essa era uma exigencia da area de seguranca.

### EC2 — SSH

1. A chave privada SSH fica no GitHub Secret `EC2_SSH_PRIVATE_KEY`
2. O pipeline cria o arquivo `~/.ssh/deploy_key` com permissao 600
3. Usa `scp` para copiar o chart e `ssh` para executar o Helm remotamente
4. `ssh-keyscan` adiciona o host ao `known_hosts` para evitar prompt interativo

---

## GitHub Secrets

Configure em **Settings > Secrets and variables > Actions > New repository secret**:

| Secret | Como obter | Descricao |
|--------|------------|-----------|
| `AWS_ROLE_ARN` | `terraform output github_actions_role_arn` | ARN da Role OIDC |
| `EC2_INSTANCE_ID` | `terraform output ec2_instance_id` | ID da EC2 |
| `EC2_SSH_HOST` | `terraform output ec2_public_ip` | IP publico da EC2 |
| `EC2_SSH_PRIVATE_KEY` | `terraform output -raw ssh_private_key` | Chave SSH privada |

### Script rapido para extrair tudo

```bash
cd terraform
echo "=== Copie os valores abaixo para os GitHub Secrets ==="
echo ""
echo "AWS_ROLE_ARN:"
terraform output -raw github_actions_role_arn
echo ""
echo ""
echo "EC2_INSTANCE_ID:"
terraform output -raw ec2_instance_id
echo ""
echo ""
echo "EC2_SSH_HOST:"
terraform output -raw ec2_public_ip
echo ""
echo ""
echo "EC2_SSH_PRIVATE_KEY:"
terraform output -raw ssh_private_key
```

> **Ponto importante**: NUNCA cole a chave SSH em um canal do Slack, Teams ou e-mail. Use o script acima direto no terminal e copie para os Secrets. Ja presenciei situacoes onde uma chave foi compartilhada em chat e toda a infraestrutura precisou ser rotacionada. Secrets do GitHub sao encriptados em repouso e so injetados em runtime — use isso a seu favor.

---

## Mensagem Customizada (Hello World)

O pipeline injeta automaticamente no Nginx:

```
Hello World da AsapTech - Deploy realizado via CI/CD (Commit: abc1234)
```

Como funciona:
1. `${{ github.sha }}` contem o SHA completo do commit (40 chars)
2. O pipeline trunca para 7 chars: `${COMMIT_SHA:0:7}`
3. Passa como `--set customMessage="..."` no `helm upgrade`
4. O ConfigMap e recriado com a nova mensagem
5. O checksum annotation no Deployment detecta a mudanca e reinicia o pod

---

## Concurrency e Atomicidade

```yaml
concurrency:
  group: deploy-dev
  cancel-in-progress: false
```

- **concurrency group**: Apenas 1 deploy roda por vez no ambiente `dev`
- **cancel-in-progress: false**: Deploys enfileirados esperam (não cancelam o anterior)
- **--atomic**: Se o `helm upgrade` falhar, faz rollback automatico para a versao anterior

> **Ponto importante**: O `--atomic` e uma licao que aprendi na pratica. Sem ele, um deploy que falha no readiness probe deixa a release em estado "failed" e o proximo `upgrade` pode dar conflito. Com `--atomic`, se qualquer pod não ficar Ready no timeout, tudo volta ao estado anterior automaticamente. Considero obrigatorio em qualquer ambiente.

> **Ponto importante**: Este pipeline usa o modelo push-based (CI faz o deploy). A evolucao natural e migrar para pull-based com ArgoCD, onde o cluster puxa as mudancas do Git automaticamente. Isso elimina a necessidade de SSH, melhora a auditoria (cada deploy = um commit) e facilita multi-cluster. Tive experiência com ArgoCD em projetos anteriores e o ganho em rastreabilidade e rollback e significativo. Para este escopo, o modelo push atende bem e demonstra o fluxo de forma clara.

---

## Verificacao

```bash
# No GitHub: Aba Actions > "CI - Deploy K8s"

# Na EC2 (apos deploy):
ssh -i key ubuntu@<IP>
helm list                                            # Release "webapp" deployed?
kubectl get pods -l app.kubernetes.io/instance=webapp  # Pod Running?
kubectl logs -l app.kubernetes.io/instance=webapp      # Sem erros?

# Testar a mensagem
kubectl port-forward svc/webapp-webapp 8080:80 &
curl -s http://localhost:8080 | grep "Commit"        # Tem o SHA?
kill %1
```

---

## Troubleshooting

| Problema | Diagnostico | Solucao |
|----------|-------------|---------|
| OIDC: `Not authorized to perform sts:AssumeRoleWithWebIdentity` | Trust policy errada | Verifique `github_repository` no tfvars e se o OIDC Provider existe |
| SSH: `Connection refused` | SG bloqueando | GitHub runners usam IPs dinamicos. Temporariamente abra 0.0.0.0/0 no SG ou use [IP ranges do GitHub](https://api.github.com/meta) |
| SSH: `Permission denied (publickey)` | Chave errada | Confirme que `EC2_SSH_PRIVATE_KEY` contem a chave completa (incluindo BEGIN/END) |
| Helm: `timed out waiting` | Pod não fica Ready | SSH na EC2, `kubectl describe pod`, verifique resources e probes |
| Helm: `another operation in progress` | Release travada | `helm rollback webapp 0` ou `kubectl delete secret -l owner=helm` |
| Deploy não triggera | Path filter | O workflow so roda quando `charts/**` muda. Verifique `on.push.paths` |
| EC2 health check timeout | EC2 parada ou terminada | `aws ec2 describe-instances --instance-ids <ID>` — verifique o state |

> **Ponto importante**: O problema #2 (SG bloqueando GitHub runners) e o mais comum. GitHub Actions usa IPs rotativos. Para produção, a melhor solucao e usar Self-Hosted Runner na propria VPC ou SSM Run Command. Para dev, uma abertura temporaria resolve.

---

## Links Uteis

- [GitHub OIDC + AWS](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [GitHub Actions IP Ranges](https://api.github.com/meta)
- [Helm Atomic Upgrades](https://helm.sh/docs/helm/helm_upgrade/)
- [GitHub Secrets Docs](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions)
- [GitHub Actions Concurrency](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/control-the-concurrency-of-your-workflows)

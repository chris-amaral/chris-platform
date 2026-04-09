# Playbook: Rollback

> Ultima atualizacao: 2026-04 | Autor: Christopher Amaral

---

## TL;DR

Procedimentos de rollback para as 3 camadas do projeto: aplicacao (Helm), infraestrutura (Terraform) e pipeline (GitHub Actions). Cada nivel tem seu proprio mecanismo e nivel de risco.

---

## Nivel 1: Rollback de Aplicacao (Helm)

### Risco: Baixo | Tempo: ~30 segundos

O Helm mantém historico de todas as revisoes. Cada `helm upgrade` cria uma nova revisao.

```bash
# Ver historico de revisoes
helm history webapp

# Exemplo de output:
# REVISION  STATUS      DESCRIPTION
# 1         superseded  Install complete
# 2         superseded  Upgrade complete
# 3         deployed    Upgrade complete    <-- atual
```

### Rollback para revisao anterior

```bash
# Voltar para revisao 2
helm rollback webapp 2

# Voltar para a ultima revisao estavel (atalho)
helm rollback webapp 0
```

### Verificar

```bash
helm history webapp
# A revisao 4 aparece como "Rollback to 2"

kubectl get pods -l app.kubernetes.io/name=webapp
# Pod novo deve estar Running

kubectl port-forward svc/webapp 8080:80 &
curl -s http://localhost:8080
# conteúdo deve ser da revisao antiga
```

> **Ponto importante**: O `helm rollback` não apaga revisoes — ele cria uma NOVA revisao que e copia da anterior. Isso e excelente para auditoria. Em experiênciass anteriores, tinhamos regra de manter as ultimas 10 revisoes (`--history-max 10`) para não acumular secrets no etcd.

---

## Nivel 2: Rollback de Infraestrutura (Terraform)

### Risco: Alto | Tempo: variavel

Terraform não tem "rollback" nativo. As opcoes sao:

### Opcao A: Reverter o codigo e reaplicar

```bash
# Ver historico de commits no Terraform
git log --oneline terraform/

# Fazer checkout do estado anterior
git checkout <COMMIT_SHA> -- terraform/

# Reaplicar
terraform plan -var-file=inventories/dev/terraform.tfvars -out=rollback.tfplan
terraform apply rollback.tfplan
```

### Opcao B: Usar versionamento do S3

O bucket S3 tem versionamento habilitado. Se o state foi corrompido:

```bash
# Listar versoes do state
aws s3api list-object-versions \
  --bucket projeto-christopher-tfstate \
  --prefix dev/terraform.tfstate

# Restaurar versao anterior
aws s3api get-object \
  --bucket projeto-christopher-tfstate \
  --key dev/terraform.tfstate \
  --version-id <VERSION_ID> \
  terraform.tfstate.backup
```

### Opcao C: Import de recurso existente

Se um recurso foi destruido por engano e recriado manualmente:

```bash
terraform import module.compute.aws_instance.k8s_node <INSTANCE_ID>
```

> **Ponto importante**: Rollback de Terraform e perigoso porque `terraform apply` altera recursos reais. Em experiênciass anteriores, qualquer mudanca destrutiva (destroy, replace) precisa de aprovacao de 2 seniors. Minha recomendacao: NUNCA faca `terraform destroy` em produção sem antes exportar o state e ter um plano de recovery.

---

## Nivel 3: Rollback de Pipeline (GitHub Actions)

### Risco: Baixo | Tempo: ~2 minutos

Se um deploy via pipeline causou problema, ha duas opcoes:

### Opcao A: Re-rodar um workflow anterior

1. Va em **Actions** > **CI - Deploy K8s**
2. Encontre o ultimo run com sucesso
3. Clique em **Re-run all jobs**

### Opcao B: Revert do commit e novo push

```bash
# Revert do ultimo commit
git revert HEAD
git push origin main
# O pipeline roda automaticamente com o codigo revertido
```

### Opcao C: Rollback manual via SSH

```bash
ssh -i key ubuntu@<EC2_IP>
helm rollback webapp 0
```

> **Ponto importante**: A opcao C e a mais rapida para parar o sangramento. Faca o rollback do Helm primeiro, depois investigue o que deu errado no commit. Em projetos passados, tinhamos um alias `deploy-rollback` que fazia SSH + helm rollback em um comando so.

---

## Tabela de Decisao

| Situacao | Acao recomendada | Nivel |
|----------|------------------|-------|
| Mensagem errada no Nginx | `helm rollback webapp 0` | 1 |
| Pod crashando apos deploy | `helm rollback webapp 0` | 1 |
| Imagem com bug | Revert git + push (novo pipeline) | 3 |
| SG bloqueou acesso | Corrigir tfvars + `terraform apply` | 2 |
| EC2 não sobe | Verificar user-data log, `terraform apply` | 2 |
| State corrompido | Restaurar versao do S3 | 2 |

---

## Prevencao

| Pratica | Implementada? |
|---------|---------------|
| `--force --wait` no helm upgrade | Sim |
| `terraform plan` antes de apply | Sim |
| Versionamento do S3 state | Sim |
| DynamoDB lock | Sim |
| `prevent_destroy` no S3 | Sim |
| Lint obrigatorio antes de deploy | Sim |

---

## Links Uteis

- [Helm Rollback](https://helm.sh/docs/helm/helm_rollback/)
- [Terraform State Recovery](https://developer.hashicorp.com/terraform/cli/state/recover)
- [S3 Versioning](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html)
- [Git Revert](https://git-scm.com/docs/git-revert)

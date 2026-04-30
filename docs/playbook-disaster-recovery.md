# Playbook: Disaster Recovery (DR)

> Ultima atualizacao: 2026-04 | Mantenedor: chris-amaral

---

## TL;DR

Plano de recuperacao para os 4 cenarios de perda mais provaveis na chris-platform: (1) state Terraform corrompido, (2) cluster Kind perdido, (3) chave SSH comprometida, (4) conta AWS inteira indisponivel. Para cada um, o playbook traz **RTO** (tempo objetivo de recuperacao), **RPO** (tempo maximo de perda de dado aceitavel), procedimento passo a passo e o teste de validacao.

> **Ponto importante**: DR sem teste e ficcao. Aprendi isso nas equipes de pagamento que passei: a primeira vez que voce executa o procedimento de recovery e o que define se a empresa para 30 minutos ou 30 horas. Esse playbook e desenhado para ser ensaiado — pelo menos uma vez por trimestre — e nao apenas lido.

---

## Matriz de cenarios

| # | Cenario | RTO | RPO | Severidade |
|---|---------|-----|-----|------------|
| 1 | State Terraform corrompido | 15 min | 0 (versionamento S3) | Media |
| 2 | Cluster Kind morto na EC2 | 10 min | Stateless (Helm reinstala) | Baixa |
| 3 | Chave SSH vazada / comprometida | 30 min | 0 (rotacao destrutiva) | Alta |
| 4 | Conta AWS comprometida ou indisponivel | 4 h | 1 h (rebuild via IaC) | Critica |

---

## Cenario 1 — State Terraform corrompido

**Sintoma**: `terraform plan` falha com "state file is corrupted" ou erro de schema. Comum apos interrupcao no meio de um apply.

**Procedimento**:

```bash
# 1. Listar versoes do state no S3 (versionamento esta habilitado)
aws s3api list-object-versions \
  --bucket chris-platform-tfstate-<account_id> \
  --prefix dev/terraform.tfstate \
  --query 'Versions[?IsLatest!=`true`] | [0:5]'

# 2. Restaurar a versao anterior (RPO = 0 porque o S3 mantem cada apply)
aws s3api get-object \
  --bucket chris-platform-tfstate-<account_id> \
  --key dev/terraform.tfstate \
  --version-id <VERSION_ID> \
  terraform.tfstate.recovered

# 3. Validar antes de subir
terraform state list -state=terraform.tfstate.recovered

# 4. Subir
aws s3 cp terraform.tfstate.recovered \
  s3://chris-platform-tfstate-<account_id>/dev/terraform.tfstate

# 5. Re-init e plan
terraform init -backend-config=inventories/dev/backend.hcl -reconfigure
terraform plan -var-file=inventories/dev/terraform.tfvars
```

**Teste**:
```bash
# Trimestralmente, em ambiente dev:
aws s3 cp s3://chris-platform-tfstate-<account_id>/dev/terraform.tfstate \
  ./test-recovery.tfstate
terraform state list -state=./test-recovery.tfstate
# Esperado: lista todos os recursos sem erro
```

> **Ponto importante**: Versionamento de S3 e o seguro mais barato e ignorado da AWS. Em um caso que vivi, o time fez `terraform destroy` em ambiente errado por engano — recuperar o state foi o que permitiu reconstruir tudo em 20 minutos sem pedir aprovacao para refazer recursos manualmente.

---

## Cenario 2 — Cluster Kind morto na EC2

**Sintoma**: `kubectl get nodes` retorna "connection refused". Container `kind-control-plane` no Docker parou ou foi removido.

**Procedimento**:

```bash
# 1. SSH na EC2
ssh -i ssh-key-dev.pem ubuntu@<EC2_IP>

# 2. Diagnosticar
docker ps -a | grep kind
systemctl status docker
free -m && df -h

# 3a. Container existe mas parou
docker start kind-control-plane

# 3b. Container nao existe mais — recriar do zero
sudo bash -c '
  rm -f /var/log/bootstrap-status
  curl -sL https://raw.githubusercontent.com/chris-amaral/DevOps-CICD/main/terraform/modules/compute/scripts/bootstrap-cluster.sh -o /tmp/bootstrap.sh
  bash /tmp/bootstrap.sh
'

# 4. Restaurar webapp via Helm (push) ou aguardar ArgoCD reconciliar (pull)
helm upgrade --install webapp /path/to/chart --force --wait
# OU se ArgoCD ja estava la:
kubectl -n argocd patch app webapp --type merge \
  -p '{"operation":{"sync":{"prune":true}}}'

# 5. Smoke test
kubectl get pods -A
curl -s http://<EC2_IP>:30090   # webapp via NodePort, se exposto
```

**Teste**:
```bash
# Mensalmente, derrubar o cluster proposital e medir RTO
docker stop kind-control-plane && docker rm kind-control-plane
time bash /tmp/bootstrap.sh    # esperado < 10 min
```

> **Ponto importante**: O Kind e stateless por design — nada de PV importante mora no cluster do laboratorio. Quando o user-data falha por algum motivo (rede, registry indisponivel), o procedimento manual acima recupera o ambiente. Em produção, EKS resolve isso com recriacao de node group; aqui a fonte da verdade e o IaC.

---

## Cenario 3 — Chave SSH vazada ou comprometida

**Sintoma**: Identificado em log de auditoria: SSH de IP desconhecido teve sucesso. Ou voce simplesmente sabe que a chave saiu do cofre.

**Procedimento (rotacao destrutiva, ~30 min)**:

```bash
# 1. Bloquear acesso imediatamente — fechar SSH no SG
aws ec2 authorize-security-group-ingress --group-id <SG_ID> \
  --protocol tcp --port 22 --cidr 0.0.0.0/0 --dry-run   # confirme
# (Use a console pra remover regras existentes que abrem 22)

# 2. Recriar a key pair via Terraform
cd terraform
terraform taint module.compute.tls_private_key.generated[0]
terraform apply -var-file=inventories/dev/terraform.tfvars
#    Isso gera nova key, atualiza aws_key_pair, e exporta nova ssh-key-dev.pem

# 3. ATENCAO: a EC2 atual tem a chave ANTIGA no authorized_keys.
#    Para realmente revogar, ha 2 opcoes:
#
#    Opcao A (recomendada) — recriar a EC2 inteira
terraform taint module.compute.aws_instance.k8s_node
terraform apply -var-file=inventories/dev/terraform.tfvars
#
#    Opcao B (mais rapida, requer SSM ja configurado) — substituir authorized_keys via SSM
aws ssm send-command --instance-ids <ID> \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["echo \"<NOVA_PUBLIC_KEY>\" > /home/ubuntu/.ssh/authorized_keys"]'

# 4. Atualizar o GitHub Secret EC2_SSH_PRIVATE_KEY com a nova chave
gh secret set EC2_SSH_PRIVATE_KEY --body "$(cat terraform/ssh-key-dev.pem)"

# 5. Validar
ssh -i terraform/ssh-key-dev.pem ubuntu@<EC2_IP> 'echo OK'
```

**Teste**:
```bash
# Trimestralmente, simular rotacao em dev
terraform taint module.compute.tls_private_key.generated[0]
terraform plan -var-file=inventories/dev/terraform.tfvars
# Confirmar que o plan mostra: 1 to add, 0 to change, 1 to destroy
```

> **Ponto importante**: O cenario A (recriar EC2) parece exagerado mas e o unico que garante revogacao real — porque a EC2 atual nao tem mais como provar que ninguem deixou um backdoor durante a janela de exposicao. Em ambiente serio, a primeira coisa apos rotacao e auditar `~/.ssh/authorized_keys` de TODOS os usuarios e checar se algum cron novo apareceu. Por isso recomendo o caminho destrutivo.

---

## Cenario 4 — Conta AWS comprometida / indisponivel

**Sintoma**: Acesso revogado pelo Security/AWS, ou voce precisa migrar para outra conta. RTO 4h porque envolve abrir conta nova, configurar OIDC, e reaplicar IaC.

**Procedimento**:

```bash
# 1. Provisionar nova conta AWS / pegar credenciais administrativas
aws configure --profile dr
aws sts get-caller-identity --profile dr

# 2. Restaurar o backend (state e os tfvars estao no Git, entao sao recuperaveis)
git clone https://github.com/chris-amaral/DevOps-CICD.git
cd DevOps-CICD/terraform

# 3. Editar inventory para nova conta (se mudou owner/squad/regiao)
vi inventories/dev/terraform.tfvars

# 4. Bootstrap completo na nova conta (usa AWS profile dr)
AWS_PROFILE=dr ./setup.sh dev

# 5. Atualizar GitHub Secrets para os novos ARNs
gh secret set AWS_ROLE_ARN --body "$(terraform output -raw github_actions_role_arn)"
gh secret set EC2_INSTANCE_ID --body "$(terraform output -raw ec2_instance_id)"
gh secret set EC2_SSH_HOST --body "$(terraform output -raw ec2_public_ip)"
gh secret set EC2_SSH_PRIVATE_KEY --body "$(cat terraform/ssh-key-dev.pem)"

# 6. Deploy via pipeline normal
git commit --allow-empty -m "chore: trigger pipeline post-DR"
git push origin main
```

**Teste**:
- Executar em conta sandbox a cada 6 meses, do zero, com cronometro. RTO observado deve ficar abaixo de 4h.

> **Ponto importante**: Esse cenario e o que mais valoriza ter TUDO em IaC. Sem `setup.sh` e modulos parametrizados, a recuperacao em conta nova viraria semanas de cliques na console. Em uma operacao seria, eu manteria backups regulares dos states em conta separada (cross-account replication do S3) e teria uma "conta reserva" pre-bootstrapada com IAM minimo — nao e o caso desse laboratorio, mas e o proximo passo natural.

---

## Plano de testes regulares

| Cenario | Frequencia | Onde testar | Quem aprova |
|---------|-----------|-------------|-------------|
| 1 — State recovery | Trimestral | dev | Autor |
| 2 — Cluster recovery | Mensal | dev | Autor |
| 3 — SSH rotation | Trimestral | dev | Autor |
| 4 — Account rebuild | Semestral | conta sandbox | Autor + revisor |

Em cada teste, registrar:
- Data
- RTO observado vs RTO objetivo
- O que falhou ou demorou mais que esperado
- Atualizacao do playbook se algo mudou

---

## Backup adicional (defesa em profundidade)

Alem do versionamento do S3, considere — quando o projeto sair de laboratorio:

- **Cross-region replication** do bucket de state para outra regiao
- **AWS Backup** para snapshots automaticos de EBS
- **S3 Object Lock** em modo Compliance para state imutavel
- **Vault / SOPS** para a chave SSH (em vez de arquivo .pem local)

---

## Links uteis

- [Terraform State Recovery](https://developer.hashicorp.com/terraform/cli/state/recover)
- [S3 Versioning](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html)
- [AWS Backup](https://docs.aws.amazon.com/aws-backup/)
- [Disaster Recovery Pillar (Well-Architected)](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/plan-for-disaster-recovery-dr.html)

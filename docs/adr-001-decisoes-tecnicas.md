# ADR-001: Decisoes Tecnicas do Projeto

> Status: Aceito | Data: 2025-04 | Autor: Christopher Amaral

---

## Contexto

Projeto de infraestrutura como codigo para provisionar um cluster Kubernetes de desenvolvimento na AWS, com deploy automatizado via CI/CD. As decisoes abaixo foram tomadas considerando custo, complexidade, tempo de setup, seguranca e experiências profissional com as ferramentas.

---

## Decisao 1: Kind vs Minikube

**Escolha**: Kind (Kubernetes IN Docker)

| Criterio | Kind | Minikube |
|----------|------|----------|
| Dependencia | Apenas Docker | Docker ou VM driver |
| Startup time | ~30 segundos | ~2-3 minutos |
| Uso de RAM | ~1.5 GB | ~2.5 GB |
| Nested virtualization | não precisa | Precisa (VM driver) |
| Multi-node support | Nativo | Limitado |
| CI/CD friendly | Muito | Parcial |
| Persistencia apos reboot | não | Sim (VM driver) |

**Justificativa**: Em EC2 `t3.medium` (4GB RAM), o Kind e mais viavel — consome menos e inicia mais rapido. não requer virtualizacao aninhada, que seria uma limitacao em instancias que não sao `*.metal`.

> **Ponto importante**: Na minha vivência profissional, Kind se mostrou mais estavel em ambientes de CI/CD. Em uma das empresas que trabalhei, migramos de Minikube para Kind e reduzimos o tempo dos pipelines de teste em 40%. A unica desvantagem do Kind e que não sobrevive reboot, mas para dev/CI isso e aceitavel.

---

## Decisao 2: SSH vs Self-Hosted Runner vs SSM

**Escolha**: SSH com chave em GitHub Secrets

| Metodo | Pros | Contras | Quando usar |
|--------|------|---------|-------------|
| SSH | Simples, direto | IP pode mudar, SG aberto | Dev, PoC |
| Self-Hosted Runner | Sem SG inbound | Agent + manutencao | Staging, Prod |
| SSM Run Command | Zero SG inbound | IAM complexa, latencia | produção segura |

**Justificativa**: Para um cluster de desenvolvimento, SSH e o metodo mais transparente e demonstra a conexao de forma clara para avaliacao. Para produção, recomendaria SSM ou self-hosted runner.

> **Ponto importante**: Em experiênciass anteriores, usamos SSM Run Command para TUDO que envolve EC2 em produção. não existe porta 22 aberta em nenhum Security Group de produção. Para dev, SSH com key e o padrao da industria e suficiente. O importante e que a chave esteja em um secret manager e não hardcoded.

> **Ponto importante**: Em um cenario mais maduro, a evolucao natural desse modelo de deploy via SSH e migrar para GitOps com ArgoCD. Em vez do pipeline fazer SSH e executar `helm upgrade`, o ArgoCD observa o repositorio e sincroniza automaticamente o estado desejado no cluster. Tive experiência com essa abordagem e o ganho principal e auditoria completa — cada deploy e um commit no Git, com quem fez, quando e o que mudou. Para este projeto, SSH atende perfeitamente o escopo de desenvolvimento.

---

## Decisao 3: Terraform Modules vs Monolitico

**Escolha**: Modulos reusaveis com inventories por ambiente

**Justificativa**: A estrutura modular permite:
- Reusar modulos em outros projetos sem copiar codigo
- Inventories separados (dev/homol/prod) com o mesmo codigo base
- Testar e evoluir modulos individualmente
- Naming convention consistente via `locals` em cada modulo
- Dependency injection claro no `main.tf` root

> **Ponto importante**: Em projetos que participei, os modulos Terraform ficam em repositorios separados com versionamento semantico (ex: `source = "git::https://github.com/org/terraform-aws-vpc.git?ref=v2.1.0"`). Aqui usei modulos locais para simplificar, mas a estrutura interna e a mesma. Cada modulo tem `main.tf`, `variables.tf` e `outputs.tf` — esse e o contrato padrao que todo modulo Terraform deve seguir.

---

## Decisao 4: OIDC vs Access Keys para GitHub Actions

**Escolha**: OIDC (OpenID Connect)

| Criterio | OIDC | Access Keys |
|----------|------|-------------|
| Credenciais estaticas | não | Sim |
| Expiracao | ~1 hora | Nunca (ate rotacionar) |
| Risco de vazamento | Baixo | Alto |
| Rotacao | Automatica | Manual |
| restrição por repo/branch | Sim | não |

**Justificativa**: Credenciais estaticas sao um risco de seguranca significativo. OIDC gera credenciais temporarias, não armazena secrets permanentes na AWS, e permite restrição por repositorio e branch.

---

## Decisao 5: Ubuntu 22.04 vs Amazon Linux 2023

**Escolha**: Ubuntu 22.04 LTS (Jammy Jellyfish)

**Justificativa**: Kind e Helm tem documentacao e testes mais maduros no Ubuntu. O script de bootstrap usa `apt` que e nativo. Amazon Linux usaria `dnf` com nomes de pacotes diferentes. Ubuntu LTS tem suporte ate abril de 2027.

> **Ponto importante**: Em algumas empresas que trabalhei, usavamos Amazon Linux 2 por padrao (recomendacao da AWS). Em outras, Ubuntu. Para Kind especificamente, Ubuntu e mais estavel — tive problemas com cgroups v2 no Amazon Linux 2023 que não existem no Ubuntu 22.04 usando Golden Image, mas depois foi migrando para BottleRocket em EKS e ECS.

---

## Decisao 6: t3.medium como Instance Type

**Escolha**: t3.medium (2 vCPU, 4GB RAM)

| Instance | vCPU | RAM | Custo/hora (us-east-1) | Suficiente para Kind? |
|----------|------|-----|------------------------|----------------------|
| t3.small | 2 | 2GB | ~$0.02 | Apertado |
| t3.medium | 2 | 4GB | ~$0.04 | Sim (dev) |
| t3.large | 2 | 8GB | ~$0.08 | Confortavel |

**Justificativa**: Kind + 1 control-plane consome ~1.5GB RAM + Docker overhead. O `t3.medium` oferece margem para Helm deploys e operacoes do kubectl.

> **Ponto importante**: Para produção com multi-node Kind ou workloads mais pesados, eu usaria `t3.large` no minimo. O `t3.medium` e o sweet spot para dev — barato o suficiente para deixar rodando e com recursos para não dar OOMKill.

---

## Decisao 7: Chart Generico vs Especifico

**Escolha**: Chart `webapp` generico que aceita qualquer imagem

**Justificativa**: Em vez de criar um chart acoplado ao Nginx, criei um chart generico com `configMap.enabled` que pode ser desligado para imagens com seu proprio conteúdo. Isso permite reusar o mesmo chart para diferentes aplicacoes.

> **Ponto importante**: Em experiências anteriores, tinhamos um chart generico chamado `service-template` que cobria 80% dos micro-servicos (APIs REST, workers, etc). Os 20% restantes tinham charts dedicados (Kafka consumers com particularidades, batch jobs com CronJob, etc). Esse pattern economiza centenas de horas de manutencao por ano. Aqui apliquei o mesmo principio.

---

## Decisao 8: Inventories com Backend Parcial

**Escolha**: `backend "s3" {}` vazio no `backend.tf` + `backend.hcl` por ambiente

**Justificativa**: Permite trocar de ambiente com `terraform init -backend-config=inventories/<env>/backend.hcl -reconfigure` sem editar codigo. Cada ambiente tem seu proprio state file no S3, isolando completamente os ambientes.

> **Ponto importante**: Esse pattern e inspirado no Ansible (que usa `inventories/` da mesma forma). Em outras oportunidades, usavamos workspaces do Terraform, mas inventories com partial config e mais explicito e menos propenso a erros. Ja vi gente aplicar no ambiente errado porque esqueceu de trocar o workspace. Com inventories, você sempre sabe em qual ambiente esta pelo comando que digitou.

---

## Decisao 9: Deploy Atomico com --atomic

**Escolha**: `helm upgrade --install --atomic --wait`

**Justificativa**: A flag `--atomic` garante que se qualquer parte do deploy falhar (pod não fica Ready, probe falha, timeout), o Helm faz rollback automatico para a versao anterior. Sem ela, um deploy falhado deixa a release em estado inconsistente.

> **Ponto importante**: Aprendi a importancia do `--atomic` em um projeto anterior quando um deploy com imagem quebrada ficou stuck em "pending-upgrade" e impediu deploys subsequentes por 2 horas ate alguem fazer rollback manual. Desde entao, `--atomic` e obrigatorio em todos os projetos que trabalho.

---

## Links

- [ADR (Architecture Decision Records)](https://adr.github.io/)
- [Kind Design Principles](https://kind.sigs.k8s.io/docs/design/initial/)
- [GitHub OIDC Best Practices](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [Terraform Module Structure](https://developer.hashicorp.com/terraform/language/modules/develop/structure)

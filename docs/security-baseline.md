# Security Baseline

> Ultima atualizacao: 2026-04 | Autor: Christopher Amaral

---

## TL;DR

Documento de referencia com todos os controles de seguranca implementados no projeto, organizados por camada. Serve como checklist para auditorias, onboarding e revisao de seguranca.

> **Ponto importante**: Em todo projeto que trabalhei ao longo da carreira, o security baseline era o primeiro documento criado e o ultimo revisado antes de ir para produção. Ele responde a pergunta: "O que estamos fazendo para proteger esse ambiente?". Mesmo em dev, a resposta não pode ser "nada".

---

## Camada: AWS / Terraform

| # | Controle | Status | Implementacao | Arquivo |
|---|----------|--------|---------------|---------|
| 1 | OIDC (zero static keys) | OK | GitHub Actions autentica via JWT temporario | `modules/iam/main.tf` |
| 2 | IMDSv2 enforced | OK | `http_tokens = "required"` | `modules/compute/main.tf` |
| 3 | EBS encryption | OK | `encrypted = true` no root volume | `modules/compute/main.tf` |
| 4 | S3 encryption | OK | AES256 server-side com bucket key | `modules/storage/main.tf` |
| 5 | S3 public access block | OK | 4 camadas de bloqueio ativas | `modules/storage/main.tf` |
| 6 | S3 versioning | OK | Habilitado para rollback de state | `modules/storage/main.tf` |
| 7 | DynamoDB lock | OK | Previne corrupcao concorrente | `modules/storage/main.tf` |
| 8 | SG least-privilege | OK | SSH/K8s API restritos a CIDRs | `modules/security/main.tf` |
| 9 | SG dynamic blocks | OK | Regras so criadas se CIDRs informados | `modules/security/main.tf` |
| 10 | IAM least-privilege | OK | EC2: SSM only; GH: EC2 describe + SSM | `modules/iam/main.tf` |
| 11 | Default tags | OK | Owner, Squad, Environment em tudo | `main.tf` (locals) |
| 12 | prevent_destroy | OK | S3 bucket protegido | `modules/storage/main.tf` |
| 13 | Outputs sensiveis | OK | SSH key marcada como `sensitive` | `outputs.tf` |

> **Ponto importante**: O item #2 (IMDSv2) e frequentemente ignorado, mas e critico. O SSRF do Capital One em 2019 explorou exatamente o IMDSv1 para roubar credenciais IAM do EC2. Com IMDSv2, o atacante precisa de um token de sessao, o que torna o ataque muito mais dificil. Nas equipes que trabalhei, IMDSv2 e obrigatorio em 100% das instancias.

---

## Camada: Kubernetes / Helm

| # | Controle | Status | Implementacao | Arquivo |
|---|----------|--------|---------------|---------|
| 1 | Resource limits | OK | CPU e memoria com requests e limits | `values.yaml` |
| 2 | Liveness probe | OK | Restart automatico em falha | `deployment.yaml` |
| 3 | Readiness probe | OK | Remove pod se não pronto | `deployment.yaml` |
| 4 | NetworkPolicy | OK | Restringe ingress (quando habilitado) | `networkpolicy.yaml` |
| 5 | ConfigMap checksum | OK | Pod reinicia em mudancas de config | `deployment.yaml` |
| 6 | imagePullPolicy | OK | `IfNotPresent` para eficiencia | `values.yaml` |
| 7 | Labels padrao K8s | OK | `app.kubernetes.io/*` | `_helpers.tpl` |
| 8 | HPA (opcional) | OK | Escala por CPU e memoria | `hpa.yaml` |

> **Ponto importante**: Resource limits (item #1) e provavelmente o controle mais importante em Kubernetes. Sem limits, um pod pode consumir todos os recursos do node e matar outros pods via OOMKill. Vi isso acontecer em produção — um servico com memory leak derrubou 12 outros servicos no mesmo node. Desde entao, limits e obrigatorio em qualquer chart que eu crio.

---

## Camada: CI/CD

| # | Controle | Status | Implementacao | Arquivo |
|---|----------|--------|---------------|---------|
| 1 | OIDC authentication | OK | Zero credenciais AWS em secrets | `ci-deploy-k8s.yml` |
| 2 | GitHub Secrets | OK | SSH key e ARNs encriptados | GitHub Settings |
| 3 | Lint obrigatorio | OK | `helm lint --strict` | `ci-deploy-k8s.yml` |
| 4 | Deploy apenas na main | OK | Condicional no job | `ci-deploy-k8s.yml` |
| 5 | Deploy protegido | OK | `--force --wait` com timeout de 120s | `ci-deploy-k8s.yml` |
| 6 | Concurrency control | OK | 1 deploy por vez | `ci-deploy-k8s.yml` |
| 7 | Path filter | OK | So roda quando charts muda | `ci-deploy-k8s.yml` |
| 8 | Smoke test | OK | curl pos-deploy | `ci-deploy-k8s.yml` |
| 9 | Cleanup | OK | Remove chart temporario | `ci-deploy-k8s.yml` |
| 10 | SSH key permissao | OK | chmod 600 no pipeline | `ci-deploy-k8s.yml` |

> **Ponto importante**: O item #6 (concurrency control) e subestimado. Sem ele, dois pushes rapidos na main podem causar deploys simultaneos que conflitam. Em experiênciass anteriores, tivemos um incidente onde dois deploys rodaram em paralelo e deixaram o Helm em estado inconsistente. Desde entao, `concurrency.group` e padrao.

---

## Camada: Repositorio

| # | Controle | Status | Implementacao | Arquivo |
|---|----------|--------|---------------|---------|
| 1 | .gitignore completo | OK | Nunca commita state, keys, tfvars | `.gitignore` |
| 2 | Sem secrets no codigo | OK | Tudo via variaveis e GitHub Secrets | Todos |
| 3 | Inventories separados | OK | tfvars por ambiente | `inventories/` |
| 4 | Exemplo sem valores reais | OK | CIDRs e repos com placeholders | `terraform.tfvars` |

---

## Melhorias Futuras (roadmap de seguranca)

| Prioridade | Melhoria | Impacto | Complexidade | Quando implementar |
|------------|----------|---------|--------------|-------------------|
| Alta | Trivy scan no pipeline | Detecta CVEs em imagens | Baixa | Sprint 1 |
| Alta | Secrets rotation automatica | Reduz janela de exposicao | Media | Sprint 2 |
| Media | AWS GuardDuty | Deteccao de ameacas | Baixa | Sprint 2 |
| Media | OPA/Gatekeeper | Policy as code no cluster | Media | Sprint 3 |
| Media | Falco | Runtime security K8s | Media | Sprint 3 |
| Baixa | VPN/Bastion para SSH | Elimina IP publico | Alta | Sprint 4 |
| Baixa | HashiCorp Vault | Secrets management centralizado | Alta | Sprint 5 |
| Media | ArgoCD (GitOps) | Deploy auditavel, pull-based, sem SSH | Media | Sprint 3 |

> **Ponto importante**: Se eu tivesse que priorizar uma unica melhoria, seria Trivy scan. E trivial de implementar (3 linhas no workflow) e pega vulnerabilidades criticas nas imagens base. Nas equipes que trabalhei, TODA imagem passa por scan antes de ir para produção. Uma imagem com CVE critica e barrada automaticamente.

Exemplo de como adicionar Trivy ao pipeline:
```yaml
- name: Trivy scan
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: 'nginx:1.27-alpine'
    severity: 'CRITICAL,HIGH'
    exit-code: '1'
```

> **Ponto importante**: Sobre ArgoCD na tabela acima — alem da rastreabilidade, o maior ganho de seguranca do GitOps e eliminar a necessidade de credenciais SSH no pipeline. O cluster puxa as mudancas do repositorio, invertendo o modelo. Em experiências anteriores, a adocao de ArgoCD reduziu a superficie de ataque e simplificou o compliance, porque cada deploy virou um commit auditavel no Git.

---

## Links

- [AWS Well-Architected Security Pillar](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [OWASP K8s Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Kubernetes_Security_Cheat_Sheet.html)
- [Trivy](https://trivy.dev/)
- [Falco](https://falco.org/)
- [OPA Gatekeeper](https://open-policy-agent.github.io/gatekeeper/)
- [IMDSv2 (Capital One incident context)](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-service.html)

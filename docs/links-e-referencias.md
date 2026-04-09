# Links e Referencias

> Ultima atualizacao: 2026-04 | Autor: Christopher Amaral

---

## TL;DR

Pagina centralizada com todos os links de documentacao oficial, tutoriais e ferramentas utilizadas neste projeto. Organizado por tecnologia.

> **Ponto importante**: Mantenho uma pagina de links em todo projeto que trabalho. Em experiênciass anteriores, isso ficava no Confluence ou no Notion, dependendo da empresa. Ter tudo centralizado evita perder tempo procurando no Google. Esses links foram curados ao longo de 6 anos de experiências com essas ferramentas.

---

## AWS

### Documentacao Oficial

| Recurso | Link |
|---------|------|
| AWS CLI Reference | https://docs.aws.amazon.com/cli/latest/reference/ |
| EC2 User Guide | https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ |
| EC2 Instance Types | https://aws.amazon.com/ec2/instance-types/ |
| VPC User Guide | https://docs.aws.amazon.com/vpc/latest/userguide/ |
| IAM User Guide | https://docs.aws.amazon.com/IAM/latest/UserGuide/ |
| S3 User Guide | https://docs.aws.amazon.com/AmazonS3/latest/userguide/ |
| S3 Versioning | https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html |
| DynamoDB Developer Guide | https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/ |
| Security Groups | https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-groups.html |
| IMDSv2 | https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-service.html |
| OIDC Identity Providers | https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html |

### Seguranca AWS

| Recurso | Link |
|---------|------|
| Well-Architected Security Pillar | https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/ |
| IAM Best Practices | https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html |
| AWS Security Hub | https://docs.aws.amazon.com/securityhub/latest/userguide/ |
| GuardDuty | https://docs.aws.amazon.com/guardduty/latest/ug/ |

### Pricing

| Recurso | Link |
|---------|------|
| EC2 Pricing | https://aws.amazon.com/ec2/pricing/ |
| S3 Pricing | https://aws.amazon.com/s3/pricing/ |
| AWS Calculator | https://calculator.aws/ |

> **Ponto importante**: Sempre consulte o pricing ANTES de escolher o instance type. Em uma empresa que trabalhei, tivemos um susto quando um dev deixou instancias `m5.4xlarge` rodando no weekend. Resultado: fatura inesperada altissima. Hoje em dia, coloco alarmes de billing em todo projeto.

---

## Terraform

### Documentacao Oficial

| Recurso | Link |
|---------|------|
| Terraform Docs | https://developer.hashicorp.com/terraform/docs |
| AWS Provider | https://registry.terraform.io/providers/hashicorp/aws/latest/docs |
| TLS Provider | https://registry.terraform.io/providers/hashicorp/tls/latest/docs |
| S3 Backend | https://developer.hashicorp.com/terraform/language/settings/backends/s3 |
| Modules | https://developer.hashicorp.com/terraform/language/modules |
| Variables | https://developer.hashicorp.com/terraform/language/values/variables |
| Outputs | https://developer.hashicorp.com/terraform/language/values/outputs |
| State Management | https://developer.hashicorp.com/terraform/language/state |
| Import | https://developer.hashicorp.com/terraform/cli/import |

### Best Practices

| Recurso | Link |
|---------|------|
| Style Guide | https://developer.hashicorp.com/terraform/language/style |
| Module Best Practices | https://developer.hashicorp.com/terraform/language/modules/develop |
| State Locking | https://developer.hashicorp.com/terraform/language/state/locking |

### Troubleshooting

| Recurso | Link |
|---------|------|
| Debugging | https://developer.hashicorp.com/terraform/internals/debugging |
| State Recovery | https://developer.hashicorp.com/terraform/cli/state/recover |
| Force Unlock | https://developer.hashicorp.com/terraform/cli/commands/force-unlock |

> **Ponto importante**: O link mais util do Terraform na minha experiências e o de State Recovery. Em projetos que participei, ja precisamos restaurar state corrompido 3 vezes. O versionamento do S3 salvou cada uma delas. SEMPRE habilite versionamento no bucket de state.

---

## Kubernetes

### Documentacao Oficial

| Recurso | Link |
|---------|------|
| Kubernetes Docs | https://kubernetes.io/docs/home/ |
| kubectl Reference | https://kubernetes.io/docs/reference/kubectl/ |
| kubectl Cheat Sheet | https://kubernetes.io/docs/reference/kubectl/quick-reference/ |
| Deployments | https://kubernetes.io/docs/concepts/workloads/controllers/deployment/ |
| Services | https://kubernetes.io/docs/concepts/services-networking/service/ |
| ConfigMaps | https://kubernetes.io/docs/concepts/configuration/configmap/ |
| Resource Management | https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/ |
| Network Policies | https://kubernetes.io/docs/concepts/services-networking/network-policies/ |
| HPA | https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/ |
| Probes | https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/ |
| Labels Convention | https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/#recommended-labels |

### Troubleshooting

| Recurso | Link |
|---------|------|
| Debug Pods | https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/ |
| Debug Services | https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/ |
| Troubleshoot Clusters | https://kubernetes.io/docs/tasks/debug/debug-cluster/ |
| Application Introspection | https://kubernetes.io/docs/tasks/debug/debug-application/ |

### Seguranca

| Recurso | Link |
|---------|------|
| CIS Benchmark | https://www.cisecurity.org/benchmark/kubernetes |
| OWASP K8s Cheat Sheet | https://cheatsheetseries.owasp.org/cheatsheets/Kubernetes_Security_Cheat_Sheet.html |
| Pod Security Standards | https://kubernetes.io/docs/concepts/security/pod-security-standards/ |

---

## Helm

| Recurso | Link |
|---------|------|
| Helm Docs | https://helm.sh/docs/ |
| Chart Best Practices | https://helm.sh/docs/chart_best_practices/ |
| Template Functions | https://helm.sh/docs/chart_template_guide/function_list/ |
| helm upgrade | https://helm.sh/docs/helm/helm_upgrade/ |
| helm rollback | https://helm.sh/docs/helm/helm_rollback/ |
| Troubleshooting | https://helm.sh/docs/faq/troubleshooting/ |

---

## Kind

| Recurso | Link |
|---------|------|
| Kind Docs | https://kind.sigs.k8s.io/docs/user/quick-start/ |
| Configuration | https://kind.sigs.k8s.io/docs/user/configuration/ |
| Known Issues | https://kind.sigs.k8s.io/docs/user/known-issues/ |
| Ingress | https://kind.sigs.k8s.io/docs/user/ingress/ |
| Local Registry | https://kind.sigs.k8s.io/docs/user/local-registry/ |

---

## GitHub Actions

| Recurso | Link |
|---------|------|
| Docs | https://docs.github.com/en/actions |
| OIDC with AWS | https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services |
| Secrets | https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions |
| Concurrency | https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/control-the-concurrency-of-your-workflows |
| Environments | https://docs.github.com/en/actions/managing-workflow-runs-and-deployments/managing-deployments/managing-environments-for-deployment |
| IP Ranges (API) | https://api.github.com/meta |

---

## Docker

| Recurso | Link |
|---------|------|
| Docker Docs | https://docs.docker.com/ |
| Install on Ubuntu | https://docs.docker.com/engine/install/ubuntu/ |
| Dockerfile Reference | https://docs.docker.com/reference/dockerfile/ |
| Docker Compose | https://docs.docker.com/compose/ |

---

## Ferramentas Complementares

| Ferramenta | Uso | Link |
|------------|-----|------|
| Metrics Server | Metricas de CPU/memoria para HPA | https://github.com/kubernetes-sigs/metrics-server |
| KEDA | Autoscaling event-driven | https://keda.sh/ |
| Trivy | Scan de vulnerabilidades em imagens | https://trivy.dev/ |
| Falco | Runtime security no K8s | https://falco.org/ |
| OPA/Gatekeeper | Policy as code | https://open-policy-agent.github.io/gatekeeper/ |
| k9s | TUI para Kubernetes | https://k9scli.io/ |
| Lens | IDE para Kubernetes | https://k8slens.dev/ |

> **Ponto importante**: Se você vai trabalhar com Kubernetes no dia a dia, instale o `k9s`. E um terminal UI que substitui 90% dos comandos `kubectl` manuais. Nas minhas experiênciass anteriores, era a primeira ferramenta que eu instalava em qualquer maquina nova. `brew install derailed/k9s/k9s` ou `snap install k9s`.

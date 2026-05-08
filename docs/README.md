# Documentacao — chris-platform

> Indice consolidado da documentacao tecnica do projeto. Cada documento foi escrito para resolver um cenario real, com TL;DR no topo, procedimento detalhado no meio, troubleshooting no rodape e — sempre que cabe — uma historia rapida sobre o **porque** daquela escolha.
>
> Mantenedor: chris-amaral — [LinkedIn](https://www.linkedin.com/in/christopher-amaral-6788b0359)

---

## Como navegar

- **Quero entender o projeto** → comece pelo [README principal](../README.md), depois leia o [ADR-001](adr-001-decisoes-tecnicas.md).
- **Quero subir o ambiente agora** → [Guia passo a passo](GUIA-PASSO-A-PASSO.md) + [Runbook Terraform](runbook-terraform-setup.md).
- **Quebrou alguma coisa** → [Playbook de incidentes](playbook-incident-response.md), depois [Rollback](playbook-rollback.md).
- **Quero auditar seguranca** → [Security baseline](security-baseline.md).
- **Quero entender o GitOps** → [Runbook ArgoCD](runbook-argocd.md).

---

## Mapa por tipo de documento

### Runbooks — passo a passo de operacoes recorrentes

| Documento | Quando usar |
|-----------|-------------|
| [Arquitetura (diagramas Mermaid)](architecture.md) | Onboarding rapido de quem nunca viu o repo |
| [Runbook Terraform](runbook-terraform-setup.md) | Provisionar, evoluir ou destruir a infraestrutura AWS |
| [Runbook Helm chart](runbook-helm-chart.md) | Mexer no chart `webapp`, mudar parametros, debugar valores |
| [Runbook CI/CD pipeline](runbook-ci-cd-pipeline.md) | Entender o workflow, GitFlow, OIDC e Secrets |
| [Runbook ArgoCD](runbook-argocd.md) | Instalar/gerenciar GitOps, App-of-Apps, sync e drift |
| [Runbook Observabilidade](runbook-observability.md) | Subir Prometheus + Grafana + Loki via ArgoCD |
| [Runbook Validacao de deploy](runbook-validacao-deploy.md) | Checklist pos-deploy para confirmar saude |

### Playbooks — resposta a cenarios criticos

| Documento | Severidade tipica |
|-----------|-------------------|
| [Playbook Incident Response](playbook-incident-response.md) | Pod CrashLoop, cluster offline, EC2 down |
| [Playbook Rollback](playbook-rollback.md) | Reverter app (Helm), infra (Terraform) ou pipeline |
| [Playbook Scaling & performance](playbook-scaling-performance.md) | Latencia alta, pods Pending, autoscaling |
| [Playbook Disaster Recovery](playbook-disaster-recovery.md) | State perdido, EC2 morta, conta AWS comprometida |

### Decisoes e referencias

| Documento | Para que serve |
|-----------|---------------|
| [ADR-001 Decisoes tecnicas](adr-001-decisoes-tecnicas.md) | Por que Kind, OIDC, m7i-flex.large, partial backend, etc. |
| [Security baseline](security-baseline.md) | Checklist de controles por camada (AWS, K8s, CI/CD, repo) |
| [Cost Explorer automation](cost-explorer-automation.md) | Padrao de relatorio de custo via Python+OIDC com observacoes de campo |
| [Guia passo a passo](GUIA-PASSO-A-PASSO.md) | Validacao end-to-end, da clonagem ao curl no pod |
| [Links e referencias](links-e-referencias.md) | Documentacao oficial curada por tecnologia |

---

## Convencoes que sigo nessa documentacao

Aprendi essas regras na pratica, errando primeiro, e elas sao a razao da documentacao deste repo nao virar um cemiterio:

1. **TL;DR no topo.** Quem chegou aqui as 3 da manha em call de incidente nao tem tempo de ler 5 paginas. O resumo entrega o caminho rapido em duas linhas.
2. **`Ponto importante:` ao longo do texto.** Sao callouts onde escrevo o que aprendi a duras penas — desde a 4xlarge esquecida no fim de semana ate o servico que derrubou outros 12 por OOMKill no mesmo node. E o que diferencia um runbook util de um copy-paste de comandos.
3. **Tabela de troubleshooting com `Sintoma -> Diagnostico -> Solucao`.** Em incidente, quem precisa do runbook nao quer prosa. Tabela direta, comando pronto para copiar.
4. **Toda escolha tem ADR.** Se eu decidi `m7i-flex.large` em vez de `t3.micro`, o motivo esta no ADR-001. Decisao sem registro vira cargo cult em 6 meses.
5. **Datas absolutas, nunca relativas.** Quando algo foi feito "semana passada", em 2 anos ninguem entende. As datas no historico sao sempre `2026-04-30`.

---

## Como contribuir

Se voce esta lendo isto em uma squad nova, em uma entrevista ou em uma banca, e tem feedback honesto, abra issue ou me chame no [LinkedIn](https://www.linkedin.com/in/christopher-amaral-6788b0359). Documentacao boa e produto vivo: revisada, evoluida, lida.

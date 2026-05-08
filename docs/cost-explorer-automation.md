# Padrao: Automacao de Cost Explorer via Python + OIDC

> Documento de referencia (teorico). O workflow correspondente foi desativado neste lab por escolha pratica — ver "Por que nao esta ativo" no fim. O script `scripts/aws_cost_report.py` continua versionado como artefato de estudo.
>
> Mantenedor: chris-amaral

---

## TL;DR

Esse documento descreve como construir um relatorio diario de custo AWS rodando 100% serverless: GitHub Actions agendado via cron → autenticacao OIDC → script Python que chama Cost Explorer → JSON publicado como artifact (ou enviado para Slack/Teams). Reproduz, em escala de bancada, automacoes operacionais que entreguei em banco de varejo da America Latina.

A intencao aqui e **teorica**: o codigo esta no repositorio (`scripts/aws_cost_report.py`), mas o workflow GitHub Actions foi removido para nao gerar custo de runner recorrente em laboratorio sem trafego real. As observacoes ao longo deste doc descrevem armadilhas que so aparecem quando se executa de verdade, em conta nova.

---

## Arquitetura

```text
+------------------+    cron diario    +-----------------+
| GitHub Actions   |<-- 09:00 UTC ----| schedule trigger |
| cost-report.yml  |                   +-----------------+
+--------+---------+
         |
         | 1. JWT OIDC (id-token: write)
         v
+------------------+
|   AWS STS        |
|  AssumeRoleWith- |
|  WebIdentity     |
+--------+---------+
         |
         | 2. credenciais temporarias (1h)
         v
+------------------+
| boto3 Cost       |
| Explorer client  |---> 3. GetCostAndUsage agrupado por SERVICE + tag Project
+--------+---------+
         |
         | 4. JSON estruturado
         v
+------------------+
| Action artifact  |---> consumido por runs futuros, dashboards, ou Slack hook
+------------------+
```

---

## Por que essa arquitetura

| Atributo | O que essa stack entrega | Alternativa que eu considerei |
|----------|--------------------------|-------------------------------|
| Sem credencial estatica | OIDC AssumeRoleWithWebIdentity expira em 1h | Access Key armazenada em secret (vaza, expira nunca) |
| Custo do scheduling | Free Tier do GitHub Actions cobre cron diario | EventBridge + Lambda (paga ~US$0.20/mes mesmo idle) |
| Linguagem | Python boto3 — ecossistema robusto, fluencia da equipe | Bash + AWS CLI funciona, mas parsing JSON fica fragil |
| Output | JSON estruturado como artifact (retencao 30d) | Email com HTML — fica orfao, dificil de parsear depois |
| Audit | Cada run no GitHub Actions tem log + autor + commit SHA | Crontab numa EC2 — invisivel pra resto do time |

> **Observacao de campo**: em uma equipe de 12 pessoas, esse padrao economizou ~3h/semana de "alguem abre o Cost Explorer no console e tira screenshot pro time". Output em JSON viabilizou alimentar um dashboard no Grafana com um painel "Top 5 servicos da semana".

---

## Walkthrough do codigo

O script `scripts/aws_cost_report.py` tem ~150 linhas em 5 funcoes. Vale ler na ordem:

### `_parse_args()` — interface de linha de comando

```python
parser.add_argument("--days", type=int, default=7)
parser.add_argument("--tag-key", default="Project")
parser.add_argument("--region", default="us-east-1")
parser.add_argument("--output", type=str, default=None)
```

Defaults conservadores: 7 dias (suficiente para spotting trend, sem estourar pageSize do CE), tag `Project` (alinhada com a tag obrigatoria que o `setup.sh` aplica em todos os recursos).

> **Observacao**: Cost Explorer aceita ate 14 dimensoes por GroupBy, mas a API limita a 2 simultaneos. Por isso uso `SERVICE` + `tag:Project` — cobre 90% das perguntas que se faz ao olhar custo ("quem gastou?" e "no que gastou?").

### `_fetch_costs()` — chamada principal

```python
client.get_cost_and_usage(
    TimePeriod={"Start": ..., "End": ...},
    Granularity="DAILY",
    Metrics=["UnblendedCost"],
    GroupBy=[
        {"Type": "DIMENSION", "Key": "SERVICE"},
        {"Type": "TAG", "Key": tag_key},
    ],
)
```

Por que `UnblendedCost` e nao `BlendedCost`? Em conta unica nao faz diferenca. Em organizations com Reserved Instances compartilhadas, `Unblended` mostra o custo real da conta; `Blended` distribui as savings de RI por toda a org. Para auditoria de quem gastou o que, `Unblended` e o correto.

> **Observacao**: ja vi time gastar 2h debatendo "porque o numero do CE nao bate com o do CSV de billing" — era exatamente isso. Documentei a escolha aqui pra evitar a discussao de novo.

### `_summarize()` — agrega por servico e por tag

```python
total = sum(row["amount"] for row in rows)
by_service = sorted(by_service.items(), key=lambda kv: kv[1], reverse=True)[:5]
by_tag = sorted(by_tag.items(), key=lambda kv: kv[1], reverse=True)[:5]
```

Top 5 e suficiente para alerta diario. Se quiser long-tail completo, o JSON tem `rows` com tudo.

### `_print_human()` + saida JSON

Dois canais: stdout legivel pra olho humano (Slack ou logs do CI), JSON estruturado para consumo por outros sistemas. Padrao "human-friendly + machine-friendly" que sempre uso em scripts de automacao.

### Tratamento de erro inteligente

```python
except ClientError as exc:
    msg = str(exc)
    if "not enabled for cost explorer" in msg.lower():
        sys.stderr.write("Cost Explorer NAO esta ativado nesta conta AWS.\n...")
    elif "AccessDenied" in msg:
        sys.stderr.write("Permissao IAM insuficiente...\n...")
    else:
        sys.stderr.write(f"Erro chamando Cost Explorer: {exc}\n")
```

Em vez de cuspir o stack trace do boto3, identifica os 2 erros mais comuns e mostra o caminho de resolucao. Mensagem de erro como produto, nao como diagnostico.

---

## Workflow GitHub Actions de referencia

O arquivo `.github/workflows/cost-report.yml` (removido neste lab) seguiria esta forma:

```yaml
name: AWS - Daily Cost Report

on:
  schedule:
    - cron: "0 9 * * *"   # 09:00 UTC = 06:00 BRT
  workflow_dispatch:
    inputs:
      days:
        description: "Janela em dias"
        default: "7"

permissions:
  id-token: write    # OIDC
  contents: read

jobs:
  report:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
          cache: pip
      - run: pip install -r scripts/requirements.txt
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: us-east-1
      - run: python scripts/aws_cost_report.py --days ${{ inputs.days || 7 }} --output cost.json
      - uses: actions/upload-artifact@v4
        with:
          name: cost-report-${{ github.run_id }}
          path: cost.json
          retention-days: 30
```

---

## Pre-requisitos para rodar de verdade

Esses sao os tropecos que aparecem na primeira execucao em conta nova. Documentando para que voce nao precise aprender errando.

### 1. Cost Explorer ATIVADO no console AWS

Cost Explorer nao vem ligado por default em conta nova. Antes da primeira chamada API funcionar, alguem com permissao de billing precisa abrir o console e clicar em **"Launch Cost Explorer"**:

[https://console.aws.amazon.com/cost-management/home#/cost-explorer](https://console.aws.amazon.com/cost-management/home#/cost-explorer)

Sem isso, `boto3.client("ce").get_cost_and_usage(...)` retorna:

```text
AccessDeniedException: User not enabled for cost explorer access
```

E nao tem como ativar via Terraform/CLI. E uma decisao deliberada da AWS.

> **Observacao de campo**: a primeira indexacao apos ativar **leva ate 24h**. Se voce rodar o script no mesmo dia, retorna estrutura vazia (nao um erro). Esse comportamento confunde quem nao esta esperando.

### 2. IAM Role com permissoes ce:*

Cost Explorer nao aceita resource-level permission, entao policy fica:

```json
{
  "Sid": "CostExplorerRead",
  "Effect": "Allow",
  "Action": [
    "ce:GetCostAndUsage",
    "ce:GetTags",
    "ce:GetDimensionValues",
    "ce:GetCostForecast"
  ],
  "Resource": "*"
}
```

A IAM role do GitHub Actions deste projeto (`chris-platform-dev-github-actions-role`) ja inclui essas permissoes — ver `terraform/modules/iam/main.tf`.

### 3. Tags consistentes nos recursos

Sem tag `Project` nos recursos AWS, o GroupBy retorna `(untagged)`. O `setup.sh` desse lab aplica `Project=chris-platform` em tudo via `default_tags` do provider AWS (ver `terraform/providers.tf`), entao isso ja esta resolvido.

---

## Por que nao esta ativo neste lab

Decisao consciente:

- O workflow `cost-report.yml` foi removido das Actions porque **rodar diariamente em conta sem trafego significativo gera valor zero** (sempre mostra ~US$ 0.50/dia de overhead da EC2 idle)
- **Custo de runner**: cada execucao consome ~30s de runner. Free Tier cobre, mas ainda assim e ruido nas Actions
- **Sinal de portfolio**: o que importa demonstrar e a arquitetura e o codigo — nao precisa estar verde rodando todo dia para isso

O codigo continua versionado em `scripts/aws_cost_report.py` e pode ser executado manualmente quando voce quiser:

```bash
# Localmente, com AWS CLI configurado
python scripts/aws_cost_report.py --days 7 --output /tmp/cost.json
cat /tmp/cost.json | jq
```

Ou reativar o workflow recriando o arquivo em `.github/workflows/cost-report.yml` com o conteudo da secao "Workflow GitHub Actions de referencia" acima.

---

## Evolucao natural deste padrao

Onde isso vai quando deixa de ser laboratorio:

| Maturidade | Mudanca | Por que |
|------------|---------|---------|
| 1 | Slack/Teams webhook em vez de artifact | Output que ninguem le e sinal morto |
| 2 | Threshold + alerta (custo > X = aviso) | Reativo > proativo |
| 3 | Multiple accounts via assume role chain | Quando vira organization |
| 4 | Substituir por **Apache Airflow** DAG | Quando tiver mais que 5 jobs operacionais — Airflow ganha em retry, dependency, observabilidade |
| 5 | Adicionar **LLM** que classifica anomalias | "custo subiu 30%, provavelmente NAT Gateway na regiao us-east-1, picos as 14h" |

Os passos 4 e 5 sao iniciativas que toquei em equipes anteriores e estao no roadmap deste lab (ver [docs/runbook-observability.md](runbook-observability.md)).

---

## Links uteis

- [AWS Cost Explorer API](https://docs.aws.amazon.com/aws-cost-management/latest/APIReference/API_Operations_AWS_Cost_Explorer_Service.html)
- [boto3 ce client](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/ce.html)
- [GitHub Actions OIDC + AWS](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [AWS Tagging Best Practices](https://docs.aws.amazon.com/whitepapers/latest/tagging-best-practices/tagging-best-practices.html)

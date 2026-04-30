"""
aws_cost_report.py — relatorio diario de custo AWS por servico/tag.

Reproduz, em escala de laboratorio, o tipo de automacao que se entrega em
fintechs: pipeline GitHub Actions agendada, autenticada via OIDC, que coleta
custos do Cost Explorer, agrupa por Project (tag) e Service e devolve um
sumario textual + JSON. O JSON pode ser publicado como artifact da Action
ou enviado para Slack/Teams num passo subsequente.

Uso local:
    aws sso login                          # ou aws configure
    python scripts/aws_cost_report.py --days 7 --tag-key Project

Uso na Action (cost-report.yml):
    - run: python scripts/aws_cost_report.py --days 1 --output cost.json

Exit codes:
    0 — sucesso
    1 — erro de autenticacao AWS
    2 — argumento invalido

Mantenedor: chris-amaral
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import date, timedelta
from decimal import Decimal

try:
    import boto3
    from botocore.exceptions import BotoCoreError, ClientError, NoCredentialsError
except ImportError:
    sys.stderr.write("boto3 nao instalado. Rode: pip install boto3\n")
    sys.exit(2)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument(
        "--days", type=int, default=7,
        help="Janela em dias para coleta (default: 7)",
    )
    parser.add_argument(
        "--tag-key", default="Project",
        help="Tag a usar como chave de agrupamento (default: Project)",
    )
    parser.add_argument(
        "--region", default="us-east-1",
        help="Regiao da Cost Explorer API (default: us-east-1)",
    )
    parser.add_argument(
        "--output", type=str, default=None,
        help="Caminho para salvar o JSON (default: stdout apenas)",
    )
    return parser.parse_args()


def _fetch_costs(client, start: date, end: date, tag_key: str) -> list[dict]:
    response = client.get_cost_and_usage(
        TimePeriod={"Start": start.isoformat(), "End": end.isoformat()},
        Granularity="DAILY",
        Metrics=["UnblendedCost"],
        GroupBy=[
            {"Type": "DIMENSION", "Key": "SERVICE"},
            {"Type": "TAG", "Key": tag_key},
        ],
    )

    rows: list[dict] = []
    for bucket in response["ResultsByTime"]:
        period_start = bucket["TimePeriod"]["Start"]
        for group in bucket.get("Groups", []):
            service, tag_value = group["Keys"]
            amount = Decimal(group["Metrics"]["UnblendedCost"]["Amount"])
            currency = group["Metrics"]["UnblendedCost"]["Unit"]
            if amount == 0:
                continue
            rows.append({
                "date": period_start,
                "service": service,
                "tag": tag_value.split("$", 1)[-1] or "(untagged)",
                "amount": float(amount),
                "currency": currency,
            })
    return rows


def _summarize(rows: list[dict]) -> dict:
    total = sum(row["amount"] for row in rows)
    by_service: dict[str, float] = {}
    by_tag: dict[str, float] = {}
    for row in rows:
        by_service[row["service"]] = by_service.get(row["service"], 0.0) + row["amount"]
        by_tag[row["tag"]] = by_tag.get(row["tag"], 0.0) + row["amount"]

    return {
        "total_usd": round(total, 4),
        "top_services": sorted(by_service.items(), key=lambda kv: kv[1], reverse=True)[:5],
        "top_tags": sorted(by_tag.items(), key=lambda kv: kv[1], reverse=True)[:5],
        "rows": rows,
    }


def _print_human(summary: dict, days: int) -> None:
    print(f"Relatorio de custo — ultimos {days} dia(s)")
    print(f"Total: USD {summary['total_usd']:.4f}\n")

    print("Top 5 servicos:")
    for service, value in summary["top_services"]:
        print(f"  {service:<40} USD {value:>10.4f}")

    print("\nTop 5 tags:")
    for tag, value in summary["top_tags"]:
        print(f"  {tag:<40} USD {value:>10.4f}")


def main() -> int:
    args = _parse_args()
    if args.days < 1:
        sys.stderr.write("--days deve ser >= 1\n")
        return 2

    end = date.today()
    start = end - timedelta(days=args.days)

    try:
        client = boto3.client("ce", region_name=args.region)
        rows = _fetch_costs(client, start, end, args.tag_key)
    except NoCredentialsError:
        sys.stderr.write("Credenciais AWS ausentes. Rode 'aws configure' ou use OIDC.\n")
        return 1
    except (BotoCoreError, ClientError) as exc:
        sys.stderr.write(f"Erro chamando Cost Explorer: {exc}\n")
        return 1

    summary = _summarize(rows)
    _print_human(summary, args.days)

    if args.output:
        with open(args.output, "w", encoding="utf-8") as fp:
            json.dump(summary, fp, indent=2, default=str)
        print(f"\nJSON salvo em: {args.output}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

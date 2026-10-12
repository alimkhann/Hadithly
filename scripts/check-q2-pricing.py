#!/usr/bin/env python3
"""Reproduce Q2 unit economics; optionally fail on exported regional USD prices."""
import argparse
import csv
import json
import math
from datetime import date
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--regions", help="JSON rows: region, monthlyUsd, annualUsd, taxRate, storeFee")
parser.add_argument("--floor", type=float, default=0.60)
parser.add_argument("--apple-export-dir", help="Folder containing the dated monthly/annual CSVs and FX snapshot")
args = parser.parse_args()
if not math.isfinite(args.floor) or not 0 <= args.floor < 1:
    raise SystemExit("FAIL: margin floor must be a finite fraction below one")
TOKEN_COST = (2000 * 0.10 + 500 * 0.40) / 1_000_000
RC_FEE = 0.01  # Reserve even below the free MTR threshold.
PAID_INFRA = 0.10  # Planning reserve per paid account/month, not measured billing.
FREE_INFRA = 0.02  # Planning reserve per free active account/month.
MONTH_DAYS = 365.25 / 12


def economics(price, months, fee, tax, generations):
    gross = price / months
    tax_amount = gross - gross / (1 + tax)
    store = (gross - tax_amount) * fee
    rc = gross * RC_FEE
    net = gross - tax_amount - store - rc
    ai = generations * TOKEN_COST
    contribution = net - ai - PAID_INFRA
    return [gross, tax_amount, store, rc, ai, PAID_INFRA, contribution, contribution / net if net > 0 else float("-inf")]


print("Assumptions: 2,000 input + 500 output tokens, $0.000400/new generation;")
print("100 expected Pro generations/month; infrastructure reserves $0.10 Pro/$0.02 free.")
print("RC 1% reserved on gross; included taxes removed before store fee. Corporate tax excluded.")
print("| Case | Gross/mo | Tax | Store | RC | Gemini | Convex reserve | Contribution | % of proceeds |")
print("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
for name, price, months, fee, tax, count in [
    ("Monthly, 15%, expected", 2.99, 1, .15, 0, 100),
    ("Annual, 15%, expected", 24.99, 12, .15, 0, 100),
    ("Monthly, Apple 30%, expected", 2.99, 1, .30, 0, 100),
    ("Annual, Apple 30%, expected", 24.99, 12, .30, 0, 100),
    ("Annual, 30% + illustrative 25% included tax", 24.99, 12, .30, .25, 100),
    ("Annual, 30% + 25% tax, full average quota", 24.99, 12, .30, .25, 100 * MONTH_DAYS / 7),
    ("Monthly, 30% + 25% tax, 31-day quota bursts", 2.99, 1, .30, .25, 500),
]:
    row = economics(price, months, fee, tax, count)
    print("| " + name + " | " + " | ".join(f"${x:.4f}" for x in row[:-1]) + f" | {row[-1]:.1%} |")

free_ai = 5 * MONTH_DAYS / 7 * TOKEN_COST
free_cost = free_ai + FREE_INFRA
print(f"\nFree full-quota average: Gemini ${free_ai:.4f} + infrastructure ${FREE_INFRA:.2f} = ${free_cost:.4f}/MAU/month.")
print(f"31-day free burst maximum: 25 successes, Gemini ${25 * TOKEN_COST:.4f} at typical size.")
print(f"Annual discount: {1 - 24.99 / (12 * 2.99):.2%}. Annual recognized gross/month: ${24.99 / 12:.4f}.")
for fee, tax in [(0.15, 0), (0.30, .25)]:
    row = economics(24.99, 12, fee, tax, 100 * MONTH_DAYS / 7)
    paid_contribution = row[-2]
    ratio = paid_contribution / free_cost
    conversion = free_cost / (free_cost + paid_contribution)
    floor_ratio = max(0, (paid_contribution - args.floor * (row[0] - row[1] - row[2] - row[3])) / free_cost)
    print(f"Annual full typical quota, {fee:.0%} fee/{tax:.0%} tax: break-even {ratio:.1f} free per Pro ({conversion:.1%} paying), before fixed overhead; {args.floor:.0%} margin allows {floor_ratio:.1f} free per Pro.")

# A byte upper bound is intentionally conservative across source scripts/tokenizers.
max_call = (65_000 * .1 + 8192 * .4) / 1_000_000
print(f"\nLong-source stress: <=65,000 modeled input + 8,192 output gives ${max_call:.6f}/attempt;")
print(f"500 successes in a 31-day month would cost ${500 * max_call:.4f}. Prices do NOT cover this stress without the shared budget pause.")
print("Existing Q1 default aggregate AI budget: $10/month, 500 attempts/day, 25,000/month, all users/service/failures combined.")
print("Free users have a real cost; no price guarantees profit with arbitrarily many free users or retries.")

if args.regions:
    with open(args.regions, encoding="utf-8") as source:
        regions = json.load(source)
    if not isinstance(regions, list) or not regions:
        raise SystemExit("FAIL: no actual regional tiers supplied")
    failures = []
    for region in regions:
        if not isinstance(region, dict) or not isinstance(region.get("region"), str):
            raise SystemExit("FAIL: invalid region")
        for field in ["monthlyUsd", "annualUsd", "taxRate", "storeFee"]:
            value = region.get(field)
            if not isinstance(value, (int, float)) or isinstance(value, bool) or not math.isfinite(value) or value < 0:
                raise SystemExit(f"FAIL: invalid {field}")
        if region["storeFee"] > 1 or region["taxRate"] > 1:
            raise SystemExit("FAIL: rates must be fractions")
        for product, months in [("monthlyUsd", 1), ("annualUsd", 12)]:
            values = economics(region[product], months, region["storeFee"], region["taxRate"], 100 * MONTH_DAYS / 7)
            if values[0] <= 0 or values[-1] < args.floor:
                failures.append(f"{region['region']} {product}")
    if failures:
        raise SystemExit("FAIL margin floor: " + ", ".join(failures))
    print(f"PASS: {len(regions)} supplied regions meet {args.floor:.0%} paid-unit margin at full typical quota. Free subsidy and long-source stress remain separate.")

if args.apple_export_dir:
    directory = Path(args.apple_export_dir)
    fx = json.loads((directory / "fx-2026-10-12.json").read_text())
    exports = []
    for plan in ["monthly", "annual"]:
        with (directory / f"apple-{plan}-2026-10-12.csv").open(encoding="utf-8-sig", newline="") as source:
            rows = list(csv.DictReader(source))
        countries = {r["Countries or Regions"] for r in rows}
        if len(rows) != 175 or len(countries) != 175 or any(r["Billing Plan"] != "Upfront" for r in rows):
            raise SystemExit("FAIL: incomplete or duplicate Apple export, or unapproved billing plan")
        exports.append(countries)
        ranked = []
        for row in rows:
            currency = row["Currency Code"]
            rate = fx[currency]
            rate_date = date.fromisoformat(rate["date"])
            if not 0 <= (date(2026, 10, 12) - rate_date).days <= 7 or not math.isfinite(rate["usdPerUnit"]) or rate["usdPerUnit"] <= 0:
                raise SystemExit("FAIL: stale or invalid FX")
            months = 1 if plan == "monthly" else 12
            if not all(math.isfinite(float(row[field])) and float(row[field]) > 0 for field in ["Price", "Year 1 Proceeds", "Year 2 Proceeds"]):
                raise SystemExit("FAIL: non-positive or invalid Apple price/proceeds")
            gross = float(row["Price"]) * rate["usdPerUnit"] / months
            # Apple export's US proceeds imply 15%; scale to 30% and haircut FX by 15%.
            proceeds = float(row["Year 1 Proceeds"]) * rate["usdPerUnit"] / months * (0.70 / 0.85) * 0.85
            net = proceeds - gross * RC_FEE
            successes = 500 if plan == "monthly" else 5300 / 12
            contribution = net - successes * TOKEN_COST - PAID_INFRA
            margin = contribution / net if net > 0 else float("-inf")
            ranked.append((margin, row["Countries or Regions"], contribution, gross))
        ranked.sort()
        if ranked[0][0] < args.floor:
            raise SystemExit(f"FAIL Apple {plan}: {ranked[0]}")
        print(f"PASS Apple {plan}: 175 storefronts; 30% modeled fee, export tax/proceeds, 15% FX haircut, typical-size quota bursts. Minimum paid-unit margin {ranked[0][0]:.1%} in {ranked[0][1]} (${ranked[0][2]:.4f}/month contribution).")
        print("Lowest five:", [(country, round(margin * 100, 2)) for margin, country, _, _ in ranked[:5]])
    if exports[0] != exports[1]:
        raise SystemExit("FAIL: monthly/annual country coverage differs")

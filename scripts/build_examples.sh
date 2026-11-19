#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p examples

moon run --target native cmd/main -- audit fixtures/bad_model.xlsx --format json --out examples/findings.json
moon run --target native cmd/main -- audit fixtures/bad_model.xlsx --format sarif --out examples/results.sarif
moon run --target native cmd/main -- audit fixtures/bad_model.xlsx --format html --out examples/report.html
moon run --target native cmd/main -- graph fixtures/bad_model.xlsx --format mermaid --out examples/graph.mmd

moon run --target native cmd/main -- slice fixtures/bad_model.xlsx --target "Summary!B3" --out examples/slice.xlsx --manifest examples/slice_manifest.json --report examples/slice_certificate.html --strict
moon run --target native cmd/main -- verify-slice examples/slice.xlsx --manifest examples/slice_manifest.json --source fixtures/bad_model.xlsx --strict > examples/verify_slice.txt

moon run --target native cmd/main -- slice fixtures/bad_model.xlsx --target "Summary!B3" --target "Summary!B10" --out examples/multi_slice.xlsx --manifest examples/multi_slice_manifest.json --strict
moon run --target native cmd/main -- verify-slice examples/multi_slice.xlsx --manifest examples/multi_slice_manifest.json --source fixtures/bad_model.xlsx --strict > examples/verify_multi_slice.txt

moon run --target native cmd/main -- slice fixtures/bad_model.xlsx --target "Summary!B14" --out examples/external_slice.xlsx --manifest examples/external_slice_manifest.json --report examples/external_slice_certificate.html --external external_book.xlsx=fixtures/external_book.xlsx --strict
moon run --target native cmd/main -- verify-slice examples/external_slice.xlsx --manifest examples/external_slice_manifest.json --source fixtures/bad_model.xlsx --strict > examples/verify_external_slice.txt

targets="$(python3 -c 'print(",".join(f"Coverage!B{i}" for i in range(2,32)))')"
moon run --target native cmd/main -- slice fixtures/formula_coverage.xlsx --targets "$targets" --out examples/formula_coverage_slice.xlsx --manifest examples/formula_coverage_manifest.json --strict

if [ "${RUN_CROSSCHECK:-0}" = "1" ]; then
  python3 scripts/crosscheck_formulas.py examples/multi_slice.xlsx examples/multi_slice_manifest.json examples/multi_crosscheck.json
  python3 scripts/crosscheck_formulas.py examples/external_slice.xlsx examples/external_slice_manifest.json examples/external_crosscheck.json
  python3 scripts/crosscheck_formulas.py examples/formula_coverage_slice.xlsx examples/formula_coverage_manifest.json examples/formula_coverage_crosscheck.json
fi

echo "Examples generated in examples/"

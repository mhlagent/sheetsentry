#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out="${OUTPUT_DIR:-examples}"
mkdir -p "$out"

moon run --target native cmd/main -- audit fixtures/bad_model.xlsx --format json --out "$out/findings.json"
moon run --target native cmd/main -- audit fixtures/bad_model.xlsx --format sarif --out "$out/results.sarif"
moon run --target native cmd/main -- audit fixtures/bad_model.xlsx --format html --out "$out/report.html"
moon run --target native cmd/main -- graph fixtures/bad_model.xlsx --format mermaid --out "$out/graph.mmd"

moon run --target native cmd/main -- slice fixtures/bad_model.xlsx --target "Summary!B3" --out "$out/slice.xlsx" --manifest "$out/slice_manifest.json" --report "$out/slice_certificate.html" --strict
moon run --target native cmd/main -- verify-slice "$out/slice.xlsx" --manifest "$out/slice_manifest.json" --source fixtures/bad_model.xlsx --strict > "$out/verify_slice.txt"

moon run --target native cmd/main -- slice fixtures/bad_model.xlsx --target "Summary!B3" --target "Summary!B10" --out "$out/multi_slice.xlsx" --manifest "$out/multi_slice_manifest.json" --strict
moon run --target native cmd/main -- verify-slice "$out/multi_slice.xlsx" --manifest "$out/multi_slice_manifest.json" --source fixtures/bad_model.xlsx --strict > "$out/verify_multi_slice.txt"

moon run --target native cmd/main -- slice fixtures/bad_model.xlsx --target "Summary!B14" --out "$out/external_slice.xlsx" --manifest "$out/external_slice_manifest.json" --report "$out/external_slice_certificate.html" --external external_book.xlsx=fixtures/external_book.xlsx --strict
moon run --target native cmd/main -- verify-slice "$out/external_slice.xlsx" --manifest "$out/external_slice_manifest.json" --source fixtures/bad_model.xlsx --strict > "$out/verify_external_slice.txt"

targets="$(python3 -c 'print(",".join(f"Coverage!B{i}" for i in range(2,32)))')"
moon run --target native cmd/main -- slice fixtures/formula_coverage.xlsx --targets "$targets" --out "$out/formula_coverage_slice.xlsx" --manifest "$out/formula_coverage_manifest.json" --strict

if [ "${RUN_CROSSCHECK:-0}" = "1" ]; then
  python3 scripts/crosscheck_formulas.py "$out/multi_slice.xlsx" "$out/multi_slice_manifest.json" "$out/multi_crosscheck.json"
  python3 scripts/crosscheck_formulas.py "$out/external_slice.xlsx" "$out/external_slice_manifest.json" "$out/external_crosscheck.json"
  python3 scripts/crosscheck_formulas.py "$out/formula_coverage_slice.xlsx" "$out/formula_coverage_manifest.json" "$out/formula_coverage_crosscheck.json"
fi

echo "Examples generated in $out"

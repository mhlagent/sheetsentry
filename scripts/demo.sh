#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
moon run --target native cmd/main -- audit fixtures/bad_model.xlsx
moon run --target native cmd/main -- trace fixtures/bad_model.xlsx --cell "Summary!B3" --direction precedents --depth 1
moon run --target native cmd/main -- audit fixtures/bad_model.xlsx --format html --out /tmp/sheetsentry-report.html
echo "HTML report: /tmp/sheetsentry-report.html"

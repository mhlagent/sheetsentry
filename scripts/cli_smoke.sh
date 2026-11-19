#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

run_expect() {
  local expected="$1"
  shift
  set +e
  "$@" >"$tmp/cli-output.txt" 2>&1
  local actual=$?
  set -e
  if [ "$actual" -ne "$expected" ]; then
    echo "expected exit $expected, got $actual: $*" >&2
    cat "$tmp/cli-output.txt" >&2
    exit 1
  fi
}

run_expect 2 moon run --target native cmd/main --
run_expect 2 moon run --target native cmd/main -- unknown-command
run_expect 1 moon run --target native cmd/main -- audit /tmp/sheetsentry-missing.xlsx
run_expect 1 moon run --target native cmd/main -- audit fixtures/bad_model.xlsx --format yaml
run_expect 1 moon run --target native cmd/main -- audit fixtures/bad_model.xlsx --fail-on urgent
run_expect 0 moon run --target native cmd/main -- audit fixtures/clean_model.xlsx --fail-on low
run_expect 1 moon run --target native cmd/main -- audit fixtures/bad_model.xlsx --fail-on high
run_expect 1 moon run --target native cmd/main -- trace fixtures/bad_model.xlsx

run_expect 0 moon run --target native cmd/main -- slice fixtures/bad_model.xlsx --target "Summary!B3" --out "$tmp/slice.xlsx" --manifest "$tmp/slice.json" --strict
run_expect 0 moon run --target native cmd/main -- verify-slice "$tmp/slice.xlsx" --manifest "$tmp/slice.json" --source fixtures/bad_model.xlsx --strict
cp "$tmp/slice.xlsx" "$tmp/tampered.xlsx"
printf 'tampered' >> "$tmp/tampered.xlsx"
run_expect 1 moon run --target native cmd/main -- verify-slice "$tmp/tampered.xlsx" --manifest "$tmp/slice.json" --strict

run_expect 1 moon run --target native cmd/main -- slice fixtures/bad_model.xlsx --target "Summary!B3" --depth 0 --out "$tmp/incomplete.xlsx" --manifest "$tmp/incomplete.json" --strict
run_expect 1 moon run --target native cmd/main -- verify-slice "$tmp/incomplete.xlsx" --manifest "$tmp/incomplete.json" --strict

echo "CLI smoke tests passed"

#!/usr/bin/env python3
"""Validate committed SheetSentry examples and independent cross-check reports."""
from __future__ import annotations

import json
import sys
from pathlib import Path

REQUIRED = [
    "findings.json",
    "results.sarif",
    "report.html",
    "graph.mmd",
    "slice.xlsx",
    "slice_manifest.json",
    "slice_certificate.html",
    "verify_slice.txt",
    "multi_slice.xlsx",
    "multi_slice_manifest.json",
    "verify_multi_slice.txt",
    "external_slice.xlsx",
    "external_slice_manifest.json",
    "external_slice_certificate.html",
    "verify_external_slice.txt",
    "formula_coverage_slice.xlsx",
    "formula_coverage_manifest.json",
    "multi_crosscheck.json",
    "external_crosscheck.json",
    "formula_coverage_crosscheck.json",
]


def load_json(path: Path):
    return json.loads(path.read_text())


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def main() -> None:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "examples")
    for name in REQUIRED:
        require((root / name).is_file(), f"missing example: {root / name}")

    slice_manifest = load_json(root / "slice_manifest.json")
    require(slice_manifest["target"] == "Summary!B3", "wrong single-slice target")
    require(slice_manifest["verified"], "single slice target value is not verified")
    require(slice_manifest["calc_verified"], "single slice recalculation failed")
    require(slice_manifest["complete"], "single slice is incomplete")
    require(slice_manifest["minimality_verified"], "single slice minimality failed")
    require(len(slice_manifest["included_cells"]) == 12, "single slice should contain 12 cells")
    require(slice_manifest["included_sheets"] == ["Summary", "Opex"], "unexpected single-slice sheets")

    multi_manifest = load_json(root / "multi_slice_manifest.json")
    require(len(multi_manifest["targets"]) == 2, "multi slice should contain two targets")
    require(all(item["verified"] and item["calc_verified"] for item in multi_manifest["targets"]), "multi target verification failed")
    require(multi_manifest["reduction_ratio"] == "13/65", "unexpected multi-slice reduction")
    require(multi_manifest["complete"] and multi_manifest["minimality_verified"], "multi slice gates failed")

    external_manifest = load_json(root / "external_slice_manifest.json")
    require(external_manifest["target"] == "Summary!B14", "wrong external target")
    require(external_manifest["target_value_before"] == "42", "wrong external target value")
    require(external_manifest["verified"] and external_manifest["calc_verified"], "external verification failed")
    require(external_manifest["complete"], "external slice is incomplete")
    require(external_manifest["external_workbooks"] == ["external_book.xlsx"], "wrong external workbook list")

    coverage_manifest = load_json(root / "formula_coverage_manifest.json")
    require(len(coverage_manifest["targets"]) == 30, "formula coverage should contain 30 targets")
    require(all(item["verified"] and item["calc_verified"] for item in coverage_manifest["targets"]), "formula coverage verification failed")

    expected_crosschecks = {
        "multi_crosscheck.json": (2, 2),
        "external_crosscheck.json": (1, 1),
        "formula_coverage_crosscheck.json": (30, 30),
    }
    for name, (targets, matched) in expected_crosschecks.items():
        report = load_json(root / name)
        require(report["engine"] == "formulas==1.3.4" or report["engine"] == "formulas", f"unexpected engine in {name}")
        require(report["targets"] == targets, f"unexpected target count in {name}")
        require(report["matched"] == matched, f"unexpected matched count in {name}")
        require(report["mismatched"] == 0 and report["all_match"], f"cross-check failed in {name}")

    print("Examples and cross-check reports are valid")


if __name__ == "__main__":
    main()

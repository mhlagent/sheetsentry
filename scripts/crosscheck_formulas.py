#!/usr/bin/env python3
"""Cross-check SheetSentry slice targets with the independent `formulas` engine.

Usage:
    python3 scripts/crosscheck_formulas.py slice.xlsx manifest.json [report.json]
"""
from __future__ import annotations

import json
import math
import os
import sys
from pathlib import Path

import formulas


def scalar(value):
    value = getattr(value, "value", value)
    while isinstance(value, (list, tuple)):
        value = value[0]
    try:
        import numpy as np
        if isinstance(value, np.ndarray):
            while value.size == 1:
                value = value.item()
    except Exception:
        pass
    return value


def normalize(value):
    if isinstance(value, bool):
        return "TRUE" if value else "FALSE"
    if isinstance(value, (int, float)):
        if isinstance(value, float) and math.isfinite(value) and value.is_integer():
            return str(int(value))
        return format(value, ".15g")
    return str(value)


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    slice_path = Path(sys.argv[1]).resolve()
    manifest_path = Path(sys.argv[2])
    report_path = Path(sys.argv[3]) if len(sys.argv) > 3 else None
    manifest = json.loads(manifest_path.read_text())
    model = formulas.ExcelModel().loads(str(slice_path)).finish()
    solution = model.calculate()
    basename = slice_path.name
    results = []
    mismatches = 0
    for item in manifest.get("targets", []):
        target = item["target"]
        sheet, cell = target.split("!", 1)
        key = f"'[{basename}]{sheet.upper()}'!{cell.upper()}"
        value = normalize(scalar(solution[key])) if key in solution else None
        before = item.get("before")
        calculated = item.get("calculated")
        def equivalent(expected):
            if expected is None:
                return False
            candidate = normalize(expected)
            if value in ("TRUE", "FALSE"):
                if value == "TRUE":
                    return candidate in ("1", "TRUE", "true")
                return candidate in ("0", "FALSE", "false")
            return value == candidate
        match_before = value is not None and equivalent(before)
        match_calculated = value is not None and equivalent(calculated)
        if not (match_before and match_calculated):
            mismatches += 1
        results.append({
            "target": target,
            "manifest_before": before,
            "manifest_calculated": calculated,
            "formulas_value": value,
            "match_before": match_before,
            "match_calculated": match_calculated,
        })
    report = {
        "slice": basename,
        "engine": "formulas",
        "targets": len(results),
        "matched": len(results) - mismatches,
        "mismatched": mismatches,
        "all_match": mismatches == 0 and len(results) > 0,
        "results": results,
    }
    text = json.dumps(report, ensure_ascii=False, indent=2)
    print(text)
    if report_path:
        report_path.write_text(text)
    raise SystemExit(0 if report["all_match"] else 1)


if __name__ == "__main__":
    main()

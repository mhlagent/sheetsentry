# Changelog

## 0.3.0

- Add JSON config files (`--config`) for severity, disabled rules, ignored cells, and fail-on.
- Add `SS009` whole-axis reference rule.
- Add `SS010` missing cached result rule.
- Expand tests to 46.

## 0.2.0

- Add baseline suppression (`--baseline`, `--write-baseline`).
- Add external workbook reference rule (`SS008`).
- Replace first-edge cycle probing with DFS cycle detection.
- Add DOT and Mermaid dependency graph export (`graph` command).
- Add filterable HTML report.
- Add `rules` command.
- Sort findings by severity, sheet, and cell.
- Add `--min-severity` and `--disable` filters.
- Add `SS009` whole-axis reference and `SS010` missing cached value rules.
- Expand tests to 19.

## 0.1.0

- Initial MVP: XLSX reading, formula reference parsing, dependency graph, six audit rules, terminal/JSON/SARIF/HTML reports, precedents/dependents trace, CI thresholds.

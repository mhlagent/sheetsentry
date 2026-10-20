# Changelog

## 0.2.0

- Add baseline suppression (`--baseline`, `--write-baseline`).
- Add external workbook reference rule (`SS008`).
- Replace first-edge cycle probing with DFS cycle detection.
- Add DOT and Mermaid dependency graph export (`graph` command).
- Add filterable HTML report.
- Add `rules` command.
- Sort findings by severity, sheet, and cell.
- Add `--min-severity` and `--disable` filters.
- Expand tests to 19.

## 0.1.0

- Initial MVP: XLSX reading, formula reference parsing, dependency graph, six audit rules, terminal/JSON/SARIF/HTML reports, precedents/dependents trace, CI thresholds.

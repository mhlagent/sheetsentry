# Changelog

## 0.8.0

- Add minimality detail lists: unreachable included, missing required, and excluded reachable.
- Add `verify-slice --source` source hash verification.
- Add an integrated six-target slice test covering named, dynamic, structured, and external references.
- Expand tests to 71.

## 0.7.0

- Add slice minimality metrics and closure verification.
- Add independent recalculation for all slice targets.
- Add `calc_verified`, `minimality_verified`, reduction metrics, and per-target calculated values.
- Expand tests to 68.

## 0.6.0

- Add multi-target calculation slices with unioned precedent closure.
- Add HTML slice certificates.
- Verify slice SHA-256 and all target values in `verify-slice`.
- Expand tests to 65.

## 0.5.0

- Add named-range resolution and defined-name preservation in slices.
- Add literal `INDIRECT` and constant `OFFSET` dependency resolution.
- Add table catalog parsing and structured-reference rewriting to A1 ranges.
- Add external workbook mapping with value import and formula rewriting.
- Expand tests to 62.

## 0.4.1

- Clean up CLI verification output so builds run without warnings.

## 0.4.0

- Add calculation-slice extraction: target precedent closure, standalone XLSX reconstruction, and unrelated-sheet exclusion.
- Add SHA-256 slice manifests with included cells, completeness, unresolved dependencies, and target before/after values.
- Add `verify-slice` for independent target-value verification.
- Clarify the independent core boundary versus formula-analysis tools.
- Expand tests to 54.

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

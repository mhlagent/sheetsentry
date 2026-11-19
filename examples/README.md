# Reproducible examples

These files are generated from the repository fixtures with MoonBit 0.10.20:

```bash
bash scripts/build_examples.sh
```

| File | Contents |
| --- | --- |
| `slice.xlsx` | Standalone `Summary!B3` calculation slice |
| `slice_manifest.json` | Source/slice hashes, target values, minimality, and completeness |
| `slice_certificate.html` | Self-contained slice verification certificate |
| `multi_slice.xlsx` | Two-target slice for `Summary!B3` and `Summary!B10` |
| `multi_slice_manifest.json` | Two-target manifest with 13/65 used cells |
| `verify_multi_slice.txt` | Strict verification output for both targets |
| `external_slice.xlsx` | Slice with an imported external workbook |
| `external_slice_manifest.json` | External-reference manifest with `complete=true` |
| `external_slice_certificate.html` | External-slice verification certificate |
| `verify_external_slice.txt` | Strict verification output for the external slice |
| `formula_coverage_slice.xlsx` | 30-formula compatibility fixture slice |
| `formula_coverage_manifest.json` | Manifest for all 30 targets |
| `findings.json` | Audit report for `fixtures/bad_model.xlsx` |
| `results.sarif` | SARIF 2.1.0 audit report |
| `report.html` | Self-contained HTML audit report |
| `graph.mmd` | Mermaid dependency graph |
| `multi_crosscheck.json` | Independent `formulas==1.3.4` results for two targets |
| `external_crosscheck.json` | Independent result for the external-reference target |
| `formula_coverage_crosscheck.json` | Independent results for 30 formula cases |
| `verify_slice.txt` | `verify-slice --source --strict` output |

Current verified results:

- `Summary!B3`: 12 cells, 2 sheets, target `539`, `verified=true`, `calc_verified=true`, `complete=true`.
- `Summary!B3` + `Summary!B10`: 14 cells, 13/65 used cells, both targets match independent recalculation.
- `Summary!B14` with `external_book.xlsx`: target `42`, `complete=true`, strict verification passes.
- Formula coverage: 30/30 targets match `formulas==1.3.4`.
- `verify-slice --strict`: target value, independent recalculation, slice SHA-256, source SHA-256, completeness, and minimality all pass.

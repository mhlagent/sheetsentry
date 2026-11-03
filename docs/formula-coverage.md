# Formula coverage and cross-implementation validation

## Covered functions

`fixtures/formula_coverage.xlsx` contains 30 formula targets with cached expected values:

| Category | Functions |
| --- | --- |
| Aggregation | SUM, AVERAGE, MIN, MAX, COUNT |
| Logical | IF, AND, OR, NOT |
| Numeric | ABS, ROUND, ROUNDUP, ROUNDDOWN, MOD, INT |
| Text | CONCAT, LEFT, RIGHT, MID, LEN, UPPER, LOWER, TRIM |
| Lookup | VLOOKUP, INDEX, MATCH |
| Date | YEAR, MONTH, DAY |
| Error handling | IFERROR |

SheetSentry slices all 30 targets in one workbook and verifies:

- all 30 cached target values are preserved;
- all 30 targets recalculate independently through `mbtexcel`;
- the slice is minimal and complete.

Independent engine check: `formulas==1.3.4` calculates the same 30 targets; **30/30 match**.

## Complex workbook check

`fixtures/bad_model.xlsx` combines:

- ordinary A1 and cross-sheet references;
- named ranges;
- `INDIRECT` with a literal reference;
- `OFFSET` with constant offsets;
- a table structured reference;
- an external workbook reference imported with `--external`.

A six-target complex slice contains 20 cells across 3 sheets. `formulas` independently calculates all six targets; **6/6 match** SheetSentry's manifest values.

## Supported semantics

| Scenario | Status |
| --- | --- |
| A1, absolute and range references | Supported |
| Cross-sheet references | Supported |
| Named ranges | Supported; definitions copied into the slice |
| `INDIRECT("Sheet!A1")` | Supported for literal reference strings |
| `OFFSET(A1, row, col)` | Supported for constant offsets |
| Table `[Column]`, `@Column`, `#Data`, `#Headers`, `#Totals` | Supported and rewritten to A1 ranges |
| External workbook values | Supported through explicit `--external book=path`; values imported into `__ext__*` sheets |
| Arithmetic, logical, text, lookup and date functions above | Supported |
| Computed `INDIRECT` / variable `OFFSET` | Marked unresolved; slice becomes incomplete |
| Array formulas, dynamic arrays, macros | Not supported |
| External formulas recalculated from the external file | Not supported; external values are imported as cached values |
| Volatile time/random functions | Preserved as formulas, but deterministic verification is not claimed |

## Reproduce

```bash
moon run --target native cmd/main -- \
  slice fixtures/formula_coverage.xlsx \
  --targets "Coverage!B2,Coverage!B3,Coverage!B4,Coverage!B5,Coverage!B6" \
  --out coverage-slice.xlsx --manifest coverage-manifest.json

python3 scripts/crosscheck_formulas.py coverage-slice.xlsx coverage-manifest.json
```

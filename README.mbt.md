# SheetSentry

Static analysis and dependency tracing for Excel models, written in MoonBit.

SheetSentry reads `.xlsx` workbooks, parses formula references across sheets, builds a cell dependency graph, and reports model risks such as error values, inconsistent formulas, hardcoded constants, volatile functions, hidden content, and circular references.

## Status

Early MVP. The first milestone reads workbooks and summarizes sheet/formula counts.

## Quick start

```bash
moon check --target native
moon test --target native
moon run --target native cmd/main -- audit fixtures/bad_model.xlsx
```

## Planned CLI

```bash
sheetsentry audit model.xlsx
sheetsentry audit model.xlsx --format json --out findings.json
sheetsentry audit model.xlsx --format sarif --out results.sarif
sheetsentry audit model.xlsx --format html --out report.html
sheetsentry trace model.xlsx --cell "Summary!B7" --direction precedents --depth 4
```

## Rules

| ID | Rule |
| --- | --- |
| SS001 | Error values (`#REF!`, `#DIV/0!`, `#VALUE!`, `#N/A`, ...) |
| SS002 | Formula inconsistency in a row or column |
| SS003 | Hardcoded numeric constants in formulas |
| SS004 | Volatile functions (`TODAY`, `NOW`, `RAND`, `INDIRECT`, `OFFSET`, ...) |
| SS005 | Hidden sheets or rows containing formulas |
| SS006 | Circular references |

## License

Apache-2.0.

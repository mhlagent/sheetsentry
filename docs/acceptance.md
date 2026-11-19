# Acceptance evidence

This checklist maps the project to the hackathon review criteria and to the
claims in `docs/application.md`.

## Repository and open source

| Requirement | Evidence |
| --- | --- |
| Public GitHub repository | https://github.com/mhlagent/sheetsentry |
| Incremental commit history | Feature, test, documentation, and CI commits across the development and release history |
| License | Apache-2.0 in `moon.mod` and `LICENSE` |
| Copyright and attribution | `LICENSE`, `NOTICE`, and dependency declarations in `moon.mod` |
| Dependency compatibility | All runtime dependencies are Apache-2.0 packages resolved through Mooncakes |
| External service independence | Runtime slicing and verification require no network, LLM, or AI service |

## MoonBit ecosystem relevance

| Requirement | Evidence |
| --- | --- |
| Core implementation in MoonBit | XLSX slicing, formula parsing, dependency tracing, audit rules, reports, and CLI are implemented in `.mbt` files |
| Reusable library API | 48 public functions/types are exported in `pkg.generated.mbti` |
| Mooncakes package | [`mhlagent/sheetsentry@0.10.2`](https://mooncakes.io/docs/mhlagent/sheetsentry), target `native` |
| Compatibility | Verified with `moon 0.1.20261104` and `moonc v0.10.20+65efd5b93` |
| Optional non-MoonBit tooling | Python is used only for fixture generation and independent formula cross-checking |

## Functional completeness

| Capability | Evidence |
| --- | --- |
| Reconstruct a standalone XLSX slice | `slice` command and `slice_bytes_many` API |
| Reopen and verify a slice | `verify-slice` command with target, recalculation, hash, completeness, and minimality gates |
| Multi-target slices | `--target`, `--targets`, and `--targets-file` |
| Formula support | A1, absolute and range references, named ranges, literal `INDIRECT`, constant `OFFSET`, structured references |
| External workbook import | `--external book.xlsx=path` |
| Audit rules | Ten deterministic rules, severity filters, baseline suppression, and config files |
| Reports | Terminal, JSON, SARIF 2.1.0, and self-contained HTML |
| Dependency graph | Precedent/dependent trace and DOT/Mermaid export |
| CI behavior | Strict failure exits for findings, invalid input, incomplete slices, hash mismatch, and failed recalculation |

## Verification results

Run from a clean clone:

```bash
moon update
moon check --target native --deny-warn
moon test --target native --deny-warn
moon build --target native --deny-warn
moon fmt --check
python3 scripts/check_examples.py examples
```

Expected and verified results:

- 78/78 MoonBit tests pass.
- `Summary!B3` produces 12 cells across 2 sheets, target value `539`, with `verified=true`, `calc_verified=true`, `complete=true`, and `minimality_verified=true`.
- `Summary!B3 + Summary!B10` produces 14 cells and retains 13/65 used cells; both targets verify and recalculate.
- `Summary!B14` imports `external_book.xlsx`, produces target value `42`, and passes strict verification.
- The six-target complex slice matches independent `formulas==1.3.4` results 6/6.
- The 30-case formula fixture matches independent `formulas==1.3.4` results 30/30.
- Committed example manifests and certificates are validated by `scripts/check_examples.py`.
- [GitHub Actions](https://github.com/mhlagent/sheetsentry/actions) passes all strict checks and cross-implementation tests.
- Mooncakes reports `build_status=success` for `0.10.2`.

## Documented boundaries

These are explicit limits, not silent failure modes:

- XLSX only; styles, charts, and macros are not fully preserved.
- Computed `INDIRECT` and variable `OFFSET` are marked unresolved and force `complete=false`.
- External formulas are imported by cached value unless a mapping is supplied.
- Depth-limited slices fail `--strict`.
- Volatile functions are preserved as formulas but deterministic future recalculation is not claimed.
- Native is the supported build target.

## Reproduce the evidence

```bash
moon update
moon check --target native --deny-warn
moon test --target native --deny-warn
moon build --target native --deny-warn
moon fmt --check
bash scripts/cli_smoke.sh

python3 -m pip install formulas==1.3.4 openpyxl
OUTPUT_DIR=/tmp/sheetsentry-examples RUN_CROSSCHECK=1 bash scripts/build_examples.sh
python3 scripts/check_examples.py /tmp/sheetsentry-examples
python3 scripts/check_examples.py examples
```

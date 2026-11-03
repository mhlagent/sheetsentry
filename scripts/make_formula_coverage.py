#!/usr/bin/env python3
"""Generate a formula function coverage workbook with cached expected values."""
from pathlib import Path
import xlsxwriter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "fixtures" / "formula_coverage.xlsx"

CASES = [
    ("SUM", "=SUM(1,2,3)", 6, "numeric aggregate"),
    ("AVERAGE", "=AVERAGE(1,2,3)", 2, "numeric aggregate"),
    ("MIN", "=MIN(1,2,3)", 1, "numeric aggregate"),
    ("MAX", "=MAX(1,2,3)", 3, "numeric aggregate"),
    ("COUNT", "=COUNT(1,2,3)", 3, "numeric aggregate"),
    ("IF", "=IF(1<2,10,20)", 10, "logical"),
    ("AND", "=AND(TRUE,TRUE)", True, "logical"),
    ("OR", "=OR(FALSE,TRUE)", True, "logical"),
    ("NOT", "=NOT(FALSE)", True, "logical"),
    ("ABS", "=ABS(-5)", 5, "numeric"),
    ("ROUND", "=ROUND(1.2345,2)", 1.23, "numeric"),
    ("ROUNDUP", "=ROUNDUP(1.21,1)", 1.3, "numeric"),
    ("ROUNDDOWN", "=ROUNDDOWN(1.29,1)", 1.2, "numeric"),
    ("MOD", "=MOD(7,3)", 1, "numeric"),
    ("INT", "=INT(2.9)", 2, "numeric"),
    ("CONCAT", '=CONCAT("A","B")', "AB", "text"),
    ("LEFT", '=LEFT("HELLO",2)', "HE", "text"),
    ("RIGHT", '=RIGHT("HELLO",2)', "LO", "text"),
    ("MID", '=MID("HELLO",2,3)', "ELL", "text"),
    ("LEN", '=LEN("HELLO")', 5, "text"),
    ("UPPER", '=UPPER("abc")', "ABC", "text"),
    ("LOWER", '=LOWER("ABC")', "abc", "text"),
    ("TRIM", '=TRIM(" A B ")', "A B", "text"),
    ("VLOOKUP", "=VLOOKUP(2,Data!A1:B3,2,FALSE)", 20, "lookup"),
    ("INDEX", "=INDEX(Data!B1:B3,2)", 20, "lookup"),
    ("MATCH", "=MATCH(2,Data!A1:A3,0)", 2, "lookup"),
    ("YEAR", "=YEAR(DATE(2026,1,1))", 2026, "date"),
    ("MONTH", "=MONTH(DATE(2026,1,1))", 1, "date"),
    ("DAY", "=DAY(DATE(2026,1,1))", 1, "date"),
    ("IFERROR", '=IFERROR(1/0,"ERR")', "ERR", "error handling"),
]


def build():
    wb = xlsxwriter.Workbook(OUT)
    data = wb.add_worksheet("Data")
    data.write_row("A1", [1, 10])
    data.write_row("A2", [2, 20])
    data.write_row("A3", [3, 30])

    ws = wb.add_worksheet("Coverage")
    ws.write_row(0, 0, ["Function", "Result", "Category"])
    for i, (name, formula, value, category) in enumerate(CASES, start=1):
        ws.write(i, 0, name)
        ws.write_formula(i, 1, formula, None, value)
        ws.write(i, 2, category)
    wb.close()
    print(OUT)


if __name__ == "__main__":
    build()

#!/usr/bin/env python3
"""Generate deterministic XLSX fixtures for SheetSentry tests."""
from pathlib import Path
import shutil
import tempfile
import zipfile
import xlsxwriter

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "fixtures"


def add_inputs(wb):
    ws = wb.add_worksheet("Inputs")
    ws.write("A1", "Input")
    ws.write("B1", "Value")
    ws.write("A2", "Revenue")
    ws.write_number("B2", 1000)
    ws.write("A3", "Growth rate")
    ws.write_number("B3", 0.03)
    ws.write("A4", "Years")
    ws.write_number("B4", 5)
    ws.write("A5", "Base year")
    ws.write_number("B5", 2026)


def add_opex(wb, bad: bool):
    ws = wb.add_worksheet("Opex")
    ws.write("A1", "Item")
    ws.write("B1", "Amount")
    ws.write("C1", "Inflated")
    ws.write("D1", "Multiplier")
    ws.write_number("D2", 1.1)
    rows = [("Rent", 100), ("Payroll", 120), ("Cloud", 130), ("Travel", 140), ("Other", 150)]
    start = 2
    for i, (label, amount) in enumerate(rows):
        r = start + i
        ws.write(r - 1, 0, label)
        ws.write_number(r - 1, 1, amount)
        if bad and i == 4:
            # Deliberate off-by-one: should be B6, but points to the empty B7.
            ws.write_formula(r - 1, 2, "=B7*$D$2", None, 0)
        else:
            ws.write_formula(r - 1, 2, f"=B{r}*$D$2", None, amount * 1.1)
    if bad:
        ws.set_row(5, None, None, {"hidden": True})  # row 6 is hidden


def add_summary(wb, bad: bool):
    ws = wb.add_worksheet("Summary")
    ws.write("A1", "Metric")
    ws.write("B1", "Value")
    ws.write("A2", "Revenue projection")
    if bad:
        ws.write_formula("B2", "=Inputs!B2*1.05", None, 1050)
    else:
        ws.write_formula("B2", "=Inputs!B2*(1+Inputs!B3)", None, 1030)
    ws.write("A3", "Total opex")
    ws.write_formula("B3", "=SUM(Opex!C2:C6)", None, 660)
    ws.write("A4", "Margin")
    if bad:
        ws.write_formula("B4", "=#REF!", None, "#REF!")
    else:
        ws.write_formula("B4", "=B2-B3", None, 370)
    ws.write("A5", "As of")
    if bad:
        ws.write_formula("B5", "=TODAY()", None, 46000)
    else:
        ws.write_formula("B5", "=Inputs!B5", None, 2026)
    if bad:
        ws.write("A6", "Broken lookup")
        ws.write_formula("B6", "=NA()", None, "#N/A")
        ws.write("A7", "External link")
        ws.write_formula("B7", "'[Book2.xlsx]Sheet1'!A1", None, 0)
        ws.write("A8", "Whole column")
        ws.write_formula("B8", "=SUM(Opex!C:C)", None, 660)
        ws.write("A9", "Uncached formula")
        ws.write_formula("B9", "=1+1", None, 0)


def add_tax(wb, bad: bool):
    ws = wb.add_worksheet("Tax")
    ws.write("A1", "Tax model")
    ws.write("A3", "Taxable")
    ws.write_number("C3", 100)
    ws.write("B3", "Tax")
    if bad:
        ws.write_formula("C3", "=D3*0.1", None, 0)
        ws.write_formula("D3", "=C3+1", None, 1)
    else:
        ws.write_formula("C3", "=Inputs!B2*Inputs!B3", None, 30)
        ws.write_formula("D3", "=C3+1", None, 101)


def add_scratch(wb, bad: bool):
    if not bad:
        return
    ws = wb.add_worksheet("Scratch")
    ws.hide()
    ws.write_formula("A1", "=Summary!B3+1", None, 661)
    ws.write_formula("A2", "=Inputs!B2", None, 1000)


def strip_cached_value(path: Path, cell: str) -> None:
    """Remove the cached <v> for one formula cell so it exercises the no-cache rule."""
    with zipfile.ZipFile(path, "r") as src:
        items = [(item, src.read(item.filename)) for item in src.infolist()]
    patched = []
    for item, data in items:
        if item.filename == "xl/worksheets/sheet3.xml":
            text = data.decode("utf-8")
            start = text.find(f'<c r="{cell}"')
            if start != -1:
                end = text.find("</c>", start)
                block = text[start:end]
                f_end = block.find("</f>") + len("</f>")
                block = block[:f_end] + block[block.find("</v>") + len("</v>"):] if "</v>" in block else block
                text = text[:start] + block + text[end:]
            data = text.encode("utf-8")
        patched.append((item, data))
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as dst:
        for item, data in patched:
            dst.writestr(item, data)


def build(path: Path, bad: bool):
    wb = xlsxwriter.Workbook(path)
    wb.set_properties({"title": "SheetSentry bad model" if bad else "SheetSentry clean model"})
    add_inputs(wb)
    add_opex(wb, bad)
    add_summary(wb, bad)
    add_tax(wb, bad)
    add_scratch(wb, bad)
    wb.close()
    if bad:
        strip_cached_value(path, "B9")
    print(path)


if __name__ == "__main__":
    FIXTURES.mkdir(exist_ok=True)
    build(FIXTURES / "bad_model.xlsx", True)
    build(FIXTURES / "clean_model.xlsx", False)

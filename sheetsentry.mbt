///|
pub(all) struct WorkbookSummary {
  sheets : Array[String]
  formula_cells : Int
  stored_cells : Int
}

///|
pub fn summarize_bytes(bytes : Bytes) -> WorkbookSummary raise @xlsx.XlsxError {
  let workbook = @xlsx.read(bytes)
  let names = workbook.get_sheet_list()
  let mut formula_cells = 0
  let mut stored_cells = 0
  for name in names {
    guard workbook.sheet(name) is Some(sheet) else { continue }
    let max_row = sheet.max_row()
    let max_col = sheet.max_col()
    stored_cells = stored_cells + sheet.stored_cell_count()
    for row in 1..=max_row {
      for col in 1..=max_col {
        let reference = @xlsx.coordinates_to_cell_name(col, row)
        match sheet.get_cell_formula(reference) {
          Some(_) => formula_cells = formula_cells + 1
          None => ()
        }
      }
    }
  }
  { sheets: names, formula_cells, stored_cells }
}

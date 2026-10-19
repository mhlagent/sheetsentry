///|
fn main {
  try {
    let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
    let workbook = @mbtexcel.read(bytes)
    let sheet = workbook.sheet("Opex").unwrap()
    for r in 2..=6 {
      let ref = @mbtexcel.coordinates_to_cell_name(r, 3)
      println("\{ref} raw=\{sheet.get_cell_rc(r, 3)} formula=\{sheet.get_cell_formula(ref)}")
    }
    let summary = workbook.sheet("Summary").unwrap()
    for r in 2..=6 {
      let ref = @mbtexcel.coordinates_to_cell_name(r, 2)
      println("Summary \{ref} raw=\{summary.get_cell_rc(r, 2)} formula=\{summary.get_cell_formula(ref)}")
    }
  } catch {
    err => println("error: \{err}")
  }
}

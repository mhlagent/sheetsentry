///|
test "summarize bad model" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let summary = @sheetsentry.summarize_bytes(bytes)
  assert_eq(summary.sheets.length(), 5)
  assert_eq(summary.sheets[0], "Inputs")
  assert_eq(summary.formula_cells, 14)
}

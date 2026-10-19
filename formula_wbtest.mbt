///|
test "extract refs and dynamic functions" {
  let refs = extract_refs("=SUM(Opex!C2:C6)+$B$2*1.05+INDIRECT(\"A1\")", "Summary")
  assert_eq(refs.cells.length(), 2)
  assert_eq(refs.cells[0].sheet, Some("Opex"))
  assert_eq(refs.cells[0].row, 2)
  assert_eq(refs.cells[0].col, 3)
  assert_eq(refs.cells[0].end_row, 6)
  assert_eq(refs.cells[0].end_col, 3)
  assert_eq(refs.cells[1].abs_row, true)
  assert_eq(refs.cells[1].abs_col, true)
  assert_eq(refs.dynamic, true)
  assert_eq(refs.names.length(), 0)
}

///|
test "function names" {
  let names = function_names("=IF(A1>0,SUM(B1:B3),TODAY())")
  assert_eq(names.length(), 3)
  assert_eq(names[0], "IF")
  assert_eq(names[1], "SUM")
  assert_eq(names[2], "TODAY")
}

///|
test "numeric literals skip refs and strings" {
  let nums = numeric_literals("=A1*1.05+100-2.5E3+\"42\"")
  assert_eq(nums.length(), 3)
  assert_eq(nums[0], "1.05")
  assert_eq(nums[1], "100")
  assert_eq(nums[2], "-2.5E3")
}

///|
test "normalize relative formulas" {
  let a = normalize_formula("=B2*$C$2", "Opex", 2, 3)
  let b = normalize_formula("=B3*$C$2", "Opex", 3, 3)
  assert_eq(a, b)
}

///|
test "quoted sheet reference" {
  let refs = extract_refs("='Sheet 1'!$A$1+1", "Summary")
  assert_eq(refs.cells.length(), 1)
  assert_eq(refs.cells[0].sheet, Some("Sheet 1"))
  assert_eq(refs.cells[0].row, 1)
  assert_eq(refs.cells[0].col, 1)
  assert_eq(refs.cells[0].abs_row, true)
  assert_eq(refs.cells[0].abs_col, true)
}

///|
test "numeric literals skip sheet name digits" {
  let nums = numeric_literals("=Sheet1!A1+2")
  assert_eq(nums.length(), 1)
  assert_eq(nums[0], "2")
}

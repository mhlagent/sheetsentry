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

///|
test "plain cell reference" {
  let refs = extract_refs("=A1+B2", "Sheet1")
  assert_eq(refs.cells.length(), 2)
  assert_eq(refs.cells[0].sheet, None)
  assert_eq(refs.cells[0].row, 1)
  assert_eq(refs.cells[0].col, 1)
}

///|
test "absolute reference flags" {
  let refs = extract_refs("=$A$1+$B2+C$3", "Sheet1")
  assert_eq(refs.cells.length(), 3)
  assert_true(refs.cells[0].abs_col)
  assert_true(refs.cells[0].abs_row)
  assert_true(refs.cells[1].abs_col)
  assert_false(refs.cells[1].abs_row)
  assert_false(refs.cells[2].abs_col)
  assert_true(refs.cells[2].abs_row)
}

///|
test "range reference" {
  let refs = extract_refs("=SUM(A1:B10)", "Sheet1")
  assert_eq(refs.cells.length(), 1)
  assert_eq(refs.cells[0].row, 1)
  assert_eq(refs.cells[0].end_row, 10)
  assert_eq(refs.cells[0].col, 1)
  assert_eq(refs.cells[0].end_col, 2)
}

///|
test "multiple refs keep order" {
  let refs = extract_refs("=C3+A1+B2", "Sheet1")
  assert_eq(refs.cells.length(), 3)
  assert_eq(refs.cells[0].col, 3)
  assert_eq(refs.cells[1].col, 1)
  assert_eq(refs.cells[2].col, 2)
}

///|
test "string literals are not refs" {
  let refs = extract_refs("=\"A1 and B2\"+C3", "Sheet1")
  assert_eq(refs.cells.length(), 1)
  assert_eq(refs.cells[0].col, 3)
}

///|
test "error literals are not refs" {
  let refs = extract_refs("=#REF!+A1", "Sheet1")
  assert_eq(refs.cells.length(), 1)
  assert_eq(refs.cells[0].col, 1)
}

///|
test "functions are case insensitive" {
  let names = function_names("=sum(A1:A3)+if(B1,1,0)")
  assert_eq(names.length(), 2)
  assert_eq(names[0], "SUM")
  assert_eq(names[1], "IF")
}

///|
test "named range is captured" {
  let refs = extract_refs("=Revenue*GrowthRate", "Summary")
  assert_eq(refs.names.length(), 2)
  assert_eq(refs.names[0], "Revenue")
  assert_eq(refs.names[1], "GrowthRate")
}

///|
test "offset marks dynamic" {
  let refs = extract_refs("=OFFSET(A1,1,1)", "Sheet1")
  assert_true(refs.dynamic)
}

///|
test "absolute refs stay absolute when normalized" {
  let a = normalize_formula("=$A$1+B2", "Sheet1", 2, 2)
  let b = normalize_formula("=$A$1+C3", "Sheet1", 3, 3)
  assert_eq(a, b)
}

///|
test "range normalization keeps endpoints" {
  let normalized = normalize_formula("=SUM(B2:C3)", "Sheet1", 2, 2)
  assert_true(normalized.contains("R[0]C[0]:R[1]C[1]"))
}

///|
test "whole axis detection" {
  assert_true(has_whole_axis_ref("=SUM(A:A)"))
  assert_true(has_whole_axis_ref("=SUM(1:1)"))
  assert_false(has_whole_axis_ref("=SUM(A1:B2)"))
}

///|
test "external link detection" {
  assert_eq(external_link("='[Book2.xlsx]Sheet1'!A1"), Some("Book2.xlsx"))
  assert_eq(external_link("=A1+B2"), None)
}

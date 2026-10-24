///|
pub(all) struct SliceResult {
  data : Bytes
  manifest : SliceManifest
}

///|
pub(all) struct SliceManifest {
  source_file : String
  target : String
  source_sha256 : String
  slice_sha256 : String
  included_cells : Array[String]
  included_sheets : Array[String]
  unresolved : Array[String]
  external_workbooks : Array[String]
  external_cells : Array[String]
  target_value_before : String?
  target_value_after : String?
  verified : Bool
  complete : Bool
}

///|
fn hex_digit(value : Int) -> String {
  let digits = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]
  digits[value]
}

///|
fn hex_bytes(bytes : FixedArray[Byte]) -> String {
  let mut out = ""
  for byte in bytes {
    let value = byte.to_int()
    out = out + hex_digit((value >> 4) & 15) + hex_digit(value & 15)
  }
  out
}

///|
fn cell_key_parts(key : String) -> (String, String) {
  let parts = key.split("!").collect()
  match parts {
    [sheet, cell] => (sheet.to_owned(), cell.to_owned())
    _ => ("", key)
  }
}

///|
fn array_contains(items : Array[String], value : String) -> Bool {
  for item in items {
    if item == value {
      return true
    }
  }
  false
}

///|
fn copy_cell(
  source : @xlsx.Worksheet,
  destination : @xlsx.Worksheet,
  cell : String,
  formula_override : String?,
) -> Unit raise @xlsx.XlsxError {
  match source.get_cell_formula(cell) {
    Some(formula) => {
      let formula = match formula_override {
        Some(value) => value
        None => formula
      }
      // Read the cached value through the A1 API.
      let raw = source.get_cell(cell)
      match raw {
        Some(value) => destination.set_cell_formula(cell, formula, value=value)
        None => destination.set_cell_formula(cell, formula)
      }
    }
    None => {
      match source.get_cell_value_raw(cell) {
        Some(value) => destination.set_cell_value(cell, value)
        None => ()
      }
    }
  }
}

///|
fn sanitize_sheet_name(value : String) -> String {
  let mut out = ""
  for c in value {
    match c {
      ':' | '\\' | '/' | '?' | '*' | '[' | ']' => out = out + "_"
      _ => out = out + c.to_string()
    }
  }
  if out.length() > 31 {
    out[:31].to_owned()
  } else {
    out
  }
}

///|
fn external_sheet_name(workbook : String, sheet : String) -> String {
  let base = if workbook.has_suffix(".xlsx") {
    workbook[:workbook.length() - 5].to_owned()
  } else if workbook.has_suffix(".xlsm") {
    workbook[:workbook.length() - 5].to_owned()
  } else if workbook.has_suffix(".xls") {
    workbook[:workbook.length() - 4].to_owned()
  } else {
    workbook
  }
  sanitize_sheet_name("__ext__" + base + "__" + sheet)
}

///|
fn rewrite_with_external(
  formula : StringView,
  node : String,
  output : @xlsx.Workbook,
  external_workbooks : Map[String, Bytes],
  external_names : Array[String],
  external_cells : Array[String],
  unresolved : Array[String],
  ext_sheets : Map[String, Bool],
) -> String raise @xlsx.XlsxError {
  let refs = external_refs(formula)
  if refs.length() == 0 {
    return formula.to_owned()
  }
  let mut out = ""
  let mut last = 0
  for ext in refs {
    out = out + formula[last:ext.start].to_owned()
    let replacement = match external_workbooks.get(ext.workbook) {
      Some(bytes) => {
        let external = @xlsx.read(bytes)
        let external_sheet = match external.sheet(ext.sheet) {
          Some(value) => value
          None => {
            unresolved.push("external-sheet:\{ext.workbook}:\{ext.sheet}")
            out = out + formula[ext.start:ext.end].to_owned()
            last = ext.end
            continue
          }
        }
        let cell = @xlsx.coordinates_to_cell_name(ext.col, ext.row)
        let value = external_sheet.get_cell_value_raw(cell)
        let name = external_sheet_name(ext.workbook, ext.sheet)
        if !ext_sheets.contains(name) {
          ignore(output.add_sheet(name))
          ext_sheets.set(name, true)
        }
        let destination = match output.sheet(name) {
          Some(value) => value
          None => {
            unresolved.push("external-output-sheet:\{name}")
            out = out + formula[ext.start:ext.end].to_owned()
            last = ext.end
            continue
          }
        }
        match value {
          Some(value) => {
            destination.set_cell_value(cell, value)
            if !array_contains(external_names, ext.workbook) {
              external_names.push(ext.workbook)
            }
            external_cells.push("\{ext.workbook}!\{ext.sheet}!\{cell}")
            "'" + name + "'!" + cell
          }
          None => {
            unresolved.push("external-cell:\{ext.workbook}!\{ext.sheet}!\{cell}")
            formula[ext.start:ext.end].to_owned()
          }
        }
      }
      None => {
        unresolved.push("external:\{ext.workbook}:\{node}")
        formula[ext.start:ext.end].to_owned()
      }
    }
    out = out + replacement
    last = ext.end
  }
  out + formula[last:].to_owned()
}

///|
fn row_of(cell : String) -> Int raise @xlsx.XlsxError {
  let (_, row) = @xlsx.cell_name_to_coordinates(cell)
  row
}

///|
pub fn slice_bytes(
  source_bytes : Bytes,
  source_file : String,
  target : String,
  max_depth : Int,
) -> SliceResult raise @xlsx.XlsxError {
  slice_bytes_with_external(source_bytes, source_file, target, max_depth, Map([]))
}

///|
pub fn slice_bytes_with_external(
  source_bytes : Bytes,
  source_file : String,
  target : String,
  max_depth : Int,
  external_workbooks : Map[String, Bytes],
) -> SliceResult raise @xlsx.XlsxError {
  let source = @xlsx.read(source_bytes)
  let tables = table_catalog(source_bytes, source.get_sheet_list())
  let nodes = trace_bytes(source_bytes, target, "precedents", max_depth)
  let included : Array[String] = []
  let sheets : Array[String] = []
  for node in nodes {
    included.push(node)
    let (sheet, _) = cell_key_parts(node)
    if sheet != "" && !array_contains(sheets, sheet) {
      sheets.push(sheet)
    }
  }
  let output = @mbtexcel.new_workbook()
  for sheet_name in sheets {
    ignore(output.add_sheet(sheet_name))
  }
  let unresolved : Array[String] = []
  let used_names : Array[String] = []
  let external_names : Array[String] = []
  let external_cells : Array[String] = []
  let ext_sheets : Map[String, Bool] = Map([])
  for node in nodes {
    let (sheet_name, cell) = cell_key_parts(node)
    if sheet_name == "" {
      unresolved.push("invalid:\{node}")
      continue
    }
    let source_sheet = match source.sheet(sheet_name) {
      Some(value) => value
      None => {
        unresolved.push("missing-sheet:\{sheet_name}")
        continue
      }
    }
    let destination = match output.sheet(sheet_name) {
      Some(value) => value
      None => {
        unresolved.push("missing-output-sheet:\{sheet_name}")
        continue
      }
    }
    let formula_override = match source_sheet.get_cell_formula(cell) {
      Some(formula) => {
        let table_rewritten = rewrite_structured_refs(formula, sheet_name, row_of(cell), tables)
        Some(
          rewrite_with_external(
            table_rewritten,
            node,
            output,
            external_workbooks,
            external_names,
            external_cells,
            unresolved,
            ext_sheets,
          ),
        )
      }
      None => None
    }
    match source_sheet.get_cell_formula(cell) {
      Some(formula) => {
        let refs = extract_refs(formula, sheet_name)
        for r in resolve_formula_cells(source, tables, sheet_name, formula, row_of(cell)) {
          let ref_sheet = match r.sheet {
            Some(value) => value
            None => sheet_name
          }
          if !array_contains(sheets, ref_sheet) {
            let lo_row = if r.row < r.end_row { r.row } else { r.end_row }
            let lo_col = if r.col < r.end_col { r.col } else { r.end_col }
            unresolved.push("missing-dependency:\{ref_sheet}!\{@xlsx.coordinates_to_cell_name(lo_col, lo_row)}")
          }
        }
        if refs.dynamic && dynamic_refs(formula, sheet_name, row_of(cell), source).length() == 0 {
          unresolved.push("dynamic:\{node}")
        }
        match external_link(formula) {
          Some(workbook) => if !external_workbooks.contains(workbook) {
            unresolved.push("external:\{workbook}:\{node}")
          }
          None => ()
        }
        let external_defs = external_refs(formula)
        for name in refs.names {
          if is_table_symbol(tables, name) {
            continue
          }
          let mut external_symbol = false
          for ext in external_defs {
            if name == ext.workbook || name == ext.sheet {
              external_symbol = true
            }
          }
          if external_symbol {
            continue
          }
          if named_refs(source, name, sheet_name).length() == 0 {
            unresolved.push("name:\{name}:\{node}")
          } else if !array_contains(used_names, name) {
            used_names.push(name)
          }
        }
        if formula.contains("[") && external_link(formula) == None && table_refs(formula, row_of(cell), tables).length() == 0 {
          unresolved.push("table-unresolved:\{node}")
        }
      }
      None => ()
    }
    copy_cell(source_sheet, destination, cell, formula_override)
  }
  for defined in source.get_defined_names() {
    if array_contains(used_names, defined.name) {
      output.set_defined_name(defined)
    }
  }
  let slice_data = @mbtexcel.write(output)
  let source_hash = hex_bytes(@crypto.sha256(source_bytes))
  let slice_hash = hex_bytes(@crypto.sha256(slice_data))
  let (target_sheet, target_cell) = cell_key_parts(target)
  let before = match source.sheet(target_sheet) {
    Some(sheet) => sheet.get_cell(target_cell)
    None => None
  }
  let sliced = @xlsx.read(slice_data)
  let after = match sliced.sheet(target_sheet) {
    Some(sheet) => sheet.get_cell(target_cell)
    None => None
  }
  let verified = match (before, after) {
    (Some(a), Some(b)) => a == b
    (None, None) => false
    _ => false
  }
  {
    data: slice_data,
    manifest: {
      source_file,
      target,
      source_sha256: source_hash,
      slice_sha256: slice_hash,
      included_cells: included,
      included_sheets: sheets,
      unresolved,
      external_workbooks: external_names,
      external_cells,
      target_value_before: before,
      target_value_after: after,
      verified,
      complete: unresolved.length() == 0,
    },
  }
}

///|
pub fn slice_manifest_json(manifest : SliceManifest) -> String {
  let cells = "[" + manifest.included_cells.map(fn(x) { "\"" + json_escape(x) + "\"" }).join(",") + "]"
  let sheets = "[" + manifest.included_sheets.map(fn(x) { "\"" + json_escape(x) + "\"" }).join(",") + "]"
  let unresolved = "[" + manifest.unresolved.map(fn(x) { "\"" + json_escape(x) + "\"" }).join(",") + "]"
  let external_workbooks = "[" + manifest.external_workbooks.map(fn(x) { "\"" + json_escape(x) + "\"" }).join(",") + "]"
  let external_cells = "[" + manifest.external_cells.map(fn(x) { "\"" + json_escape(x) + "\"" }).join(",") + "]"
  let before = match manifest.target_value_before {
    Some(value) => "\"" + json_escape(value) + "\""
    None => "null"
  }
  let after = match manifest.target_value_after {
    Some(value) => "\"" + json_escape(value) + "\""
    None => "null"
  }
  "{\"tool\":\"sheetsentry\",\"kind\":\"calculation-slice\",\"version\":\"\{tool_version()}\",\"source_file\":\"\{json_escape(manifest.source_file)}\",\"target\":\"\{json_escape(manifest.target)}\",\"source_sha256\":\"\{manifest.source_sha256}\",\"slice_sha256\":\"\{manifest.slice_sha256}\",\"included_cells\":\{cells},\"included_sheets\":\{sheets},\"unresolved\":\{unresolved},\"external_workbooks\":\{external_workbooks},\"external_cells\":\{external_cells},\"target_value_before\":\{before},\"target_value_after\":\{after},\"verified\":\{manifest.verified},\"complete\":\{manifest.complete}}"
}

///|
pub(all) struct SliceVerification {
  target : String
  before : String?
  after : String?
  verified : Bool
  error : String?
}

///|
pub fn verify_slice_bytes(
  slice_bytes : Bytes,
  manifest_text : String,
) -> SliceVerification raise @json.ParseError {
  let value = @json.parse(manifest_text)
  let mut target = ""
  let mut before : String? = None
  match value {
    Object(map) => {
      match map.get("target") {
        Some(String(value)) => target = value
        _ => ()
      }
      match map.get("target_value_before") {
        Some(String(value)) => before = Some(value)
        _ => ()
      }
    }
    _ => ()
  }
  let (sheet, cell) = cell_key_parts(target)
  let mut after : String? = None
  let mut error : String? = None
  try {
    let workbook = @xlsx.read(slice_bytes)
    after = match workbook.sheet(sheet) {
      Some(worksheet) => worksheet.get_cell(cell)
      None => None
    }
  } catch {
    _ => error = Some("failed to read slice workbook")
  }
  let verified = match (before, after) {
    (Some(a), Some(b)) => a == b
    _ => false
  }
  { target, before, after, verified, error }
}

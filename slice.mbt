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
) -> Unit raise @xlsx.XlsxError {
  match source.get_cell_formula(cell) {
    Some(formula) => {
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
pub fn slice_bytes(
  source_bytes : Bytes,
  source_file : String,
  target : String,
  max_depth : Int,
) -> SliceResult raise @xlsx.XlsxError {
  let source = @xlsx.read(source_bytes)
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
    match source_sheet.get_cell_formula(cell) {
      Some(formula) => {
        let refs = extract_refs(formula, sheet_name)
        for r in refs.cells {
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
        if refs.dynamic {
          unresolved.push("dynamic:\{node}")
        }
        match external_link(formula) {
          Some(workbook) => unresolved.push("external:\{workbook}:\{node}")
          None => ()
        }
        for name in refs.names {
          unresolved.push("name:\{name}:\{node}")
        }
      }
      None => ()
    }
    copy_cell(source_sheet, destination, cell)
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
  let before = match manifest.target_value_before {
    Some(value) => "\"" + json_escape(value) + "\""
    None => "null"
  }
  let after = match manifest.target_value_after {
    Some(value) => "\"" + json_escape(value) + "\""
    None => "null"
  }
  "{\"tool\":\"sheetsentry\",\"kind\":\"calculation-slice\",\"version\":\"\{tool_version()}\",\"source_file\":\"\{json_escape(manifest.source_file)}\",\"target\":\"\{json_escape(manifest.target)}\",\"source_sha256\":\"\{manifest.source_sha256}\",\"slice_sha256\":\"\{manifest.slice_sha256}\",\"included_cells\":\{cells},\"included_sheets\":\{sheets},\"unresolved\":\{unresolved},\"target_value_before\":\{before},\"target_value_after\":\{after},\"verified\":\{manifest.verified},\"complete\":\{manifest.complete}}"
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

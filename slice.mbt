///|
pub(all) struct SliceResult {
  data : Bytes
  manifest : SliceManifest
}

///|
pub(all) struct SliceTarget {
  target : String
  before : String?
  after : String?
  verified : Bool
}

///|
pub(all) struct SliceManifest {
  source_file : String
  target : String
  targets : Array[SliceTarget]
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
  slice_bytes_many(source_bytes, source_file, [target], max_depth, Map([]))
}

///|
pub fn slice_bytes_with_external(
  source_bytes : Bytes,
  source_file : String,
  target : String,
  max_depth : Int,
  external_workbooks : Map[String, Bytes],
) -> SliceResult raise @xlsx.XlsxError {
  slice_bytes_many(source_bytes, source_file, [target], max_depth, external_workbooks)
}

///|
pub fn slice_bytes_many(
  source_bytes : Bytes,
  source_file : String,
  targets : Array[String],
  max_depth : Int,
  external_workbooks : Map[String, Bytes],
) -> SliceResult raise @xlsx.XlsxError {
  let source = @xlsx.read(source_bytes)
  let tables = table_catalog(source_bytes, source.get_sheet_list())
  let nodes : Array[String] = []
  for target in targets {
    for node in trace_bytes(source_bytes, target, "precedents", max_depth) {
      if !array_contains(nodes, node) {
        nodes.push(node)
      }
    }
  }
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
  let sliced = @xlsx.read(slice_data)
  let target_results : Array[SliceTarget] = []
  for target in targets {
    let (target_sheet, target_cell) = cell_key_parts(target)
    let before = match source.sheet(target_sheet) {
      Some(sheet) => sheet.get_cell(target_cell)
      None => None
    }
    let after = match sliced.sheet(target_sheet) {
      Some(sheet) => sheet.get_cell(target_cell)
      None => None
    }
    let verified = match (before, after) {
      (Some(a), Some(b)) => a == b
      _ => false
    }
    target_results.push({ target, before, after, verified })
  }
  let primary = if target_results.length() > 0 {
    target_results[0]
  } else {
    { target: "", before: None, after: None, verified: false }
  }
  let all_verified = target_results.length() > 0 && target_results.all(fn(item) { item.verified })
  {
    data: slice_data,
    manifest: {
      source_file,
      target: primary.target,
      targets: target_results,
      source_sha256: source_hash,
      slice_sha256: slice_hash,
      included_cells: included,
      included_sheets: sheets,
      unresolved,
      external_workbooks: external_names,
      external_cells,
      target_value_before: primary.before,
      target_value_after: primary.after,
      verified: all_verified,
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
  let targets = "[" + manifest.targets.map(fn(item) {
    let before = match item.before {
      Some(value) => "\"" + json_escape(value) + "\""
      None => "null"
    }
    let after = match item.after {
      Some(value) => "\"" + json_escape(value) + "\""
      None => "null"
    }
    "{\"target\":\"" + json_escape(item.target) + "\",\"before\":" + before + ",\"after\":" + after + ",\"verified\":" + item.verified.to_string() + "}"
  }).join(",") + "]"
  let before = match manifest.target_value_before {
    Some(value) => "\"" + json_escape(value) + "\""
    None => "null"
  }
  let after = match manifest.target_value_after {
    Some(value) => "\"" + json_escape(value) + "\""
    None => "null"
  }
  "{\"tool\":\"sheetsentry\",\"kind\":\"calculation-slice\",\"version\":\"\{tool_version()}\",\"source_file\":\"\{json_escape(manifest.source_file)}\",\"target\":\"\{json_escape(manifest.target)}\",\"targets\":\{targets},\"source_sha256\":\"\{manifest.source_sha256}\",\"slice_sha256\":\"\{manifest.slice_sha256}\",\"included_cells\":\{cells},\"included_sheets\":\{sheets},\"unresolved\":\{unresolved},\"external_workbooks\":\{external_workbooks},\"external_cells\":\{external_cells},\"target_value_before\":\{before},\"target_value_after\":\{after},\"verified\":\{manifest.verified},\"complete\":\{manifest.complete}}"
}

///|
pub(all) struct SliceVerification {
  target : String
  before : String?
  after : String?
  verified : Bool
  hash_verified : Bool
  targets_total : Int
  targets_verified : Int
  error : String?
}

///|
fn manifest_targets(map : Map[String, Json]) -> Array[(String, String?)] {
  let result : Array[(String, String?)] = []
  match map.get("targets") {
    Some(Array(items)) =>
      for item in items {
        match item {
          Object(target_map) => {
            let target = match target_map.get("target") {
              Some(String(value)) => value
              _ => ""
            }
            let before = match target_map.get("before") {
              Some(String(value)) => Some(value)
              _ => None
            }
            if target != "" {
              result.push((target, before))
            }
          }
          _ => ()
        }
      }
    _ => ()
  }
  if result.length() == 0 {
    let target = match map.get("target") {
      Some(String(value)) => value
      _ => ""
    }
    let before = match map.get("target_value_before") {
      Some(String(value)) => Some(value)
      _ => None
    }
    if target != "" {
      result.push((target, before))
    }
  }
  result
}

///|
pub fn verify_slice_bytes(
  slice_bytes : Bytes,
  manifest_text : String,
) -> SliceVerification raise @json.ParseError {
  let value = @json.parse(manifest_text)
  let mut expected_hash = ""
  let mut targets : Array[(String, String?)] = []
  match value {
    Object(map) => {
      match map.get("slice_sha256") {
        Some(String(value)) => expected_hash = value
        _ => ()
      }
      targets = manifest_targets(map)
    }
    _ => ()
  }
  let actual_hash = hex_bytes(@crypto.sha256(slice_bytes))
  let hash_verified = expected_hash != "" && expected_hash == actual_hash
  let mut targets_verified = 0
  let mut primary_target = ""
  let mut primary_before : String? = None
  let mut primary_after : String? = None
  let mut error : String? = None
  try {
    let workbook = @xlsx.read(slice_bytes)
    for index, item in targets {
      let (target, before) = item
      let (sheet, cell) = cell_key_parts(target)
      let after = match workbook.sheet(sheet) {
        Some(worksheet) => worksheet.get_cell(cell)
        None => None
      }
      let verified = match (before, after) {
        (Some(a), Some(b)) => a == b
        _ => false
      }
      if verified {
        targets_verified = targets_verified + 1
      }
      if index == 0 {
        primary_target = target
        primary_before = before
        primary_after = after
      }
    }
  } catch {
    _ => error = Some("failed to read slice workbook")
  }
  let verified = targets.length() > 0 && targets_verified == targets.length()
  {
    target: primary_target,
    before: primary_before,
    after: primary_after,
    verified,
    hash_verified,
    targets_total: targets.length(),
    targets_verified,
    error,
  }
}

///|
pub fn slice_report_html(manifest : SliceManifest) -> String {
  let mut target_rows = ""
  for item in manifest.targets {
    let before = match item.before {
      Some(value) => html_escape(value)
      None => "<missing>"
    }
    let after = match item.after {
      Some(value) => html_escape(value)
      None => "<missing>"
    }
    target_rows = target_rows + "<tr><td>\{html_escape(item.target)}</td><td>\{before}</td><td>\{after}</td><td>\{item.verified}</td></tr>"
  }
  let sheets = manifest.included_sheets.map(fn(x) { "<li>" + html_escape(x) + "</li>" }).join("")
  let unresolved = if manifest.unresolved.length() == 0 {
    "<p class=\"ok\">No unresolved dependencies.</p>"
  } else {
    "<ul>" + manifest.unresolved.map(fn(x) { "<li>" + html_escape(x) + "</li>" }).join("") + "</ul>"
  }
  "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>SheetSentry slice certificate</title><style>body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;margin:32px;color:#1f2937;background:#f8fafc}h1{margin:0 0 6px}.meta{color:#64748b;margin-bottom:24px}.cards{display:flex;gap:12px;margin-bottom:24px}.card{background:white;border:1px solid #e2e8f0;border-radius:10px;padding:14px 18px;min-width:120px}.card b{display:block;font-size:24px}table{width:100%;border-collapse:collapse;background:white;border:1px solid #e2e8f0;margin-bottom:20px}th,td{padding:10px 12px;border-bottom:1px solid #e2e8f0;text-align:left;font-size:13px}th{background:#f1f5f9}.ok{color:#15803d;font-weight:600}.bad{color:#dc2626;font-weight:600}code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;word-break:break-all}</style></head><body><h1>SheetSentry slice certificate</h1><div class=\"meta\">\{html_escape(manifest.source_file)} · target count \{manifest.targets.length()}</div><div class=\"cards\"><div class=\"card\"><b>\{manifest.included_cells.length()}</b>cells</div><div class=\"card\"><b>\{manifest.included_sheets.length()}</b>sheets</div><div class=\"card\"><b>\{manifest.external_workbooks.length()}</b>external</div><div class=\"card\"><b class=\"\{if manifest.verified { "ok" } else { "bad" }}\">\{manifest.verified}</b>verified</div><div class=\"card\"><b>\{manifest.complete}</b>complete</div></div><h2>Targets</h2><table><thead><tr><th>Target</th><th>Before</th><th>After</th><th>Verified</th></tr></thead><tbody>\{target_rows}</tbody></table><h2>Integrity</h2><table><tr><th>Source SHA-256</th><td><code>\{manifest.source_sha256}</code></td></tr><tr><th>Slice SHA-256</th><td><code>\{manifest.slice_sha256}</code></td></tr></table><h2>Included sheets</h2><ul>\{sheets}</ul><h2>Unresolved dependencies</h2>\{unresolved}</body></html>"
}

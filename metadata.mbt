///|
pub(all) struct TableInfo {
  name : String
  sheet : String
  start_row : Int
  start_col : Int
  end_row : Int
  end_col : Int
  columns : Array[String]
}

///|
fn find_sub(text : StringView, needle : StringView, start : Int) -> Int? {
  let n = needle.length()
  if n == 0 {
    return Some(start)
  }
  let mut i = start
  while i + n <= text.length() {
    if text[i:i + n] == needle {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
fn xml_attr(tag : StringView, name : String) -> String? {
  let needle = name + "=\""
  match find_sub(tag, needle[:], 0) {
    Some(pos) => {
      let start = pos + needle.length()
      match find_sub(tag, "\"", start) {
        Some(end) => Some(tag[start:end].to_owned())
        None => None
      }
    }
    None => None
  }
}

///|
fn xml_elements(xml : StringView, marker : String) -> Array[String] {
  let result : Array[String] = []
  let mut i = 0
  while i < xml.length() {
    match find_sub(xml, marker[:], i) {
      Some(start) => {
        match find_sub(xml, ">", start) {
          Some(end) => {
            result.push(xml[start:end + 1].to_owned())
            i = end + 1
          }
          None => break
        }
      }
      None => break
    }
  }
  result
}

///|
fn normalize_zip_target(target : String) -> String {
  if target.has_prefix("../") {
    "xl/" + target[3:].to_owned()
  } else if target.has_prefix("/") {
    target[1:].to_owned()
  } else {
    target
  }
}

///|
pub fn table_catalog(bytes : BytesView, sheets : Array[String]) -> Array[TableInfo] {
  let result : Array[TableInfo] = []
  let archive = @zip.read(bytes) catch { _ => return result }
  for index, sheet_name in sheets {
    let sheet_path = "xl/worksheets/sheet\{(index + 1)}.xml"
    let rels_path = "xl/worksheets/_rels/sheet\{(index + 1)}.xml.rels"
    let sheet_xml = match archive.get(sheet_path) {
      Some(value) => @utf8.decode_lossy(value)
      None => continue
    }
    let rels_xml = match archive.get(rels_path) {
      Some(value) => @utf8.decode_lossy(value)
      None => continue
    }
    let rel_map : Map[String, String] = Map([])
    for rel in xml_elements(rels_xml, "<Relationship ") {
      match (xml_attr(rel, "Id"), xml_attr(rel, "Target")) {
        (Some(id), Some(target)) => rel_map.set(id, target)
        _ => ()
      }
    }
    for part in xml_elements(sheet_xml, "<tablePart ") {
      match xml_attr(part, "r:id") {
        Some(id) =>
          match rel_map.get(id) {
            Some(target) => {
              let table_path = normalize_zip_target(target)
              match archive.get(table_path) {
                Some(table_bytes) => {
                  let table_xml = @utf8.decode_lossy(table_bytes)
                  let table_tag = match xml_elements(table_xml, "<table ") {
                    [tag, ..] => tag
                    _ => continue
                  }
                  let name = xml_attr(table_tag, "name")
                  let range = xml_attr(table_tag, "ref")
                  match (name, range) {
                    (Some(name), Some(range)) => {
                      let refs = extract_refs(range, sheet_name)
                      match refs.cells {
                        [cellref, ..] => {
                          let columns : Array[String] = []
                          for column in xml_elements(table_xml, "<tableColumn ") {
                            match xml_attr(column, "name") {
                              Some(value) => columns.push(value)
                              None => ()
                            }
                          }
                          result.push({
                            name,
                            sheet: sheet_name,
                            start_row: cellref.row,
                            start_col: cellref.col,
                            end_row: cellref.end_row,
                            end_col: cellref.end_col,
                            columns,
                          })
                        }
                        _ => ()
                      }
                    }
                    _ => ()
                  }
                }
                None => ()
              }
            }
            None => ()
          }
        None => ()
      }
    }
  }
  result
}

///|
pub fn table_column_index(table : TableInfo, column : String) -> Int? {
  for index, name in table.columns {
    if name == column {
      return Some(index + 1)
    }
  }
  None
}

///|
pub fn table_refs(
  formula : StringView,
  current_row : Int,
  tables : Array[TableInfo],
) -> Array[CellRef] {
  let result : Array[CellRef] = []
  for table in tables {
    let marker = table.name + "["
    let mut i = 0
    while i < formula.length() {
      match find_sub(formula, marker[:], i) {
        Some(start) => {
          let content_start = start + marker.length()
          match find_sub(formula, "]", content_start) {
            Some(end) => {
              let content = formula[content_start:end].to_owned()
              let mut column = content
              let mut at_row = false
              let mut all_rows = false
              if column.has_prefix("@") {
                at_row = true
                column = column[1:].to_owned()
              } else if column == "#All" {
                all_rows = true
              } else if column.has_prefix("[#Data],[") && column.has_suffix("]") {
                column = column[9:column.length() - 1].to_owned()
              } else if column.has_prefix("#Data") || column.has_prefix("#Headers") || column.has_prefix("#Totals") {
                column = ""
              }
              if all_rows || column == "" {
                result.push({
                  start: 0,
                  end: 0,
                  sheet: Some(table.sheet),
                  row: table.start_row,
                  col: table.start_col,
                  end_row: table.end_row,
                  end_col: table.end_col,
                  abs_row: false,
                  abs_col: false,
                })
              } else {
                match table_column_index(table, column) {
                  Some(column_index) => {
                    let col = table.start_col + column_index - 1
                    let (row, end_row) = if at_row {
                      (current_row, current_row)
                    } else {
                      (table.start_row + 1, table.end_row)
                    }
                    result.push({
                      start: 0,
                      end: 0,
                      sheet: Some(table.sheet),
                      row,
                      col,
                      end_row,
                      end_col: col,
                      abs_row: false,
                      abs_col: false,
                    })
                  }
                  None => ()
                }
              }
              i = end + 1
            }
            None => break
          }
        }
        None => break
      }
    }
  }
  result
}

///|
pub fn named_refs(
  workbook : @xlsx.Workbook,
  name : String,
  current_sheet : String,
) -> Array[CellRef] {
  let result : Array[CellRef] = []
  for defined in workbook.get_defined_names() {
    if defined.name == name {
      let scope = if defined.scope != "Workbook" && workbook.sheet(defined.scope) is Some(_) {
        defined.scope
      } else {
        current_sheet
      }
      let refs = extract_refs(defined.refers_to, scope)
      for cell in refs.cells {
        result.push(cell)
      }
    }
  }
  result
}

///|
fn digit_value(c : Char) -> Int {
  match c {
    '0' => 0
    '1' => 1
    '2' => 2
    '3' => 3
    '4' => 4
    '5' => 5
    '6' => 6
    '7' => 7
    '8' => 8
    '9' => 9
    _ => 0
  }
}

///|
fn parse_signed_int(text : StringView, start : Int) -> (Int, Int)? {
  let mut i = start
  while i < text.length() && text.get_char(i).unwrap_or('\u0000').is_ascii_whitespace() {
    i = i + 1
  }
  let mut sign = 1
  if i < text.length() && text.get_char(i).unwrap_or('\u0000') == '-' {
    sign = -1
    i = i + 1
  } else if i < text.length() && text.get_char(i).unwrap_or('\u0000') == '+' {
    i = i + 1
  }
  let begin = i
  let mut value = 0
  while i < text.length() && text.get_char(i).unwrap_or('\u0000').is_ascii_digit() {
    value = value * 10 + digit_value(text.get_char(i).unwrap_or('0'))
    i = i + 1
  }
  if i == begin {
    None
  } else {
    Some((sign * value, i))
  }
}

///|
pub fn dynamic_refs(
  formula : StringView,
  current_sheet : String,
  _current_row : Int,
  _workbook : @xlsx.Workbook,
) -> Array[CellRef] {
  let result : Array[CellRef] = []
  let upper = formula.to_owned().to_upper()
  let mut search = 0
  while true {
    match find_sub(upper, "INDIRECT(", search) {
      Some(pos) => {
        let mut i = pos + 9
        while i < formula.length() && formula.get_char(i).unwrap_or('\u0000').is_ascii_whitespace() {
          i = i + 1
        }
        if i < formula.length() && formula.get_char(i).unwrap_or('\u0000') == '"' {
          let mut j = i + 1
          let mut content = ""
          while j < formula.length() {
            let c = formula.get_char(j).unwrap_or('\u0000')
            if c == '"' {
              if j + 1 < formula.length() && formula.get_char(j + 1).unwrap_or('\u0000') == '"' {
                content = content + "\""
                j = j + 2
              } else {
                break
              }
            } else {
              content = content + c.to_string()
              j = j + 1
            }
          }
          let refs = extract_refs(content, current_sheet)
          for cell in refs.cells {
            result.push(cell)
          }
          search = j + 1
        } else {
          search = pos + 9
        }
      }
      None => break
    }
  }
  search = 0
  while true {
    match find_sub(upper, "OFFSET(", search) {
      Some(pos) => {
        let arg_start = pos + 7
        let mut arg_end = arg_start
        while arg_end < formula.length() {
          let c = formula.get_char(arg_end).unwrap_or('\u0000')
          if c == ',' || c == ')' {
            break
          }
          arg_end = arg_end + 1
        }
        let base_refs = extract_refs(formula[arg_start:arg_end], current_sheet)
        match base_refs.cells {
          [base, ..] => {
            let mut p = arg_end
            if p < formula.length() && formula.get_char(p).unwrap_or('\u0000') == ',' {
              p = p + 1
            }
            match parse_signed_int(formula, p) {
              Some((rows, next)) => {
                p = next
                if p < formula.length() && formula.get_char(p).unwrap_or('\u0000') == ',' {
                  p = p + 1
                }
                match parse_signed_int(formula, p) {
                  Some((cols, _)) => {
                    let row = base.row + rows
                    let col = base.col + cols
                    if row > 0 && col > 0 {
                      result.push({
                        start: 0,
                        end: 0,
                        sheet: base.sheet,
                        row,
                        col,
                        end_row: row,
                        end_col: col,
                        abs_row: false,
                        abs_col: false,
                      })
                    }
                  }
                  None => ()
                }
              }
              None => ()
            }
          }
          _ => ()
        }
        search = pos + 7
      }
      None => break
    }
  }
  result
}

///|
pub fn resolve_formula_cells(
  workbook : @xlsx.Workbook,
  tables : Array[TableInfo],
  sheet : String,
  formula : StringView,
  row : Int,
) -> Array[CellRef] {
  let refs = extract_refs(formula, sheet)
  let externals = external_refs(formula)
  let external_sheets : Array[String] = []
  let external_names : Array[String] = []
  for ext in externals {
    external_sheets.push(ext.sheet)
    external_names.push(ext.workbook)
  }
  let result : Array[CellRef] = []
  for cell in refs.cells {
    let ref_sheet = match cell.sheet {
      Some(value) => value
      None => sheet
    }
    let mut skip = false
    for external_sheet in external_sheets {
      if ref_sheet == external_sheet {
        skip = true
      }
    }
    if !skip {
      result.push(cell)
    }
  }
  for name in refs.names {
    let mut skip = false
    for external_name in external_names {
      if name == external_name {
        skip = true
      }
    }
    for external_sheet in external_sheets {
      if name == external_sheet {
        skip = true
      }
    }
    if !skip {
      for cell in named_refs(workbook, name, sheet) {
        result.push(cell)
      }
    }
  }
  for cell in dynamic_refs(formula, sheet, row, workbook) {
    result.push(cell)
  }
  for cell in table_refs(formula, row, tables) {
    result.push(cell)
  }
  result
}

///|
fn absolute_range(
  sheet : String,
  start_row : Int,
  start_col : Int,
  end_row : Int,
  end_col : Int,
  current_sheet : String,
) -> String raise @xlsx.XlsxError {
  let prefix = if sheet == current_sheet { "" } else { sheet + "!" }
  prefix + @xlsx.coordinates_to_cell_name(start_col, start_row, abs=true) + ":" + @xlsx.coordinates_to_cell_name(end_col, end_row, abs=true)
}

///|
pub fn rewrite_structured_refs(
  formula : StringView,
  current_sheet : String,
  current_row : Int,
  tables : Array[TableInfo],
) -> String raise @xlsx.XlsxError {
  let mut out = ""
  let mut last = 0
  for table in tables {
    let marker = table.name + "["
    let mut i = last
    while i < formula.length() {
      match find_sub(formula, marker[:], i) {
        Some(start) => {
          let content_start = start + marker.length()
          match find_sub(formula, "]", content_start) {
            Some(end) => {
              let content = formula[content_start:end].to_owned()
              let mut column = content
              let mut at_row = false
              let mut all_rows = false
              let mut headers = false
              let mut totals = false
              if column.has_prefix("@") {
                at_row = true
                column = column[1:].to_owned()
              } else if column == "#All" {
                all_rows = true
              } else if column == "#Headers" {
                headers = true
              } else if column == "#Totals" {
                totals = true
              } else if column.has_prefix("[#Data],[") && column.has_suffix("]") {
                column = column[9:column.length() - 1].to_owned()
              } else if column.has_prefix("#Data") {
                column = ""
              }
              let replacement = if all_rows || (column == "" && !headers && !totals) {
                Some(
                  absolute_range(
                    table.sheet,
                    table.start_row,
                    table.start_col,
                    table.end_row,
                    table.end_col,
                    current_sheet,
                  ),
                )
              } else {
                match table_column_index(table, column) {
                  Some(column_index) => {
                    let col = table.start_col + column_index - 1
                    if headers {
                      Some(absolute_range(table.sheet, table.start_row, col, table.start_row, col, current_sheet))
                    } else if totals {
                      Some(absolute_range(table.sheet, table.end_row, col, table.end_row, col, current_sheet))
                    } else if at_row {
                      Some(absolute_range(table.sheet, current_row, col, current_row, col, current_sheet))
                    } else {
                      Some(absolute_range(table.sheet, table.start_row + 1, col, table.end_row, col, current_sheet))
                    }
                  }
                  None => None
                }
              }
              match replacement {
                Some(range) => {
                  out = out + formula[last:start].to_owned() + range
                  last = end + 1
                }
                None => ()
              }
              i = end + 1
            }
            None => break
          }
        }
        None => break
      }
    }
  }
  out + formula[last:].to_owned()
}

///|
pub fn is_table_symbol(tables : Array[TableInfo], name : String) -> Bool {
  for table in tables {
    if table.name == name {
      return true
    }
    for column in table.columns {
      if column == name {
        return true
      }
    }
  }
  false
}

///|
pub(all) struct ExternalRef {
  workbook : String
  sheet : String
  row : Int
  col : Int
  start : Int
  end : Int
}

///|
pub fn external_refs(formula : StringView) -> Array[ExternalRef] {
  let result : Array[ExternalRef] = []
  let mut i = 0
  while i < formula.length() {
    if formula.get_char(i).unwrap_or('\u0000') == '[' {
      match find_sub(formula, "]", i + 1) {
        Some(bracket_end) => {
          let workbook = formula[i + 1:bracket_end].to_owned()
          let lower = workbook.to_lower()
          if lower.has_suffix(".xlsx") || lower.has_suffix(".xlsm") || lower.has_suffix(".xls") {
            let rest_start = bracket_end + 1
            let rest = formula[rest_start:]
            let refs = extract_refs(rest, "")
            match refs.cells {
              [cell, ..] => {
                let sheet = match cell.sheet {
                  Some(value) => value
                  None => ""
                }
                if sheet != "" {
                  result.push({
                    workbook,
                    sheet,
                    row: cell.row,
                    col: cell.col,
                    start: i,
                    end: rest_start + cell.end,
                  })
                }
              }
              _ => ()
            }
          }
          i = bracket_end + 1
        }
        None => break
      }
    } else {
      i = i + 1
    }
  }
  result
}

///|
fn rewrite_indirect(formula : StringView, current_sheet : String) -> String {
  let upper = formula.to_owned().to_upper()
  let mut out = ""
  let mut last = 0
  let mut search = 0
  while true {
    match find_sub(upper, "INDIRECT(", search) {
      Some(pos) => {
        let mut i = pos + 9
        while i < formula.length() && formula.get_char(i).unwrap_or('\u0000').is_ascii_whitespace() {
          i = i + 1
        }
        if i < formula.length() && formula.get_char(i).unwrap_or('\u0000') == '"' {
          let mut j = i + 1
          let mut content = ""
          while j < formula.length() {
            let c = formula.get_char(j).unwrap_or('\u0000')
            if c == '"' {
              if j + 1 < formula.length() && formula.get_char(j + 1).unwrap_or('\u0000') == '"' {
                content = content + "\""
                j = j + 2
              } else {
                break
              }
            } else {
              content = content + c.to_string()
              j = j + 1
            }
          }
          match find_sub(formula, ")", j + 1) {
            Some(end) => {
              let refs = extract_refs(content, current_sheet)
              if refs.cells.length() > 0 {
                out = out + formula[last:pos].to_owned() + content
                last = end + 1
              }
              search = end + 1
            }
            None => break
          }
        } else {
          search = pos + 9
        }
      }
      None => break
    }
  }
  out + formula[last:].to_owned()
}

///|
fn rewrite_offset(formula : StringView, current_sheet : String) -> String raise @xlsx.XlsxError {
  let upper = formula.to_owned().to_upper()
  let mut out = ""
  let mut last = 0
  let mut search = 0
  while true {
    match find_sub(upper, "OFFSET(", search) {
      Some(pos) => {
        match find_sub(formula, ")", pos + 7) {
          Some(end) => {
            let args = formula[pos + 7:end]
            let commas : Array[Int] = []
            let mut i = 0
            while i < args.length() {
              if args.get_char(i).unwrap_or('\u0000') == ',' {
                commas.push(i)
              }
              i = i + 1
            }
            let replacement = if commas.length() >= 2 {
              let base_text = args[:commas[0]]
              let rest = args[commas[1] + 1:]
              let base_refs = extract_refs(base_text, current_sheet)
              let rows = parse_signed_int(args, commas[0] + 1)
              let cols = parse_signed_int(rest, 0)
              match (base_refs.cells, rows, cols) {
                ([base, ..], Some((row_delta, _)), Some((col_delta, _))) => {
                  let row = base.row + row_delta
                  let col = base.col + col_delta
                  if row > 0 && col > 0 {
                    let cell = @xlsx.coordinates_to_cell_name(col, row)
                    match base.sheet {
                      Some(sheet) => Some(sheet + "!" + cell)
                      None => Some(cell)
                    }
                  } else {
                    None
                  }
                }
                _ => None
              }
            } else {
              None
            }
            match replacement {
              Some(value) => {
                out = out + formula[last:pos].to_owned() + value
                last = end + 1
              }
              None => ()
            }
            search = end + 1
          }
          None => break
        }
      }
      None => break
    }
  }
  out + formula[last:].to_owned()
}

///|
pub fn rewrite_dynamic_refs(
  formula : StringView,
  current_sheet : String,
  _current_row : Int,
) -> String raise @xlsx.XlsxError {
  let indirect = rewrite_indirect(formula, current_sheet)
  rewrite_offset(indirect, current_sheet)
}

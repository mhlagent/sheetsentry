///|
pub(all) struct CellRef {
  start : Int
  end : Int
  sheet : String?
  row : Int
  col : Int
  end_row : Int
  end_col : Int
  abs_row : Bool
  abs_col : Bool
}

///|
pub(all) struct FormulaRefs {
  cells : Array[CellRef]
  names : Array[String]
  dynamic : Bool
}

///|
fn is_ident_start(c : Char) -> Bool {
  c.is_ascii_alphabetic() || c == '_'
}

///|
fn is_ident_char(c : Char) -> Bool {
  c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '_' || c == '.'
}

///|
fn digits_to_int(chars : StringView) -> Int {
  let mut value = 0
  for i in 0..<chars.length() {
    value = value * 10 + (chars.get_char(i).unwrap_or('0').to_int() - '0'.to_int())
  }
  value
}

///|
fn column_number(letters : StringView) -> Int {
  let mut value = 0
  for i in 0..<letters.length() {
    let c = letters.get_char(i).unwrap_or('\u0000').to_ascii_uppercase()
    value = value * 26 + (c.to_int() - 'A'.to_int() + 1)
  }
  value
}

///|
fn parse_cell_at(
  s : StringView,
  start : Int,
  current_sheet : String,
) -> CellRef? {
  let mut i = start
  let abs_col = i < s.length() && s.get_char(i).unwrap_or('\u0000') == '$'
  if abs_col {
    i = i + 1
  }
  let col_start = i
  while i < s.length() && s.get_char(i).unwrap_or('\u0000').is_ascii_alphabetic() {
    i = i + 1
  }
  if i == col_start {
    return None
  }
  let col = column_number(s[col_start:i])
  if col < 1 || col > 16384 {
    return None
  }
  let abs_row = i < s.length() && s.get_char(i).unwrap_or('\u0000') == '$'
  if abs_row {
    i = i + 1
  }
  let row_start = i
  while i < s.length() && s.get_char(i).unwrap_or('\u0000').is_ascii_digit() {
    i = i + 1
  }
  if i == row_start {
    return None
  }
  let row = digits_to_int(s[row_start:i])
  if row < 1 || row > 1048576 {
    return None
  }
  let mut sheet : String? = None
  if start > 0 && s.get_char(start - 1).unwrap_or('\u0000') == '!' {
    let mut j = start - 1
    if j > 0 && s.get_char(j - 1).unwrap_or('\u0000') == '\'' {
      let mut k = j - 2
      while k >= 0 && s.get_char(k).unwrap_or('\u0000') != '\'' {
        k = k - 1
      }
      if k >= 0 {
        sheet = Some(s[k + 1:j - 1].to_owned())
      }
    } else {
      while j > 0 && (is_ident_char(s.get_char(j - 1).unwrap_or('\u0000'))) {
        j = j - 1
      }
      if j < start - 1 {
        sheet = Some(s[j:start - 1].to_owned())
      }
    }
  }
  ignore(current_sheet)
  Some({
    start,
    end: i,
    sheet,
    row,
    col,
    end_row: row,
    end_col: col,
    abs_row,
    abs_col,
  })
}

///|
fn skip_string(s : StringView, start : Int) -> Int {
  let mut i = start + 1
  while i < s.length() {
    if s.get_char(i).unwrap_or('\u0000') == '"' {
      if i + 1 < s.length() && s.get_char(i + 1).unwrap_or('\u0000') == '"' {
        i = i + 2
      } else {
        return i + 1
      }
    } else {
      i = i + 1
    }
  }
  i
}

///|
pub fn extract_refs(formula : StringView, current_sheet : StringView) -> FormulaRefs {
  let cells : Array[CellRef] = []
  let names : Array[String] = []
  let mut dynamic = false
  let mut i = 0
  while i < formula.length() {
    let c = formula.get_char(i).unwrap_or('\u0000')
    if c == '"' {
      i = skip_string(formula, i)
      continue
    }
    if c == '#' {
      i = i + 1
      while i < formula.length() {
        let d = formula.get_char(i).unwrap_or('\u0000')
        if d == '!' || d == '?' || d.is_ascii_whitespace() || d == ')' || d == ',' || d == '+' || d == '-' || d == '*' || d == '/' || d == '^' || d == '&' || d == '<' || d == '>' || d == '=' {
          break
        }
        i = i + 1
      }
      continue
    }
    if c == '$' || c.is_ascii_alphabetic() {
      let cell = parse_cell_at(formula, i, current_sheet.to_owned())
      match cell {
        Some(first) => {
          let mut last = first
          let mut next = first.end
          if next < formula.length() && formula.get_char(next).unwrap_or('\u0000') == ':' {
            match parse_cell_at(formula, next + 1, current_sheet.to_owned()) {
              Some(second) => {
                let merged_sheet = match first.sheet {
                  Some(name) => Some(name)
                  None => second.sheet
                }
                last = {
                  sheet: merged_sheet,
                  row: first.row,
                  col: first.col,
                  end_row: second.row,
                  end_col: second.col,
                  abs_row: first.abs_row,
                  abs_col: first.abs_col,
                  start: first.start,
                  end: second.end,
                }
                next = second.end
              }
              None => ()
            }
          }
          cells.push(last)
          i = next
          continue
        }
        None => {
          if is_ident_start(c) {
            let mut j = i + 1
            while j < formula.length() && is_ident_char(formula.get_char(j).unwrap_or('\u0000')) {
              j = j + 1
            }
            let name = formula[i:j].to_owned()
            if j < formula.length() && formula.get_char(j).unwrap_or('\u0000') == '(' {
              if name.to_upper() == "INDIRECT" || name.to_upper() == "OFFSET" {
                dynamic = true
              }
            } else if j < formula.length() && formula.get_char(j).unwrap_or('\u0000') == '!' {
              // sheet prefix; the cell parser handles it
            } else {
              let mut found = false
              for existing in names {
                if existing == name {
                  found = true
                }
              }
              if !found {
                names.push(name)
              }
            }
            i = j
            continue
          }
        }
      }
    }
    i = i + 1
  }
  { cells, names, dynamic }
}

///|
pub fn function_names(formula : StringView) -> Array[String] {
  let result : Array[String] = []
  let mut i = 0
  while i < formula.length() {
    let c = formula.get_char(i).unwrap_or('\u0000')
    if c == '"' {
      i = skip_string(formula, i)
      continue
    }
    if is_ident_start(c) {
      let start = i
      let mut j = i + 1
      while j < formula.length() && is_ident_char(formula.get_char(j).unwrap_or('\u0000')) {
        j = j + 1
      }
      if j < formula.length() && formula.get_char(j).unwrap_or('\u0000') == '(' {
        let name = formula[start:j].to_owned().to_upper()
        let mut found = false
        for existing in result {
          if existing == name {
            found = true
          }
        }
        if !found {
          result.push(name)
        }
      }
      i = j
      continue
    }
    i = i + 1
  }
  result
}

///|
fn rel_ref(value : Int, base : Int, absolute : Bool) -> String {
  if absolute {
    value.to_string()
  } else {
    "[\{(value - base)}]"
  }
}

///|
pub fn normalize_formula(
  formula : StringView,
  current_sheet : StringView,
  row : Int,
  col : Int,
) -> String {
  let refs = extract_refs(formula, current_sheet)
  let mut out = ""
  let mut last = 0
  for r in refs.cells {
    if r.start < last {
      continue
    }
    out = out + formula[last:r.start].to_owned()
    out = out + "R" + rel_ref(r.row, row, r.abs_row) + "C" + rel_ref(r.col, col, r.abs_col)
    if r.end_row != r.row || r.end_col != r.col {
      out = out + ":R" + rel_ref(r.end_row, row, false) + "C" + rel_ref(r.end_col, col, false)
    }
    last = r.end
  }
  out + formula[last:].to_owned()
}

///|
pub fn numeric_literals(formula : StringView) -> Array[String] {
  let result : Array[String] = []
  let refs = extract_refs(formula, "")
  let mut i = 0
  while i < formula.length() {
    let c = formula.get_char(i).unwrap_or('\u0000')
    if c == '"' {
      i = skip_string(formula, i)
      continue
    }
    let mut in_ref = false
    for r in refs.cells {
      if i >= r.start && i < r.end {
        in_ref = true
      }
    }
    if in_ref {
      i = i + 1
      continue
    }
    let start = i
    let mut preceded_by_identifier = false
    if c != '-' && start > 0 {
      let prev = formula.get_char(start - 1).unwrap_or('\u0000')
      if prev.is_ascii_alphabetic() || prev.is_ascii_digit() || prev == '_' || prev == '.' {
        preceded_by_identifier = true
      }
    }
    if preceded_by_identifier {
      i = i + 1
      continue
    }
    if c == '-' && i + 1 < formula.length() && formula.get_char(i + 1).unwrap_or('\u0000').is_ascii_digit() {
      i = i + 1
    }
    if i < formula.length() && formula.get_char(i).unwrap_or('\u0000').is_ascii_digit() {
      while i < formula.length() && (formula.get_char(i).unwrap_or('\u0000').is_ascii_digit() || formula.get_char(i).unwrap_or('\u0000') == '.') {
        i = i + 1
      }
      if i < formula.length() && (formula.get_char(i).unwrap_or('\u0000') == 'E' || formula.get_char(i).unwrap_or('\u0000') == 'e') {
        i = i + 1
        if i < formula.length() && (formula.get_char(i).unwrap_or('\u0000') == '+' || formula.get_char(i).unwrap_or('\u0000') == '-') {
          i = i + 1
        }
        while i < formula.length() && formula.get_char(i).unwrap_or('\u0000').is_ascii_digit() {
          i = i + 1
        }
      }
      result.push(formula[start:i].to_owned())
      continue
    }
    i = i + 1
  }
  result
}

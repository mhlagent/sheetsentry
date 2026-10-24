///|
pub(all) enum Severity {
  High
  Medium
  Low
}

///|
pub fn tool_version() -> String {
  "0.5.0"
}

///|
pub fn Severity::label(self : Severity) -> String {
  match self {
    High => "high"
    Medium => "medium"
    Low => "low"
  }
}

///|
pub(all) struct Finding {
  rule_id : String
  severity : Severity
  sheet : String
  cell : String
  formula : String?
  message : String
  related : Array[String]
}

///|
pub(all) struct AuditReport {
  file : String
  sheets : Array[String]
  formula_cells : Int
  findings : Array[Finding]
  suppressed : Array[Finding]
}

///|
fn make_finding(
  rule_id : String,
  severity : Severity,
  sheet : String,
  cell : String,
  formula : String?,
  message : String,
  related : Array[String],
) -> Finding {
  { rule_id, severity, sheet, cell, formula, message, related }
}

///|
fn node_key(sheet : String, row : Int, col : Int) -> String raise @xlsx.XlsxError {
  "\{sheet}!\{@xlsx.coordinates_to_cell_name(col, row)}"
}

///|
pub(all) struct DependencyGraph {
  edges : Map[String, Array[String]]
  reverse : Map[String, Array[String]]
}

///|
fn add_edge(graph : DependencyGraph, from : String, to : String) -> Unit {
  let outgoing = graph.edges.get_or_init(from, fn() { [] })
  let mut found = false
  for item in outgoing {
    if item == to {
      found = true
    }
  }
  if !found {
    outgoing.push(to)
  }
  graph.edges.set(from, outgoing)
  let incoming = graph.reverse.get_or_init(to, fn() { [] })
  let mut found_rev = false
  for item in incoming {
    if item == from {
      found_rev = true
    }
  }
  if !found_rev {
    incoming.push(from)
  }
  graph.reverse.set(to, incoming)
}

///|
pub fn DependencyGraph::new() -> DependencyGraph {
  { edges: Map([]), reverse: Map([]) }
}

///|
fn is_error_text(value : String) -> Bool {
  value.has_prefix("#")
}

///|
fn is_volatile(name : String) -> Bool {
  match name {
    "NOW" | "TODAY" | "RAND" | "RANDBETWEEN" | "OFFSET" | "INDIRECT" | "INFO" | "CELL" => true
    _ => false
  }
}

///|
fn numeric_constant_allowed(value : String) -> Bool {
  match value {
    "0" | "1" | "-1" | "100" => true
    _ => false
  }
}

///|
fn has_constant_literal(formula : String) -> String? {
  for value in numeric_literals(formula) {
    if !numeric_constant_allowed(value) {
      return Some(value)
    }
  }
  None
}

///|
fn dfs_cycle_to(
  start : String,
  node : String,
  graph : DependencyGraph,
  colors : Map[String, Int],
  stack : Array[String],
  found : Array[Array[String]],
) -> Bool {
  colors.set(node, 1)
  stack.push(node)
  let neighbors = graph.edges.get_or_default(node, [])
  for next in neighbors {
    if next == start {
      let cycle : Array[String] = []
      for item in stack {
        cycle.push(item)
      }
      cycle.push(start)
      found.push(cycle)
      return true
    }
    if colors.get_or_default(next, 0) == 0 {
      if dfs_cycle_to(start, next, graph, colors, stack, found) {
        return true
      }
    }
  }
  ignore(stack.pop())
  colors.set(node, 2)
  false
}

///|
fn find_cycle_from(graph : DependencyGraph, start : String) -> Array[String]? {
  let colors : Map[String, Int] = Map([])
  let stack : Array[String] = []
  let found : Array[Array[String]] = []
  ignore(dfs_cycle_to(start, start, graph, colors, stack, found))
  if found.length() > 0 {
    Some(found[0])
  } else {
    None
  }
}

///|
fn cycle_related(path : Array[String], start : String) -> Array[String] {
  let result : Array[String] = []
  for item in path {
    if item != start {
      result.push(item)
    }
  }
  result
}

///|
fn has_whole_axis_ref(formula : StringView) -> Bool {
  let mut i = 0
  while i < formula.length() {
    let c = formula.get_char(i).unwrap_or('\u0000')
    if c == '$' || c.is_ascii_alphabetic() {
      let start = i
      if c == '$' {
        i = i + 1
      }
      while i < formula.length() && formula.get_char(i).unwrap_or('\u0000').is_ascii_alphabetic() {
        i = i + 1
      }
      if i > start && i < formula.length() && formula.get_char(i).unwrap_or('\u0000') == ':' {
        let mut j = i + 1
        if j < formula.length() && formula.get_char(j).unwrap_or('\u0000') == '$' {
          j = j + 1
        }
        let letter_start = j
        while j < formula.length() && formula.get_char(j).unwrap_or('\u0000').is_ascii_alphabetic() {
          j = j + 1
        }
        if j > letter_start && (j == formula.length() || !formula.get_char(j).unwrap_or('\u0000').is_ascii_digit()) {
          return true
        }
      }
    } else if c == '$' || c.is_ascii_digit() {
      let start = i
      if c == '$' {
        i = i + 1
      }
      while i < formula.length() && formula.get_char(i).unwrap_or('\u0000').is_ascii_digit() {
        i = i + 1
      }
      if i > start && i < formula.length() && formula.get_char(i).unwrap_or('\u0000') == ':' {
        let mut j = i + 1
        if j < formula.length() && formula.get_char(j).unwrap_or('\u0000') == '$' {
          j = j + 1
        }
        let digit_start = j
        while j < formula.length() && formula.get_char(j).unwrap_or('\u0000').is_ascii_digit() {
          j = j + 1
        }
        if j > digit_start {
          return true
        }
      }
    }
    i = i + 1
  }
  false
}

///|
fn external_link(formula : StringView) -> String? {
  let mut i = 0
  while i < formula.length() {
    let c = formula.get_char(i).unwrap_or('\u0000')
    if c == '[' {
      let mut j = i + 1
      while j < formula.length() && formula.get_char(j).unwrap_or('\u0000') != ']' {
        j = j + 1
      }
      if j < formula.length() {
        let name = formula[i + 1:j].to_owned()
        let lower = name.to_lower()
        if lower.has_suffix(".xlsx") || lower.has_suffix(".xlsm") || lower.has_suffix(".xls") {
          return Some(name)
        }
      }
    }
    i = i + 1
  }
  None
}

///|
fn collect_sheet_cells(
  workbook : @xlsx.Workbook,
  sheet_name : String,
  graph : DependencyGraph,
  formula_cells : Int,
  findings : Array[Finding],
) -> Int raise @xlsx.XlsxError {
  let sheet = workbook.sheet(sheet_name).unwrap()
  let hidden_sheet = !workbook.sheet_visible(sheet_name)
  let max_row = sheet.max_row()
  let max_col = sheet.max_col()
  let mut count = formula_cells
  for row in 1..=max_row {
    let hidden_row = !sheet.row_visible(row)
    for col in 1..=max_col {
      let cell = @xlsx.coordinates_to_cell_name(col, row)
      let formula = sheet.get_cell_formula(cell)
      let raw = sheet.get_cell_rc(row, col)
      match formula {
        Some(text) => {
          count = count + 1
          let key = node_key(sheet_name, row, col)
          ignore(graph.edges.get_or_init(key, fn() { [] }))
          let refs = extract_refs(text, sheet_name)
          for r in refs.cells {
            let target_sheet = match r.sheet {
              Some(name) => name
              None => sheet_name
            }
            let max_cells = 500
            let row_lo = if r.row < r.end_row { r.row } else { r.end_row }
            let row_hi = if r.row < r.end_row { r.end_row } else { r.row }
            let col_lo = if r.col < r.end_col { r.col } else { r.end_col }
            let col_hi = if r.col < r.end_col { r.end_col } else { r.col }
            let mut added = 0
            for rr in row_lo..=row_hi {
              for cc in col_lo..=col_hi {
                if added < max_cells {
                  add_edge(graph, key, node_key(target_sheet, rr, cc))
                  added = added + 1
                }
              }
            }
          }
          if refs.dynamic && dynamic_refs(text, sheet_name, row, workbook).length() == 0 {
            findings.push(
              make_finding(
                "SS007",
                Low,
                sheet_name,
                cell,
                Some(text),
                "Formula contains a dynamic reference (INDIRECT/OFFSET); dependency tracing is incomplete.",
                [],
              ),
            )
          }
          match has_constant_literal(text) {
            Some(value) => {
              findings.push(
                make_finding(
                  "SS003",
                  Medium,
                  sheet_name,
                  cell,
                  Some(text),
                  "Formula embeds numeric constant \{value}; prefer a named input cell.",
                  [],
                ),
              )
            }
            None => ()
          }
          for name in function_names(text) {
            if is_volatile(name) {
              findings.push(
                make_finding(
                  "SS004",
                  Low,
                  sheet_name,
                  cell,
                  Some(text),
                  "Formula uses volatile function \{name}().",
                  [],
                ),
              )
            }
          }
          match external_link(text) {
            Some(workbook) => {
              findings.push(
                make_finding(
                  "SS008",
                  Medium,
                  sheet_name,
                  cell,
                  Some(text),
                  "Formula references external workbook \{workbook}.",
                  [],
                ),
              )
            }
            None => ()
          }
          if has_whole_axis_ref(text) {
            findings.push(
              make_finding(
                "SS009",
                Low,
                sheet_name,
                cell,
                Some(text),
                "Formula uses a whole-column or whole-row reference; this can be expensive and ambiguous.",
                [],
              ),
            )
          }
          let cached = match sheet.get_cell_formula_info_rc(row, col) {
            Some(info) => info.cached_value_present
            None => false
          }
          if !cached {
            findings.push(
              make_finding(
                "SS010",
                Low,
                sheet_name,
                cell,
                Some(text),
                "Formula has no cached result; some readers may show a blank until recalculation.",
                [],
              ),
            )
          }
          if hidden_sheet || hidden_row {
            findings.push(
              make_finding(
                "SS005",
                Medium,
                sheet_name,
                cell,
                Some(text),
                if hidden_sheet {
                  "Formula lives on a hidden sheet."
                } else {
                  "Formula lives on a hidden row."
                },
                [],
              ),
            )
          }
        }
        None => ()
      }
      match raw {
        Some(value) =>
          if is_error_text(value) {
            findings.push(
              make_finding(
                "SS001",
                High,
                sheet_name,
                cell,
                formula,
                "Cell contains error value \{value}.",
                [],
              ),
            )
          }
        None => ()
      }
    }
  }
  count
}

///|
fn check_formula_line(
  sheet : String,
  kind : String,
  position : Int,
  list : Array[(Int, String, String)],
  findings : Array[Finding],
) -> Unit {
  if list.length() >= 3 {
    list.sort_by(fn(a, b) { a.0 - b.0 })
    let counts : Map[String, Int] = Map([])
    for item in list {
      let normalized = item.2
      counts.set(normalized, counts.get_or_default(normalized, 0) + 1)
    }
    let mut majority = false
    for _, count in counts {
      if count >= 2 {
        majority = true
      }
    }
    if majority {
      for item in list {
        let (_, cell, normalized) = item
        if counts.get_or_default(normalized, 0) == 1 {
          findings.push(
            make_finding(
              "SS002",
              Medium,
              sheet,
              cell,
              None,
              "Formula differs from the dominant pattern in \{kind} \{position}.",
              [],
            ),
          )
        }
      }
    }
  }
}

///|
fn detect_formula_inconsistency(
  sheet : String,
  formulas : Array[(Int, Int, String, String)],
  findings : Array[Finding],
) -> Unit {
  let rows : Map[Int, Array[(Int, String, String)]] = Map([])
  let cols : Map[Int, Array[(Int, String, String)]] = Map([])
  for item in formulas {
    let (row, col, cell, normalized) = item
    let row_list = rows.get_or_init(row, fn() { [] })
    row_list.push((col, cell, normalized))
    rows.set(row, row_list)
    let col_list = cols.get_or_init(col, fn() { [] })
    col_list.push((row, cell, normalized))
    cols.set(col, col_list)
  }
  for row, list in rows {
    check_formula_line(sheet, "row", row, list, findings)
  }
  for col, list in cols {
    check_formula_line(sheet, "column", col, list, findings)
  }
}

///|
pub fn audit_bytes(bytes : Bytes, file : String) -> AuditReport raise @xlsx.XlsxError {
  let workbook = @xlsx.read(bytes)
  let sheets = workbook.get_sheet_list()
  let graph = DependencyGraph::new()
  let findings : Array[Finding] = []
  let mut formula_cells = 0
  let normalized_formulas : Array[(Int, Int, String, String, String)] = []
  for name in sheets {
    formula_cells = collect_sheet_cells(workbook, name, graph, formula_cells, findings)
    guard workbook.sheet(name) is Some(sheet) else { continue }
    let max_row = sheet.max_row()
    let max_col = sheet.max_col()
    for row in 1..=max_row {
      for col in 1..=max_col {
        let cell = @xlsx.coordinates_to_cell_name(col, row)
        match sheet.get_cell_formula(cell) {
          Some(text) => {
            let normalized = normalize_formula(text, name, row, col)
            normalized_formulas.push((row, col, name, cell, normalized))
          }
          None => ()
        }
      }
    }
  }
  // Group normalized formulas by sheet for row consistency checks.
  let by_sheet : Map[String, Array[(Int, Int, String, String)]] = Map([])
  for item in normalized_formulas {
    let (row, col, sheet, cell, normalized) = item
    let list = by_sheet.get_or_init(sheet, fn() { [] })
    list.push((row, col, cell, normalized))
    by_sheet.set(sheet, list)
  }
  for sheet, list in by_sheet {
    detect_formula_inconsistency(sheet, list, findings)
  }
  for key, _ in graph.edges {
    match find_cycle_from(graph, key) {
      Some(path) => {
        let cell = match key.split("!").collect() {
          [_, c] => c.to_owned()
          _ => key
        }
        findings.push(
          make_finding(
            "SS006",
            High,
            key.split("!").collect()[0].to_owned(),
            cell,
            None,
            "Circular reference detected.",
            cycle_related(path, key),
          ),
        )
      }
      None => ()
    }
  }
  findings.sort_by(fn(a, b) {
    let ar = severity_rank(a.severity)
    let br = severity_rank(b.severity)
    if ar != br {
      ar - br
    } else if a.sheet != b.sheet {
      a.sheet.compare(b.sheet)
    } else {
      a.cell.compare(b.cell)
    }
  })
  { file, sheets, formula_cells, findings, suppressed: [] }
}

///|
pub fn count_severity_public(report : AuditReport, severity : Severity) -> Int {
  let mut count = 0
  for finding in report.findings {
    let same = match (finding.severity, severity) {
      (High, High) => true
      (Medium, Medium) => true
      (Low, Low) => true
      _ => false
    }
    if same {
      count = count + 1
    }
  }
  count
}

///|
pub fn should_fail(report : AuditReport, threshold : String) -> Bool {
  match threshold {
    "high" => count_severity_public(report, High) > 0
    "medium" => count_severity_public(report, High) + count_severity_public(report, Medium) > 0
    "low" => report.findings.length() > 0
    _ => false
  }
}


///|
pub fn severity_rank(severity : Severity) -> Int {
  match severity {
    High => 0
    Medium => 1
    Low => 2
  }
}

///|
pub fn finding_fingerprint(finding : Finding) -> String {
  "\{finding.rule_id}|\{finding.sheet}|\{finding.cell}"
}

///|
pub fn apply_baseline(report : AuditReport, fingerprints : Array[String]) -> AuditReport {
  let active : Array[Finding] = []
  let suppressed : Array[Finding] = []
  for finding in report.findings {
    let fingerprint = finding_fingerprint(finding)
    let mut matched = false
    for known in fingerprints {
      if known == fingerprint {
        matched = true
      }
    }
    if matched {
      suppressed.push(finding)
    } else {
      active.push(finding)
    }
  }
  {
    file: report.file,
    sheets: report.sheets,
    formula_cells: report.formula_cells,
    findings: active,
    suppressed,
  }
}

///|
pub fn all_fingerprints(report : AuditReport) -> Array[String] {
  let result : Array[String] = []
  for finding in report.findings {
    result.push(finding_fingerprint(finding))
  }
  for finding in report.suppressed {
    result.push(finding_fingerprint(finding))
  }
  result
}

///|
fn severity_allowed(severity : Severity, minimum : String) -> Bool {
  match minimum {
    "high" =>
      match severity {
        High => true
        _ => false
      }
    "medium" =>
      match severity {
        High => true
        Medium => true
        _ => false
      }
    _ => true
  }
}

///|
pub fn filter_report(
  report : AuditReport,
  min_severity : String,
  disabled_rules : Array[String],
) -> AuditReport {
  let active : Array[Finding] = []
  let suppressed = report.suppressed
  for finding in report.findings {
    let mut disabled = false
    for rule_id in disabled_rules {
      if finding.rule_id == rule_id {
        disabled = true
      }
    }
    if severity_allowed(finding.severity, min_severity) && !disabled {
      active.push(finding)
    } else {
      suppressed.push(finding)
    }
  }
  {
    file: report.file,
    sheets: report.sheets,
    formula_cells: report.formula_cells,
    findings: active,
    suppressed,
  }
}

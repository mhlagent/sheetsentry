///|
pub(all) struct AuditConfig {
  min_severity : String
  disabled_rules : Array[String]
  ignore_cells : Array[String]
  fail_on : String
}

///|
pub fn default_config() -> AuditConfig {
  { min_severity: "low", disabled_rules: [], ignore_cells: [], fail_on: "" }
}

///|
fn json_string_array(map : Map[String, Json], key : String) -> Array[String] {
  let result : Array[String] = []
  match map.get(key) {
    Some(Array(items)) =>
      for item in items {
        match item {
          String(value) => result.push(value)
          _ => ()
        }
      }
    _ => ()
  }
  result
}

///|
fn json_string(map : Map[String, Json], key : String, fallback : String) -> String {
  match map.get(key) {
    Some(String(value)) => value
    _ => fallback
  }
}

///|
pub fn parse_config(text : String) -> AuditConfig raise @json.ParseError {
  let value = @json.parse(text)
  match value {
    Object(map) => {
      min_severity: json_string(map, "min_severity", "low"),
      disabled_rules: json_string_array(map, "disabled_rules"),
      ignore_cells: json_string_array(map, "ignore_cells"),
      fail_on: json_string(map, "fail_on", ""),
    }
    _ => default_config()
  }
}

///|
pub fn apply_config(report : AuditReport, config : AuditConfig) -> AuditReport {
  let filtered = filter_report(report, config.min_severity, config.disabled_rules)
  let active : Array[Finding] = []
  let suppressed = filtered.suppressed
  for finding in filtered.findings {
    let cell = "\{finding.sheet}!\{finding.cell}"
    let mut ignored = false
    for pattern in config.ignore_cells {
      if pattern == cell {
        ignored = true
      }
    }
    if ignored {
      suppressed.push(finding)
    } else {
      active.push(finding)
    }
  }
  {
    file: filtered.file,
    sheets: filtered.sheets,
    formula_cells: filtered.formula_cells,
    findings: active,
    suppressed,
  }
}

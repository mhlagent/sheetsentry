///|
fn json_escape(s : String) -> String {
  let mut out = ""
  for c in s {
    match c {
      '"' => out = out + "\\\""
      '\\' => out = out + "\\\\"
      '\n' => out = out + "\\n"
      '\r' => out = out + "\\r"
      '\t' => out = out + "\\t"
      _ => out = out + c.to_string()
    }
  }
  out
}

///|
fn html_escape(s : String) -> String {
  let mut out = ""
  for c in s {
    match c {
      '&' => out = out + "&amp;"
      '<' => out = out + "&lt;"
      '>' => out = out + "&gt;"
      '"' => out = out + "&quot;"
      _ => out = out + c.to_string()
    }
  }
  out
}

///|
fn finding_json(f : Finding) -> String {
  let formula = match f.formula {
    Some(text) => "\"formula\":\"\{json_escape(text)}\""
    None => "\"formula\":null"
  }
  let related = "[" + f.related.map(fn(x) { "\"" + json_escape(x) + "\"" }).join(",") + "]"
  "{\"rule_id\":\"\{f.rule_id}\",\"severity\":\"\{f.severity.label()}\",\"sheet\":\"\{json_escape(f.sheet)}\",\"cell\":\"\{json_escape(f.cell)}\",\{formula},\"message\":\"\{json_escape(f.message)}\",\"related\":\{related}}"
}

///|
pub fn to_json(report : AuditReport) -> String {
  let findings = "[" + report.findings.map(finding_json).join(",") + "]"
  let suppressed = "[" + report.suppressed.map(finding_json).join(",") + "]"
  let sheets = "[" + report.sheets.map(fn(x) { "\"" + json_escape(x) + "\"" }).join(",") + "]"
  "{\"tool\":\"sheetsentry\",\"version\":\"\{tool_version()}\",\"file\":\"\{json_escape(report.file)}\",\"sheets\":\{sheets},\"formula_cells\":\{report.formula_cells},\"findings\":\{findings},\"suppressed\":\{suppressed}}"
}

///|
fn sarif_level(severity : Severity) -> String {
  match severity {
    High => "error"
    Medium => "warning"
    Low => "note"
  }
}

///|
fn sarif_result(f : Finding) -> String {
  let related = match f.related {
    [] => ""
    list => {
      let refs = "[" + list.map(fn(x) { "{\"logicalLocations\":[{\"fullyQualifiedName\":\"" + json_escape(x) + "\"}]}" }).join(",") + "]"
      ",\"relatedLocations\":\{refs}"
    }
  }
  "{\"ruleId\":\"\{f.rule_id}\",\"level\":\"\{sarif_level(f.severity)}\",\"message\":{\"text\":\"\{json_escape(f.message)}\"},\"locations\":[{\"logicalLocations\":[{\"name\":\"\{json_escape(f.sheet)}!\{json_escape(f.cell)}\",\"fullyQualifiedName\":\"\{json_escape(f.sheet)}!\{json_escape(f.cell)}\",\"kind\":\"member\"}]}]\{related}}"
}

///|
pub fn to_sarif(report : AuditReport) -> String {
  let results = "[" + report.findings.map(sarif_result).join(",") + "]"
  let rules = "[{\"id\":\"SS001\",\"name\":\"ErrorValue\",\"shortDescription\":{\"text\":\"Cell contains an Excel error value\"}},{\"id\":\"SS002\",\"name\":\"FormulaInconsistency\",\"shortDescription\":{\"text\":\"Formula differs from its row or column pattern\"}},{\"id\":\"SS003\",\"name\":\"HardcodedConstant\",\"shortDescription\":{\"text\":\"Formula embeds a numeric constant\"}},{\"id\":\"SS004\",\"name\":\"VolatileFunction\",\"shortDescription\":{\"text\":\"Formula uses a volatile function\"}},{\"id\":\"SS005\",\"name\":\"HiddenFormula\",\"shortDescription\":{\"text\":\"Formula lives on a hidden sheet or row\"}},{\"id\":\"SS006\",\"name\":\"CircularReference\",\"shortDescription\":{\"text\":\"Custom dependency cycle\"}},{\"id\":\"SS007\",\"name\":\"DynamicReference\",\"shortDescription\":{\"text\":\"Formula uses INDIRECT/OFFSET\"}},{\"id\":\"SS008\",\"name\":\"ExternalWorkbook\",\"shortDescription\":{\"text\":\"Formula references an external workbook\"}}]"
  "{\"$schema\":\"https://json.schemastore.org/sarif-2.1.0.json\",\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"SheetSentry\",\"version\":\"\{tool_version()}\",\"informationUri\":\"https://github.com/mhlagent/sheetsentry\",\"rules\":\{rules}}},\"results\":\{results}}]}"
}

///|
fn severity_class(severity : Severity) -> String {
  match severity {
    High => "high"
    Medium => "medium"
    Low => "low"
  }
}

///|
fn same_severity(a : Severity, b : Severity) -> Bool {
  match (a, b) {
    (High, High) => true
    (Medium, Medium) => true
    (Low, Low) => true
    _ => false
  }
}

///|
fn count_severity(report : AuditReport, severity : Severity) -> Int {
  let mut count = 0
  for finding in report.findings {
    if same_severity(finding.severity, severity) {
      count = count + 1
    }
  }
  count
}

///|
pub fn to_html(report : AuditReport) -> String {
  let mut rows = ""
  for finding in report.findings {
    let formula = match finding.formula {
      Some(text) => html_escape(text)
      None => ""
    }
    let related = finding.related.map(fn(x) { html_escape(x) }).join(", ")
    rows = rows + "<tr class=\"\{severity_class(finding.severity)}\" data-severity=\"\{finding.severity.label()}\" data-rule=\"\{finding.rule_id}\" data-sheet=\"\{html_escape(finding.sheet)}\"><td>\{finding.rule_id}</td><td>\{finding.severity.label()}</td><td>\{html_escape(finding.sheet)}!\{html_escape(finding.cell)}</td><td>\{html_escape(finding.message)}</td><td class=\"formula\">\{formula}</td><td>\{related}</td></tr>"
  }
  let high = count_severity(report, High)
  let medium = count_severity(report, Medium)
  let low = count_severity(report, Low)
  let sheet_count = report.sheets.length()
  "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>SheetSentry report</title><style>body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;margin:32px;color:#1f2937;background:#f8fafc}h1{margin:0 0 6px}.meta{color:#64748b;margin-bottom:24px}.cards{display:flex;gap:12px;margin-bottom:24px}.card{background:white;border:1px solid #e2e8f0;border-radius:10px;padding:14px 18px;min-width:110px}.card b{display:block;font-size:24px}.high{border-left:4px solid #dc2626}.medium{border-left:4px solid #d97706}.low{border-left:4px solid #2563eb}table{width:100%;border-collapse:collapse;background:white;border:1px solid #e2e8f0;border-radius:10px;overflow:hidden}th,td{padding:10px 12px;border-bottom:1px solid #e2e8f0;text-align:left;vertical-align:top;font-size:13px}th{background:#f1f5f9}.formula{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;color:#334155}tr.high td:first-child{color:#dc2626;font-weight:700}tr.medium td:first-child{color:#d97706;font-weight:700}tr.low td:first-child{color:#2563eb;font-weight:700}.filters{display:flex;gap:10px;margin:0 0 16px;align-items:center}.filters select,.filters input{padding:8px 10px;border:1px solid #cbd5e1;border-radius:8px;background:white;font-size:13px}.filters input{min-width:260px}.filters span{color:#64748b;font-size:13px}</style></head><body><h1>SheetSentry report</h1><div class=\"meta\">\{html_escape(report.file)} · \{sheet_count} sheets · \{report.formula_cells} formula cells</div><div class=\"cards\"><div class=\"card\"><b>\{report.findings.length()}</b>findings</div><div class=\"card high\"><b>\{high}</b>high</div><div class=\"card medium\"><b>\{medium}</b>medium</div><div class=\"card low\"><b>\{low}</b>low</div></div><table><thead><tr><th>Rule</th><th>Severity</th><th>Cell</th><th>Message</th><th>Formula</th><th>Related</th></tr></thead><tbody>\{rows}</tbody></table><script>function filterRows(){const s=document.getElementById('sev').value,r=document.getElementById('rule').value,q=document.getElementById('q').value.toLowerCase();let n=0;document.querySelectorAll('tbody tr').forEach(t=>{const ok=(!s||t.dataset.severity===s)&&(!r||t.dataset.rule===r)&&(!q||t.textContent.toLowerCase().includes(q));t.style.display=ok?'':'none';if(ok)n++});document.getElementById('count').textContent=n+' shown'}filterRows()</script></body></html>"
}

///|
pub fn to_terminal(report : AuditReport) -> String {
  let mut out = "SheetSentry: \{report.file}\n"
  out = out + "  sheets: \{report.sheets.length()}  formula cells: \{report.formula_cells}  findings: \{report.findings.length()}\n"
  out = out + "  high: \{count_severity(report, High)}  medium: \{count_severity(report, Medium)}  low: \{count_severity(report, Low)}  suppressed: \{report.suppressed.length()}\n"
  for finding in report.findings {
    out = out + "  [\{finding.severity.label()}] \{finding.rule_id}  \{finding.sheet}!\{finding.cell}  \{finding.message}\n"
  }
  if report.findings.length() == 0 {
    out = out + "  No findings.\n"
  }
  out
}

///|
pub fn rule_catalog() -> String {
  "SS001  high    Excel error value\nSS002  medium  Formula differs from row/column pattern\nSS003  medium  Hardcoded numeric constant\nSS004  low     Volatile function\nSS005  medium  Formula lives on hidden sheet/row\nSS006  high    Circular reference\nSS007  low     Dynamic reference (INDIRECT/OFFSET)\nSS008  medium  External workbook reference"
}

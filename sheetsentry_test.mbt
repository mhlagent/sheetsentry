///|
test "summarize bad model" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let summary = @sheetsentry.summarize_bytes(bytes)
  assert_eq(summary.sheets.length(), 5)
  assert_eq(summary.sheets[0], "Inputs")
  assert_eq(summary.formula_cells, 15)
}

///|
fn has_rule(report : @sheetsentry.AuditReport, id : String) -> Bool {
  for finding in report.findings {
    if finding.rule_id == id {
      return true
    }
  }
  false
}

///|
test "audit bad model finds core rules" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let report = @sheetsentry.audit_bytes(bytes, "bad_model.xlsx")
  println("findings=\{report.findings.length()}")
  for finding in report.findings {
    println("\{finding.rule_id} \{finding.severity.label()} \{finding.sheet}!\{finding.cell} \{finding.message}")
  }
  assert_true(has_rule(report, "SS001"))
  assert_true(has_rule(report, "SS002"))
  assert_true(has_rule(report, "SS003"))
  assert_true(has_rule(report, "SS004"))
  assert_true(has_rule(report, "SS005"))
  assert_true(has_rule(report, "SS006"))
  assert_true(has_rule(report, "SS008"))
}

///|
test "audit clean model has no findings" {
  let bytes = @fs.read_file_to_bytes("fixtures/clean_model.xlsx")
  let report = @sheetsentry.audit_bytes(bytes, "clean_model.xlsx")
  println("clean findings=\{report.findings.length()}")
  for finding in report.findings {
    println("\{finding.rule_id} \{finding.sheet}!\{finding.cell} \{finding.message}")
  }
  assert_eq(report.findings.length(), 0)
}

///|
fn contains_node(nodes : Array[String], target : String) -> Bool {
  for node in nodes {
    if node == target {
      return true
    }
  }
  false
}

///|
test "report formats are generated" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let report = @sheetsentry.audit_bytes(bytes, "bad_model.xlsx")
  let json = @sheetsentry.to_json(report)
  let sarif = @sheetsentry.to_sarif(report)
  let html = @sheetsentry.to_html(report)
  assert_true(json.has_prefix("{\"tool\":\"sheetsentry\""))
  assert_true(sarif.has_prefix("{\"$schema\""))
  assert_true(html.has_prefix("<!doctype html>"))
}

///|
test "trace finds precedents" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let nodes = @sheetsentry.trace_bytes(bytes, "Summary!B3", "precedents", 1)
  assert_true(contains_node(nodes, "Opex!C2"))
  assert_true(contains_node(nodes, "Opex!C6"))
}

///|
test "fail thresholds" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let bad = @sheetsentry.audit_bytes(bytes, "bad_model.xlsx")
  assert_true(@sheetsentry.should_fail(bad, "high"))
  assert_true(@sheetsentry.should_fail(bad, "medium"))
  assert_true(@sheetsentry.should_fail(bad, "low"))
  let clean_bytes = @fs.read_file_to_bytes("fixtures/clean_model.xlsx")
  let clean = @sheetsentry.audit_bytes(clean_bytes, "clean_model.xlsx")
  assert_false(@sheetsentry.should_fail(clean, "low"))
}

///|
test "trace finds dependents" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let nodes = @sheetsentry.trace_bytes(bytes, "Opex!C2", "dependents", 1)
  assert_true(contains_node(nodes, "Summary!B3"))
}

///|
test "baseline suppresses known findings" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let report = @sheetsentry.audit_bytes(bytes, "bad_model.xlsx")
  let baseline = @sheetsentry.parse_baseline(@sheetsentry.baseline_json(report))
  let filtered = @sheetsentry.apply_baseline(report, baseline)
  assert_eq(filtered.findings.length(), 0)
  assert_eq(filtered.suppressed.length(), report.findings.length())
  assert_false(@sheetsentry.should_fail(filtered, "low"))
}

///|
test "graph export formats" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let graph = @sheetsentry.build_graph_bytes(bytes)
  let dot = @sheetsentry.graph_to_dot(graph)
  let mermaid = @sheetsentry.graph_to_mermaid(graph)
  assert_true(dot.has_prefix("digraph sheetsentry"))
  assert_true(mermaid.has_prefix("graph LR"))
}

///|
test "rule catalog lists all rules" {
  let catalog = @sheetsentry.rule_catalog()
  assert_true(catalog.contains("SS001"))
  assert_true(catalog.contains("SS008"))
}

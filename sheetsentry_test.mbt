///|
test "summarize bad model" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let summary = @sheetsentry.summarize_bytes(bytes)
  assert_eq(summary.sheets.length(), 5)
  assert_eq(summary.sheets[0], "Inputs")
  assert_eq(summary.formula_cells, 22)
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
  assert_true(has_rule(report, "SS009"))
  assert_true(has_rule(report, "SS010"))
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

///|
test "filter by severity and disabled rule" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let report = @sheetsentry.audit_bytes(bytes, "bad_model.xlsx")
  let high = @sheetsentry.filter_report(report, "high", [])
  for finding in high.findings {
    assert_eq(finding.severity.label(), "high")
  }
  let no_ss003 = @sheetsentry.filter_report(report, "low", ["SS003"])
  for finding in no_ss003.findings {
    assert_true(finding.rule_id != "SS003")
  }
}

///|
test "default config" {
  let config = @sheetsentry.default_config()
  assert_eq(config.min_severity, "low")
  assert_eq(config.disabled_rules.length(), 0)
  assert_eq(config.ignore_cells.length(), 0)
  assert_eq(config.fail_on, "")
}

///|
test "parse full config" {
  let config = @sheetsentry.parse_config("{\"min_severity\":\"high\",\"disabled_rules\":[\"SS003\",\"SS004\"],\"ignore_cells\":[\"Summary!B2\"],\"fail_on\":\"high\"}")
  assert_eq(config.min_severity, "high")
  assert_eq(config.disabled_rules.length(), 2)
  assert_eq(config.ignore_cells[0], "Summary!B2")
  assert_eq(config.fail_on, "high")
}

///|
test "parse partial config" {
  let config = @sheetsentry.parse_config("{\"disabled_rules\":[\"SS004\"]}")
  assert_eq(config.min_severity, "low")
  assert_eq(config.disabled_rules[0], "SS004")
  assert_eq(config.fail_on, "")
}

///|
test "parse empty object config" {
  let config = @sheetsentry.parse_config("{}")
  assert_eq(config.min_severity, "low")
  assert_eq(config.disabled_rules.length(), 0)
}

///|
test "apply config filters and ignores" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let report = @sheetsentry.audit_bytes(bytes, "bad_model.xlsx")
  let config = @sheetsentry.parse_config("{\"min_severity\":\"high\",\"disabled_rules\":[\"SS006\"],\"ignore_cells\":[\"Summary!B4\"]}")
  let filtered = @sheetsentry.apply_config(report, config)
  for finding in filtered.findings {
    assert_eq(finding.severity.label(), "high")
    assert_true(finding.rule_id != "SS006")
    assert_true(finding.cell != "B4")
  }
  assert_true(filtered.suppressed.length() > 0)
}

///|
test "report terminal includes suppressed" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let report = @sheetsentry.audit_bytes(bytes, "bad_model.xlsx")
  let text = @sheetsentry.to_terminal(report)
  assert_true(text.contains("suppressed:"))
  assert_true(text.contains("SS008"))
}

///|
test "report json includes suppressed field" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let report = @sheetsentry.audit_bytes(bytes, "bad_model.xlsx")
  let json = @sheetsentry.to_json(report)
  assert_true(json.contains("\"suppressed\":[]"))
  assert_true(json.contains("\"rule_id\":\"SS009\""))
}

///|
test "report html has filters" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let report = @sheetsentry.audit_bytes(bytes, "bad_model.xlsx")
  let html = @sheetsentry.to_html(report)
  assert_true(html.contains("data-severity="))
  assert_true(html.contains("filterRows"))
}

///|
test "sarif includes all rules" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let report = @sheetsentry.audit_bytes(bytes, "bad_model.xlsx")
  let sarif = @sheetsentry.to_sarif(report)
  assert_true(sarif.contains("\"SS010\""))
  assert_true(sarif.contains("\"version\":\"2.1.0\""))
}

///|
test "severity rank ordering" {
  assert_true(@sheetsentry.severity_rank(@sheetsentry.High) < @sheetsentry.severity_rank(@sheetsentry.Medium))
  assert_true(@sheetsentry.severity_rank(@sheetsentry.Medium) < @sheetsentry.severity_rank(@sheetsentry.Low))
}

///|
test "finding fingerprint has stable format" {
  let finding = @sheetsentry.Finding::{
    rule_id: "SS001",
    severity: @sheetsentry.High,
    sheet: "Summary",
    cell: "B4",
    formula: None,
    message: "x",
    related: [],
  }
  assert_eq(@sheetsentry.finding_fingerprint(finding), "SS001|Summary|B4")
}

///|
test "trace depth zero returns start" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let nodes = @sheetsentry.trace_bytes(bytes, "Summary!B3", "precedents", 0)
  assert_eq(nodes.length(), 1)
  assert_eq(nodes[0], "Summary!B3")
}

///|
test "slice includes only needed sheets" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let result = @sheetsentry.slice_bytes(bytes, "bad_model.xlsx", "Summary!B3", 20)
  assert_true(result.manifest.verified)
  assert_true(result.manifest.complete)
  assert_eq(result.manifest.included_sheets.length(), 2)
  assert_true(result.manifest.included_sheets.contains("Summary"))
  assert_true(result.manifest.included_sheets.contains("Opex"))
  assert_false(result.manifest.included_sheets.contains("Scratch"))
}

///|
test "slice preserves target value" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let result = @sheetsentry.slice_bytes(bytes, "bad_model.xlsx", "Summary!B3", 20)
  let sliced = @mbtexcel.read(result.data)
  let target = sliced.sheet("Summary").unwrap().get_cell("B3")
  assert_eq(target, Some("539"))
}

///|
test "depth-limited slice is incomplete" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let result = @sheetsentry.slice_bytes(bytes, "bad_model.xlsx", "Summary!B3", 0)
  assert_eq(result.manifest.included_cells.length(), 1)
  assert_false(result.manifest.complete)
  assert_true(result.manifest.unresolved.length() > 0)
}

///|
test "slice manifest json" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let result = @sheetsentry.slice_bytes(bytes, "bad_model.xlsx", "Summary!B3", 20)
  let json = @sheetsentry.slice_manifest_json(result.manifest)
  assert_true(json.contains("\"kind\":\"calculation-slice\""))
  assert_true(json.contains("\"complete\":true"))
  assert_true(json.contains("\"target\":\"Summary!B3\""))
}

///|
test "slice hashes are sha256 length" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let result = @sheetsentry.slice_bytes(bytes, "bad_model.xlsx", "Summary!B3", 20)
  assert_eq(result.manifest.source_sha256.length(), 64)
  assert_eq(result.manifest.slice_sha256.length(), 64)
  assert_true(result.manifest.source_sha256 != result.manifest.slice_sha256)
}

///|
test "missing slice target is not verified" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let result = @sheetsentry.slice_bytes(bytes, "bad_model.xlsx", "Missing!A1", 20)
  assert_false(result.manifest.verified)
  assert_false(result.manifest.complete)
  assert_true(result.manifest.unresolved.length() > 0)
}

///|
test "verify slice from manifest" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let result = @sheetsentry.slice_bytes(bytes, "bad_model.xlsx", "Summary!B3", 20)
  let verification = @sheetsentry.verify_slice_bytes(result.data, @sheetsentry.slice_manifest_json(result.manifest))
  assert_true(verification.verified)
  assert_eq(verification.target, "Summary!B3")
}

///|
test "verify slice rejects changed expectation" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let result = @sheetsentry.slice_bytes(bytes, "bad_model.xlsx", "Summary!B3", 20)
  let manifest = "{\"target\":\"Summary!B3\",\"target_value_before\":\"999\"}"
  let verification = @sheetsentry.verify_slice_bytes(result.data, manifest)
  assert_false(verification.verified)
}

///|
test "table catalog from xlsx" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let workbook = @xlsx.read(bytes)
  let tables = @sheetsentry.table_catalog(bytes, workbook.get_sheet_list())
  assert_eq(tables.length(), 1)
  assert_eq(tables[0].name, "OpexTable")
  assert_eq(tables[0].sheet, "Opex")
  assert_eq(tables[0].columns.length(), 4)
  assert_eq(tables[0].columns[1], "Amount")
}

///|
test "dynamic offset resolves" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let workbook = @xlsx.read(bytes)
  let refs = @sheetsentry.dynamic_refs("=OFFSET(Inputs!B2,1,0)", "Summary", 13, workbook)
  println("offset refs=\{refs.length()}")
  assert_eq(refs.length(), 1)
}

///|
test "structured reference slice is complete" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let result = @sheetsentry.slice_bytes(bytes, "bad_model.xlsx", "Summary!B10", 20)
  assert_true(result.manifest.verified)
  assert_true(result.manifest.complete)
  let sliced = @mbtexcel.read(result.data)
  let formula = sliced.sheet("Summary").unwrap().get_cell_formula("B10")
  assert_true(formula.unwrap().contains("Opex!$B$2:$B$6"))
}

///|
test "named range slice preserves definition" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let result = @sheetsentry.slice_bytes(bytes, "bad_model.xlsx", "Summary!B11", 20)
  assert_true(result.manifest.verified)
  assert_true(result.manifest.complete)
  let sliced = @mbtexcel.read(result.data)
  let mut found = false
  for defined in sliced.get_defined_names() {
    if defined.name == "RevenueInput" {
      found = true
    }
  }
  assert_true(found)
}

///|
test "indirect slice resolves literal reference" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let result = @sheetsentry.slice_bytes(bytes, "bad_model.xlsx", "Summary!B12", 20)
  assert_true(result.manifest.verified)
  assert_true(result.manifest.complete)
  assert_true(result.manifest.included_cells.contains("Inputs!B3"))
}

///|
test "offset slice resolves constant offsets" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let result = @sheetsentry.slice_bytes(bytes, "bad_model.xlsx", "Summary!B13", 20)
  assert_true(result.manifest.verified)
  assert_true(result.manifest.complete)
  assert_true(result.manifest.included_cells.contains("Inputs!B3"))
}

///|
test "external workbook slice with mapping" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let external = @fs.read_file_to_bytes("fixtures/external_book.xlsx")
  let map : Map[String, Bytes] = Map([("external_book.xlsx", external)])
  let result = @sheetsentry.slice_bytes_with_external(bytes, "bad_model.xlsx", "Summary!B14", 20, map)
  assert_true(result.manifest.verified)
  assert_true(result.manifest.complete)
  assert_eq(result.manifest.external_workbooks.length(), 1)
  let sliced = @mbtexcel.read(result.data)
  let external_sheet = sliced.sheet("__ext__external_book__Sheet1")
  assert_true(external_sheet is Some(_))
  assert_eq(external_sheet.unwrap().get_cell("A1"), Some("42"))
}

///|
test "external workbook slice without mapping is incomplete" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let result = @sheetsentry.slice_bytes(bytes, "bad_model.xlsx", "Summary!B14", 20)
  assert_true(result.manifest.verified)
  assert_false(result.manifest.complete)
  assert_true(result.manifest.unresolved.length() > 0)
}

///|
test "multi-target slice" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let result = @sheetsentry.slice_bytes_many(bytes, "bad_model.xlsx", ["Summary!B3", "Summary!B10"], 20, Map([]))
  assert_true(result.manifest.verified)
  assert_true(result.manifest.complete)
  assert_eq(result.manifest.targets.length(), 2)
  assert_eq(result.manifest.targets[1].target, "Summary!B10")
}

///|
test "multi-target verification" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let result = @sheetsentry.slice_bytes_many(bytes, "bad_model.xlsx", ["Summary!B3", "Summary!B10"], 20, Map([]))
  let verification = @sheetsentry.verify_slice_bytes(result.data, @sheetsentry.slice_manifest_json(result.manifest))
  assert_true(verification.verified)
  assert_true(verification.hash_verified)
  assert_true(verification.calc_verified)
  assert_eq(verification.targets_verified, 2)
  assert_eq(verification.targets_calc_verified, 2)
  assert_eq(verification.targets_total, 2)
}

///|
test "slice certificate html" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let result = @sheetsentry.slice_bytes(bytes, "bad_model.xlsx", "Summary!B3", 20)
  let html = @sheetsentry.slice_report_html(result.manifest)
  assert_true(html.contains("slice certificate"))
  assert_true(html.contains("Summary!B3"))
  assert_true(html.contains(result.manifest.slice_sha256))
}

///|
test "slice recalculates independently" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let result = @sheetsentry.slice_bytes(bytes, "bad_model.xlsx", "Summary!B3", 20)
  let sliced = @mbtexcel.read(result.data)
  let calculated = sliced.calc_cell_value("Summary", "B3", raw=true)
  assert_eq(calculated, "539")
}

///|
test "slice minimality metrics" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let result = @sheetsentry.slice_bytes_many(bytes, "bad_model.xlsx", ["Summary!B3", "Summary!B10"], 20, Map([]))
  assert_true(result.manifest.minimality_verified)
  assert_true(result.manifest.total_used_cells > result.manifest.included_used_cells)
  assert_true(result.manifest.excluded_used_cells > 0)
  assert_eq(result.manifest.reduction_ratio, "\{result.manifest.included_used_cells}/\{result.manifest.total_used_cells}")
}

///|
test "complex reference slices recalculate independently" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let structured = @sheetsentry.slice_bytes(bytes, "bad_model.xlsx", "Summary!B10", 20)
  let named = @sheetsentry.slice_bytes(bytes, "bad_model.xlsx", "Summary!B11", 20)
  let indirect = @sheetsentry.slice_bytes(bytes, "bad_model.xlsx", "Summary!B12", 20)
  let offset = @sheetsentry.slice_bytes(bytes, "bad_model.xlsx", "Summary!B13", 20)
  assert_true(structured.manifest.calc_verified)
  assert_true(named.manifest.calc_verified)
  assert_true(indirect.manifest.calc_verified)
  assert_true(offset.manifest.calc_verified)
  assert_eq(structured.manifest.targets[0].calculated, Some("640"))
  assert_eq(named.manifest.targets[0].calculated, Some("2000"))
  assert_eq(indirect.manifest.targets[0].calculated, Some("30"))
}

///|
test "minimality detail lists are empty" {
  let bytes = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let result = @sheetsentry.slice_bytes_many(bytes, "bad_model.xlsx", ["Summary!B3", "Summary!B10"], 20, Map([]))
  assert_eq(result.manifest.unreachable_included.length(), 0)
  assert_eq(result.manifest.missing_required.length(), 0)
  assert_eq(result.manifest.excluded_reachable.length(), 0)
}

///|
test "source hash verification" {
  let source = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let result = @sheetsentry.slice_bytes(source, "bad_model.xlsx", "Summary!B3", 20)
  let manifest = @sheetsentry.slice_manifest_json(result.manifest)
  let ok = @sheetsentry.verify_slice_with_source(source, result.data, manifest)
  assert_true(ok.source_hash_verified)
  let wrong = @sheetsentry.verify_slice_with_source(@fs.read_file_to_bytes("fixtures/clean_model.xlsx"), result.data, manifest)
  assert_false(wrong.source_hash_verified)
}

///|
test "complex workbook combined slice" {
  let source = @fs.read_file_to_bytes("fixtures/bad_model.xlsx")
  let external = @fs.read_file_to_bytes("fixtures/external_book.xlsx")
  let map : Map[String, Bytes] = Map([("external_book.xlsx", external)])
  let targets = ["Summary!B3", "Summary!B10", "Summary!B11", "Summary!B12", "Summary!B13", "Summary!B14"]
  let result = @sheetsentry.slice_bytes_many(source, "bad_model.xlsx", targets, 20, map)
  assert_eq(result.manifest.targets.length(), 6)
  assert_true(result.manifest.verified)
  assert_true(result.manifest.calc_verified)
  assert_true(result.manifest.minimality_verified)
  assert_true(result.manifest.complete)
  assert_eq(result.manifest.external_workbooks.length(), 1)
}

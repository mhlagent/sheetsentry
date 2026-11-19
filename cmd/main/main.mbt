///|
fn usage() -> Unit {
  println("SheetSentry - Excel model static analysis")
  println("")
  println("Usage:")
  println(
    "  sheetsentry audit <file.xlsx> [--format terminal|json|sarif|html] [--out <path>] [--baseline <path>] [--write-baseline <path>] [--config <path>] [--min-severity high|medium|low] [--disable SS003,SS004] [--fail-on high|medium|low]",
  )
  println(
    "  sheetsentry trace <file.xlsx> --cell <Sheet!A1> [--direction precedents|dependents] [--depth 3]",
  )
  println(
    "  sheetsentry graph <file.xlsx> [--format dot|mermaid] [--out <path>]",
  )
  println(
    "  sheetsentry slice <file.xlsx> --target <Sheet!A1> [--target <Sheet!B1>] [--targets-file targets.txt] --out <slice.xlsx> [--manifest <manifest.json>] [--report <certificate.html>] [--external book.xlsx=path] [--strict] [--depth 20]",
  )
  println(
    "  sheetsentry verify-slice <slice.xlsx> --manifest <manifest.json> [--source <source.xlsx>] [--strict]",
  )
  println("  sheetsentry rules")
}

///|
fn fatal(message : String) -> Unit {
  println("sheetsentry: \{message}")
  @sys.exit(1)
}

///|
fn usage_failure() -> Unit {
  usage()
  @sys.exit(2)
}

///|
fn valid_report_format(value : String) -> Bool {
  value == "terminal" || value == "json" || value == "sarif" || value == "html"
}

///|
fn valid_severity(value : String) -> Bool {
  value == "high" || value == "medium" || value == "low"
}

///|
fn valid_fail_threshold(value : String) -> Bool {
  value == "" || valid_severity(value)
}

///|
fn run_audit(args : Array[String]) -> Unit {
  let path = args[2]
  let mut format = "terminal"
  let mut out : String? = None
  let mut fail_on = ""
  let mut baseline_path : String? = None
  let mut write_baseline_path : String? = None
  let mut min_severity = "low"
  let mut disabled_rules : Array[String] = []
  let mut config_path : String? = None
  let mut i = 3
  while i < args.length() {
    let arg = args[i]
    if arg == "--format" {
      if i + 1 >= args.length() {
        fatal("--format requires a value")
      }
      format = args[i + 1]
      i = i + 2
    } else if arg == "--out" {
      if i + 1 >= args.length() {
        fatal("--out requires a value")
      }
      out = Some(args[i + 1])
      i = i + 2
    } else if arg == "--fail-on" {
      if i + 1 >= args.length() {
        fatal("--fail-on requires a value")
      }
      fail_on = args[i + 1]
      i = i + 2
    } else if arg == "--baseline" {
      if i + 1 >= args.length() {
        fatal("--baseline requires a value")
      }
      baseline_path = Some(args[i + 1])
      i = i + 2
    } else if arg == "--write-baseline" {
      if i + 1 >= args.length() {
        fatal("--write-baseline requires a value")
      }
      write_baseline_path = Some(args[i + 1])
      i = i + 2
    } else if arg == "--min-severity" {
      if i + 1 >= args.length() {
        fatal("--min-severity requires a value")
      }
      min_severity = args[i + 1]
      i = i + 2
    } else if arg == "--disable" {
      if i + 1 >= args.length() {
        fatal("--disable requires a value")
      }
      disabled_rules = args[i + 1]
        .split(",")
        .map(fn(x) { x.to_owned() })
        .collect()
      i = i + 2
    } else if arg == "--config" {
      if i + 1 >= args.length() {
        fatal("--config requires a value")
      }
      config_path = Some(args[i + 1])
      i = i + 2
    } else {
      fatal("unknown audit option: \{arg}")
    }
  }
  if !valid_report_format(format) {
    fatal("--format must be terminal, json, sarif, or html")
  }
  if !valid_severity(min_severity) {
    fatal("--min-severity must be high, medium, or low")
  }
  if !valid_fail_threshold(fail_on) {
    fatal("--fail-on must be high, medium, or low")
  }
  try {
    let bytes = @fs.read_file_to_bytes(path)
    let mut report = @sheetsentry.audit_bytes(bytes, path)
    match baseline_path {
      Some(baseline) => {
        let baseline_text = @fs.read_file_to_string(baseline)
        let fingerprints = @sheetsentry.parse_baseline(baseline_text)
        report = @sheetsentry.apply_baseline(report, fingerprints)
      }
      None => ()
    }
    match config_path {
      Some(config_file) => {
        let config_text = @fs.read_file_to_string(config_file)
        let config = @sheetsentry.parse_config(config_text)
        if !valid_severity(config.min_severity) {
          fatal("config min_severity must be high, medium, or low")
        }
        if !valid_fail_threshold(config.fail_on) {
          fatal("config fail_on must be high, medium, or low")
        }
        report = @sheetsentry.apply_config(report, config)
        if fail_on == "" {
          fail_on = config.fail_on
        }
      }
      None => ()
    }
    report = @sheetsentry.filter_report(report, min_severity, disabled_rules)
    match write_baseline_path {
      Some(target) =>
        @fs.write_string_to_file(target, @sheetsentry.baseline_json(report))
      None => ()
    }
    let text = match format {
      "json" => @sheetsentry.to_json(report)
      "sarif" => @sheetsentry.to_sarif(report)
      "html" => @sheetsentry.to_html(report)
      _ => @sheetsentry.to_terminal(report)
    }
    match out {
      Some(target) => @fs.write_string_to_file(target, text)
      None => println(text)
    }
    if fail_on != "" && @sheetsentry.should_fail(report, fail_on) {
      @sys.exit(1)
    }
  } catch {
    err => fatal("\{err}")
  }
}

///|
fn run_trace(args : Array[String]) -> Unit {
  let path = args[2]
  let mut cell = ""
  let mut direction = "precedents"
  let mut depth = 3
  let mut i = 3
  while i < args.length() {
    let arg = args[i]
    if arg == "--cell" {
      if i + 1 >= args.length() {
        fatal("--cell requires a value")
      }
      cell = args[i + 1]
      i = i + 2
    } else if arg == "--direction" {
      if i + 1 >= args.length() {
        fatal("--direction requires a value")
      }
      direction = args[i + 1]
      i = i + 2
    } else if arg == "--depth" {
      if i + 1 >= args.length() {
        fatal("--depth requires a value")
      }
      depth = @string.parse_int(args[i + 1]) catch {
        _ => {
          fatal("--depth expects an integer")
          0
        }
      }
      i = i + 2
    } else {
      fatal("unknown trace option: \{arg}")
    }
  }
  if cell == "" {
    fatal("--cell is required, for example --cell 'Summary!B7'")
  }
  if direction != "precedents" && direction != "dependents" {
    fatal("--direction must be precedents or dependents")
  }
  if depth < 0 {
    fatal("--depth must be zero or greater")
  }
  try {
    let bytes = @fs.read_file_to_bytes(path)
    let nodes = @sheetsentry.trace_bytes(bytes, cell, direction, depth)
    println("\{direction}: \{cell}")
    for index, node in nodes {
      if index > 0 {
        println("  -> \{node}")
      }
    }
  } catch {
    err => fatal("\{err}")
  }
}

///|
fn run_graph(args : Array[String]) -> Unit {
  let path = args[2]
  let mut format = "dot"
  let mut out : String? = None
  let mut i = 3
  while i < args.length() {
    let arg = args[i]
    if arg == "--format" {
      if i + 1 >= args.length() {
        fatal("--format requires a value")
      }
      format = args[i + 1]
      i = i + 2
    } else if arg == "--out" {
      if i + 1 >= args.length() {
        fatal("--out requires a value")
      }
      out = Some(args[i + 1])
      i = i + 2
    } else {
      fatal("unknown graph option: \{arg}")
    }
  }
  if format != "dot" && format != "mermaid" {
    fatal("--format must be dot or mermaid")
  }
  try {
    let bytes = @fs.read_file_to_bytes(path)
    let graph = @sheetsentry.build_graph_bytes(bytes)
    let text = if format == "mermaid" {
      @sheetsentry.graph_to_mermaid(graph)
    } else {
      @sheetsentry.graph_to_dot(graph)
    }
    match out {
      Some(target) => @fs.write_string_to_file(target, text)
      None => println(text)
    }
  } catch {
    err => fatal("\{err}")
  }
}

///|
fn run_slice(args : Array[String]) -> Unit {
  let path = args[2]
  let targets : Array[String] = []
  let mut out = ""
  let mut manifest_path = ""
  let mut report_path = ""
  let mut strict = false
  let mut depth = 20
  let external_map : Map[String, Bytes] = Map([])
  let mut i = 3
  while i < args.length() {
    let arg = args[i]
    if arg == "--target" {
      if i + 1 >= args.length() {
        fatal("--target requires a value")
      }
      targets.push(args[i + 1])
      i = i + 2
    } else if arg == "--targets" {
      if i + 1 >= args.length() {
        fatal("--targets requires a value")
      }
      for target in args[i + 1].split(",") {
        let value = target.trim()
        if value != "" {
          targets.push(value.to_owned())
        }
      }
      i = i + 2
    } else if arg == "--targets-file" {
      if i + 1 >= args.length() {
        fatal("--targets-file requires a value")
      }
      let target_file = args[i + 1]
      let content = @fs.read_file_to_string(target_file) catch {
        _ => {
          fatal("failed to read targets file \{target_file}")
          ""
        }
      }
      for target in @sheetsentry.parse_targets_file(content) {
        targets.push(target)
      }
      i = i + 2
    } else if arg == "--strict" {
      strict = true
      i = i + 1
    } else if arg == "--report" {
      if i + 1 >= args.length() {
        fatal("--report requires a value")
      }
      report_path = args[i + 1]
      i = i + 2
    } else if arg == "--out" {
      if i + 1 >= args.length() {
        fatal("--out requires a value")
      }
      out = args[i + 1]
      i = i + 2
    } else if arg == "--manifest" {
      if i + 1 >= args.length() {
        fatal("--manifest requires a value")
      }
      manifest_path = args[i + 1]
      i = i + 2
    } else if arg == "--depth" {
      if i + 1 >= args.length() {
        fatal("--depth requires a value")
      }
      depth = @string.parse_int(args[i + 1]) catch {
        _ => {
          fatal("--depth expects an integer")
          0
        }
      }
      i = i + 2
    } else if arg == "--external" {
      if i + 1 >= args.length() {
        fatal("--external requires a value")
      }
      let spec = args[i + 1]
      match spec.split("=").collect() {
        [name, external_path] =>
          try {
            let bytes = @fs.read_file_to_bytes(external_path.to_owned())
            external_map.set(name.to_owned(), bytes)
          } catch {
            _ => fatal("failed to read external workbook \{external_path}")
          }
        _ => fatal("--external expects name=path")
      }
      i = i + 2
    } else {
      fatal("unknown slice option: \{arg}")
    }
  }
  if depth < 0 {
    fatal("--depth must be zero or greater")
  }
  if targets.length() == 0 || out == "" {
    fatal("at least one --target and --out are required")
  }
  try {
    let bytes = @fs.read_file_to_bytes(path)
    let result = @sheetsentry.slice_bytes_many(
      bytes, path, targets, depth, external_map,
    )
    @fs.write_bytes_to_file(out, result.data)
    if manifest_path != "" {
      @fs.write_string_to_file(
        manifest_path,
        @sheetsentry.slice_manifest_json(result.manifest),
      )
    }
    if report_path != "" {
      @fs.write_string_to_file(
        report_path,
        @sheetsentry.slice_report_html(result.manifest),
      )
    }
    println("slice: \{targets.length()} target(s) -> \{out}")
    println(
      "  cells: \{result.manifest.included_cells.length()}  sheets: \{result.manifest.included_sheets.length()}  used: \{result.manifest.reduction_ratio}  minimal: \{result.manifest.minimality_verified}  external: \{result.manifest.external_workbooks.length()}  verified: \{result.manifest.verified}  calc: \{result.manifest.calc_verified}  complete: \{result.manifest.complete}  unresolved: \{result.manifest.unresolved.length()}",
    )
    if strict &&
      !(result.manifest.verified &&
      result.manifest.calc_verified &&
      result.manifest.complete &&
      result.manifest.minimality_verified) {
      @sys.exit(1)
    }
  } catch {
    err => fatal("\{err}")
  }
}

///|
fn run_verify_slice(args : Array[String]) -> Unit {
  let slice_path = args[2]
  let mut manifest_path = ""
  let mut source_path = ""
  let mut strict = false
  let mut i = 3
  while i < args.length() {
    let arg = args[i]
    if arg == "--manifest" {
      if i + 1 >= args.length() {
        fatal("--manifest requires a value")
      }
      manifest_path = args[i + 1]
      i = i + 2
    } else if arg == "--source" {
      if i + 1 >= args.length() {
        fatal("--source requires a value")
      }
      source_path = args[i + 1]
      i = i + 2
    } else if arg == "--strict" {
      strict = true
      i = i + 1
    } else {
      fatal("unknown verify-slice option: \{arg}")
    }
  }
  if manifest_path == "" {
    fatal("--manifest is required")
  }
  try {
    let slice_bytes = @fs.read_file_to_bytes(slice_path)
    let manifest_text = @fs.read_file_to_string(manifest_path)
    let result = if source_path != "" {
      let source_bytes = @fs.read_file_to_bytes(source_path)
      @sheetsentry.verify_slice_with_source(
        source_bytes, slice_bytes, manifest_text,
      )
    } else {
      @sheetsentry.verify_slice_bytes(slice_bytes, manifest_text)
    }
    println("verify-slice: \{result.target}")
    let before = match result.before {
      Some(value) => value
      None => "<missing>"
    }
    let after = match result.after {
      Some(value) => value
      None => "<missing>"
    }
    println(
      "  before: \{before}  after: \{after}  verified: \{result.verified}",
    )
    println(
      "  targets: \{result.targets_verified}/\{result.targets_total}  recalculated: \{result.targets_calc_verified}/\{result.targets_total}  slice_sha256: \{result.hash_verified}  complete: \{result.complete}",
    )
    if source_path != "" {
      println("  source_sha256: \{result.source_hash_verified}")
    }
    if result.error is Some(message) {
      println("  error: \{message}")
    }
    if strict &&
      !(result.verified &&
      result.calc_verified &&
      result.hash_verified &&
      result.complete &&
      result.minimality_verified &&
      (source_path == "" || result.source_hash_verified)) {
      @sys.exit(1)
    }
  } catch {
    err => fatal("\{err}")
  }
}

///|
fn main {
  let args = @env.args()
  if args.length() < 2 {
    usage_failure()
  }
  match args[1] {
    "audit" =>
      if args.length() >= 3 {
        run_audit(args)
      } else {
        usage_failure()
      }
    "trace" =>
      if args.length() >= 3 {
        run_trace(args)
      } else {
        usage_failure()
      }
    "graph" =>
      if args.length() >= 3 {
        run_graph(args)
      } else {
        usage_failure()
      }
    "slice" =>
      if args.length() >= 3 {
        run_slice(args)
      } else {
        usage_failure()
      }
    "verify-slice" =>
      if args.length() >= 3 {
        run_verify_slice(args)
      } else {
        usage_failure()
      }
    "rules" => println(@sheetsentry.rule_catalog())
    "--version" => println("SheetSentry \{@sheetsentry.tool_version()}")
    "--help" | "-h" | "help" => usage()
    _ => usage_failure()
  }
}

///|
fn usage() -> Unit {
  println("SheetSentry - Excel model static analysis")
  println("")
  println("Usage:")
  println("  sheetsentry audit <file.xlsx> [--format terminal|json|sarif|html] [--out <path>] [--baseline <path>] [--write-baseline <path>] [--fail-on high|medium|low]")
  println("  sheetsentry trace <file.xlsx> --cell <Sheet!A1> [--direction precedents|dependents] [--depth 3]")
}

///|
fn run_audit(args : Array[String]) -> Unit {
  let path = args[2]
  let mut format = "terminal"
  let mut out : String? = None
  let mut fail_on = ""
  let mut baseline_path : String? = None
  let mut write_baseline_path : String? = None
  let mut i = 3
  while i < args.length() {
    if args[i] == "--format" && i + 1 < args.length() {
      format = args[i + 1]
      i = i + 2
    } else if args[i] == "--out" && i + 1 < args.length() {
      out = Some(args[i + 1])
      i = i + 2
    } else if args[i] == "--fail-on" && i + 1 < args.length() {
      fail_on = args[i + 1]
      i = i + 2
    } else if args[i] == "--baseline" && i + 1 < args.length() {
      baseline_path = Some(args[i + 1])
      i = i + 2
    } else if args[i] == "--write-baseline" && i + 1 < args.length() {
      write_baseline_path = Some(args[i + 1])
      i = i + 2
    } else {
      i = i + 1
    }
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
    match write_baseline_path {
      Some(target) => @fs.write_string_to_file(target, @sheetsentry.baseline_json(report))
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
    err => println("sheetsentry: \{err}")
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
    if args[i] == "--cell" && i + 1 < args.length() {
      cell = args[i + 1]
      i = i + 2
    } else if args[i] == "--direction" && i + 1 < args.length() {
      direction = args[i + 1]
      i = i + 2
    } else if args[i] == "--depth" && i + 1 < args.length() {
      depth = @string.parse_int(args[i + 1]) catch { _ => 3 }
      i = i + 2
    } else {
      i = i + 1
    }
  }
  if cell == "" {
    println("sheetsentry: --cell is required, for example --cell 'Summary!B7'")
    return
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
    err => println("sheetsentry: \{err}")
  }
}

///|
fn main {
  let args = @env.args()
  if args.length() < 2 {
    usage()
    return
  }
  match args[1] {
    "audit" =>
      if args.length() >= 3 {
        run_audit(args)
      } else {
        usage()
      }
    "trace" =>
      if args.length() >= 3 {
        run_trace(args)
      } else {
        usage()
      }
    _ => usage()
  }
}

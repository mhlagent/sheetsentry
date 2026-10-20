///|
pub fn parse_baseline(text : String) -> Array[String] raise @json.ParseError {
  let value = @json.parse(text)
  match value {
    Object(map) =>
      match map.get("fingerprints") {
        Some(Array(items)) => {
          let result : Array[String] = []
          for item in items {
            match item {
              String(value) => result.push(value)
              _ => ()
            }
          }
          result
        }
        Some(String(value)) => [value]
        _ => []
      }
    Array(items) => {
      let result : Array[String] = []
      for item in items {
        match item {
          String(value) => result.push(value)
          _ => ()
        }
      }
      result
    }
    _ => []
  }
}

///|
pub fn baseline_json(report : AuditReport) -> String {
  let fingerprints = all_fingerprints(report)
  let items = "[" + fingerprints.map(fn(x) { "\"" + x + "\"" }).join(",") + "]"
  "{\"version\":1,\"fingerprints\":\{items}}"
}

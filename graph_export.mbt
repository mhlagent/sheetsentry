///|
fn dot_escape(value : String) -> String {
  let mut out = ""
  for c in value {
    match c {
      '"' => out = out + "\\\""
      '\\' => out = out + "\\\\"
      _ => out = out + c.to_string()
    }
  }
  out
}

///|
pub fn graph_to_dot(graph : DependencyGraph) -> String {
  let mut out = "digraph sheetsentry {\n  rankdir=LR;\n  node [shape=box, fontname=\"Helvetica\"];\n"
  for from, targets in graph.edges {
    out = out + "  \"" + dot_escape(from) + "\";\n"
    for target in targets {
      out = out + "  \"" + dot_escape(from) + "\" -> \"" + dot_escape(target) + "\";\n"
    }
  }
  out + "}\n"
}

///|
pub fn graph_to_mermaid(graph : DependencyGraph) -> String {
  let mut out = "graph LR\n"
  for from, targets in graph.edges {
    for target in targets {
      out = out + "  \"\{from}\" --> \"\{target}\"\n"
    }
  }
  out
}

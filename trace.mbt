///|
pub fn build_graph_bytes(bytes : Bytes) -> DependencyGraph raise @xlsx.XlsxError {
  let workbook = @xlsx.read(bytes)
  let tables = table_catalog(bytes, workbook.get_sheet_list())
  let graph = DependencyGraph::new()
  for name in workbook.get_sheet_list() {
    let sheet = workbook.sheet(name).unwrap()
    let max_row = sheet.max_row()
    let max_col = sheet.max_col()
    for row in 1..=max_row {
      for col in 1..=max_col {
        let cell = @xlsx.coordinates_to_cell_name(col, row)
        match sheet.get_cell_formula(cell) {
          Some(text) => {
            let key = node_key(name, row, col)
            ignore(graph.edges.get_or_init(key, fn() { [] }))
            for r in resolve_formula_cells(workbook, tables, name, text, row) {
              let target_sheet = match r.sheet {
                Some(value) => value
                None => name
              }
              let row_lo = if r.row < r.end_row { r.row } else { r.end_row }
              let row_hi = if r.row < r.end_row { r.end_row } else { r.row }
              let col_lo = if r.col < r.end_col { r.col } else { r.end_col }
              let col_hi = if r.col < r.end_col { r.end_col } else { r.col }
              let mut added = 0
              for rr in row_lo..=row_hi {
                for cc in col_lo..=col_hi {
                  if added < 500 {
                    add_edge(graph, key, node_key(target_sheet, rr, cc))
                    added = added + 1
                  }
                }
              }
            }
          }
          None => ()
        }
      }
    }
  }
  graph
}

///|
pub fn trace_bytes(
  bytes : Bytes,
  start : String,
  direction : String,
  max_depth : Int,
) -> Array[String] raise @xlsx.XlsxError {
  let graph = build_graph_bytes(bytes)
  let result : Array[String] = [start]
  let visited : Map[String, Bool] = Map([(start, true)])
  let mut frontier : Array[String] = [start]
  let mut depth = 0
  while depth < max_depth && frontier.length() > 0 {
    let next_frontier : Array[String] = []
    for node in frontier {
      let neighbors = if direction == "dependents" {
        graph.reverse.get(node)
      } else {
        graph.edges.get(node)
      }
      match neighbors {
        Some(list) =>
          for target in list {
            if !visited.contains(target) {
              visited.set(target, true)
              result.push(target)
              next_frontier.push(target)
            }
          }
        None => ()
      }
    }
    frontier = next_frontier
    depth = depth + 1
  }
  result
}

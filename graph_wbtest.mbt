///|
test "find self cycle" {
  let graph = DependencyGraph::new()
  add_edge(graph, "A", "A")
  let cycle = find_cycle_from(graph, "A")
  assert_true(cycle is Some(_))
  assert_eq(cycle.unwrap().length(), 2)
}

///|
test "find three node cycle" {
  let graph = DependencyGraph::new()
  add_edge(graph, "A", "B")
  add_edge(graph, "B", "C")
  add_edge(graph, "C", "A")
  let cycle = find_cycle_from(graph, "A")
  assert_true(cycle is Some(_))
  assert_eq(cycle.unwrap().length(), 4)
}

///|
test "dot export escapes quotes" {
  let graph = DependencyGraph::new()
  add_edge(graph, "A\"B", "C")
  let dot = graph_to_dot(graph)
  assert_true(dot.contains("A\\\"B"))
}

///|
test "mermaid export contains edge" {
  let graph = DependencyGraph::new()
  add_edge(graph, "Sheet!A1", "Sheet!B1")
  let mermaid = graph_to_mermaid(graph)
  assert_true(mermaid.contains("\"Sheet!A1\" --> \"Sheet!B1\""))
}

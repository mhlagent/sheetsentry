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

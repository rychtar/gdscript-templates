extends RefCounted

# Base of the test files: check() records a failure, the runner reports it.

var tree: SceneTree
var failures: Array[String] = []
var _nodes: Array[Node] = []

func check(description: String, got, expected) -> void:
	if typeof(got) != typeof(expected) or got != expected:
		failures.append("%s\ngot:      %s\nexpected: %s" % [description, var_to_str(got), var_to_str(expected)])

# a node that is freed after the test
func track(node: Node) -> Node:
	_nodes.append(node)
	return node

# a CodeEdit in the scene tree (it only emits caret_changed repeatedly once it is drawn)
# with the text and the caret at the end, or at (line, column)
func make_edit(text: String, line: int = -1, column: int = -1) -> CodeEdit:
	var edit: CodeEdit = track(CodeEdit.new())
	tree.root.add_child(edit)
	edit.text = text
	edit.set_caret_line(line if line >= 0 else edit.get_line_count() - 1)
	edit.set_caret_column(column if column >= 0 else edit.get_line(edit.get_caret_line()).length())
	return edit

func cleanup() -> void:
	for node in _nodes:
		node.free()
	_nodes.clear()

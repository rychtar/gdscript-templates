extends "res://tests/assertions.gd"

const Inserter = preload("res://addons/gdscript-templates/scripts/template_inserter.gd")

func test_replaces_the_range() -> void:
	var edit = make_edit("x = vec")
	Inserter.insert(edit, "Vector2({x=0}, {y=0})", Vector2i(0, 4), Vector2i(0, 7))
	check("text", edit.text, "x = Vector2(0, 0)")

func test_returns_tab_stops() -> void:
	var edit = make_edit("vec")
	var session = Inserter.insert(edit, "Vector2({x=1}, {y=2})", Vector2i(0, 0), Vector2i(0, 3))
	check("a session", session != null and session.active, true)
	check("first parameter is selected", edit.get_selected_text(), "1")

func test_no_session_without_parameters() -> void:
	var edit = make_edit("pr")
	var session = Inserter.insert(edit, "print(|CURSOR|)", Vector2i(0, 0), Vector2i(0, 2))
	check("no session", session, null)
	check("caret at |CURSOR|", edit.get_caret_column(), 6)
	check("nothing selected", edit.has_selection(), false)

func test_given_params_are_not_tab_stops() -> void:
	var edit = make_edit("vec")
	var session = Inserter.insert(edit, "Vector2({x=1}, {y=2})", Vector2i(0, 0), Vector2i(0, 3), ["5", "6"])
	check("text", edit.text, "Vector2(5, 6)")
	check("no session", session, null)

func test_following_lines_keep_the_indentation() -> void:
	var edit = make_edit("\t\tif")
	Inserter.insert(edit, "if {c}:\n\t{selection}", Vector2i(0, 2), Vector2i(0, 4), [], "pass")
	check("text", edit.text, "\t\tif c:\n\t\t\tpass")

func test_indents_with_spaces_when_the_editor_does() -> void:
	var edit = make_edit("if")
	edit.indent_use_spaces = true
	edit.indent_size = 2
	Inserter.insert(edit, "if x:\n\tpass", Vector2i(0, 0), Vector2i(0, 2))
	check("text", edit.text, "if x:\n  pass")
	check("unit", Inserter.indent_unit(edit), "  ")

func test_indent_unit_is_a_tab_by_default() -> void:
	check("tab", Inserter.indent_unit(make_edit("")), "\t")

func test_replaces_a_selection_over_lines() -> void:
	var edit = make_edit("a = 1\nb = 2")
	Inserter.insert(edit, "if x:\n\t{selection}", Vector2i(0, 0), Vector2i(1, 5), [], "a = 1\nb = 2")
	check("text", edit.text, "if x:\n\ta = 1\n\tb = 2")

func test_one_undo_step() -> void:
	var edit = make_edit("x = vec")
	edit.clear_undo_history()
	Inserter.insert(edit, "Vector2({x=0}, {y=0})", Vector2i(0, 4), Vector2i(0, 7))
	edit.undo()
	check("undo restores the text", edit.text, "x = vec")

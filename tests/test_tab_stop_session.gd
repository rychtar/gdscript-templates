extends "res://tests/assertions.gd"

const Expander = preload("res://addons/gdscript-templates/scripts/template_expander.gd")
const TabStopSession = preload("res://addons/gdscript-templates/scripts/tab_stop_session.gd")

# inserts the expanded template into an empty editor and starts the session
func _start(body: String) -> Array:
	var edit = make_edit("")
	var expanded = Expander.expand(body)
	edit.insert_text_at_caret(expanded.text)
	var session = TabStopSession.new(edit, expanded, 0, 0)
	session.start()
	return [edit, session]

func test_first_stop_is_selected() -> void:
	var edit = _start("f({a}, {b})")[0]
	check("selected text", edit.get_selected_text(), "a")

func test_tab_copies_the_value_and_moves_on() -> void:
	var started = _start("{a} = {a} + {b}")
	var edit: CodeEdit = started[0]
	var session = started[1]
	edit.insert_text_at_caret("x")
	check("tab is consumed", session.next(), true)
	check("value copied to the other place", edit.text, "x = x + b")
	check("next parameter selected", edit.get_selected_text(), "b")

func test_last_tab_goes_to_the_cursor() -> void:
	var started = _start("{a} |CURSOR|end")
	var edit: CodeEdit = started[0]
	var session = started[1]
	session.next()
	check("session is over", session.active, false)
	check("caret at |CURSOR|", edit.get_caret_column(), 2)
	check("nothing selected", edit.has_selection(), false)

func test_shift_tab_goes_back() -> void:
	var started = _start("{a} {b}")
	var edit: CodeEdit = started[0]
	var session = started[1]
	session.next()
	check("second parameter", edit.get_selected_text(), "b")
	session.previous()
	check("first parameter again", edit.get_selected_text(), "a")

func test_empty_default_before_another_parameter() -> void:
	var started = _start("{a=}{b}")
	var edit: CodeEdit = started[0]
	var session = started[1]
	edit.insert_text_at_caret("X")
	session.next()
	check("next parameter is in the right place", edit.get_selected_text(), "b")
	check("text", edit.text, "Xb")

func test_no_parameters_moves_to_the_cursor() -> void:
	var started = _start("abc|CURSOR|def")
	check("no session", started[1].active, false)
	check("caret", started[0].get_caret_column(), 3)

# caret_changed is emitted at the end of the frame
func test_moving_the_caret_away_ends_the_session() -> void:
	var started = _start("{a} {a}\nnext")
	var edit: CodeEdit = started[0]
	var session = started[1]
	await tree.process_frame
	await tree.process_frame
	edit.insert_text_at_caret("x")
	edit.set_caret_line(1)
	await tree.process_frame
	check("session ended", session.active, false)
	check("value still copied", edit.get_line(0), "x x")

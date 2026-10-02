extends "res://tests/assertions.gd"

const Expander = preload("res://addons/gdscript-templates/scripts/template_expander.gd")
const TabStopSession = preload("res://addons/gdscript-templates/scripts/tab_stop_session.gd")

# inserts the expanded template into an empty editor and starts the session
func _start(body: String) -> Array:
	var edit := make_edit("")
	var expanded := Expander.expand(body)
	edit.insert_text_at_caret(expanded.text)
	var session := TabStopSession.new(edit, expanded, 0, 0)
	session.start()
	return [edit, session]

func test_first_stop_is_selected() -> void:
	var edit: CodeEdit = _start("f({a}, {b})")[0]
	check("selected text", edit.get_selected_text(), "a")

func test_tab_copies_the_value_and_moves_on() -> void:
	var started := _start("{a} = {a} + {b}")
	var edit: CodeEdit = started[0]
	var session: TabStopSession = started[1]
	edit.insert_text_at_caret("x")
	check("tab is consumed", session.next(), true)
	check("value copied to the other place", edit.text, "x = x + b")
	check("next parameter selected", edit.get_selected_text(), "b")

func test_last_tab_goes_to_the_cursor() -> void:
	var started := _start("{a} |CURSOR|end")
	var edit: CodeEdit = started[0]
	var session: TabStopSession = started[1]
	session.next()
	check("session is over", session.active, false)
	check("caret at |CURSOR|", edit.get_caret_column(), 2)
	check("nothing selected", edit.has_selection(), false)

func test_shift_tab_goes_back() -> void:
	var started := _start("{a} {b}")
	var edit: CodeEdit = started[0]
	var session: TabStopSession = started[1]
	session.next()
	check("second parameter", edit.get_selected_text(), "b")
	session.previous()
	check("first parameter again", edit.get_selected_text(), "a")

func test_empty_default_before_another_parameter() -> void:
	var started := _start("{a=}{b}")
	var edit: CodeEdit = started[0]
	var session: TabStopSession = started[1]
	edit.insert_text_at_caret("X")
	session.next()
	check("next parameter is in the right place", edit.get_selected_text(), "b")
	check("text", edit.text, "Xb")

func test_no_parameters_moves_to_the_cursor() -> void:
	var started := _start("abc|CURSOR|def")
	check("no session", started[1].active, false)
	check("caret", started[0].get_caret_column(), 3)

# caret_changed is emitted at the end of the frame
func test_moving_the_caret_away_ends_the_session() -> void:
	var started := _start("{a} {a}\nnext")
	var edit: CodeEdit = started[0]
	var session: TabStopSession = started[1]
	await tree.process_frame
	await tree.process_frame
	edit.insert_text_at_caret("x")
	edit.set_caret_line(1)
	await tree.process_frame
	check("session ended", session.active, false)
	check("value still copied", edit.get_line(0), "x x")

func test_choices_of_the_selected_parameter() -> void:
	var started := _start("{t|int,float} {u}")
	var session: TabStopSession = started[1]
	check("choices", session.current_choices(), PackedStringArray(["int", "float"]))
	check("position", session.current_position(), Vector2i(0, 0))
	check("index", session.current_choice_index(), 0)
	session.next()
	check("no choices on the next one", session.current_choices(), PackedStringArray())

func test_cycle_choice() -> void:
	var started := _start("{t|int,float,String}")
	var edit: CodeEdit = started[0]
	var session: TabStopSession = started[1]
	check("next", [session.cycle_choice(1), edit.text, edit.get_selected_text()], [true, "float", "float"])
	session.cycle_choice(1)
	check("last", edit.text, "String")
	session.cycle_choice(1)
	check("wraps around", edit.text, "int")
	session.cycle_choice(-1)
	check("previous wraps around", edit.text, "String")
	check("index", session.current_choice_index(), 2)

func test_cycle_from_a_typed_value() -> void:
	var started := _start("{t|int,float,String}")
	var edit: CodeEdit = started[0]
	var session: TabStopSession = started[1]
	edit.insert_text_at_caret("bool")
	check("not a choice", session.current_choice_index(), -1)
	session.cycle_choice(1)
	check("forward starts at the first", edit.text, "int")
	edit.insert_text_at_caret("bool")
	session.cycle_choice(-1)
	check("backward starts at the last", edit.text, "String")

func test_cycle_choice_without_choices() -> void:
	var started := _start("{a} {b|x,y}")
	var edit: CodeEdit = started[0]
	check("nothing to cycle", started[1].cycle_choice(1), false)
	check("text is the same", edit.text, "a x")

func test_choice_is_copied_and_the_next_stop_follows() -> void:
	var started := _start("{t|int,float,String} {u} {t}")
	var edit: CodeEdit = started[0]
	var session: TabStopSession = started[1]
	session.cycle_choice(1)
	session.cycle_choice(1)
	session.next()
	check("copied to the other place", edit.text, "String u String")
	check("the next parameter is in the right place", edit.get_selected_text(), "u")

func test_finished_is_emitted_once() -> void:
	var started := _start("{a} {b}")
	var session: TabStopSession = started[1]
	var count := [0]
	session.finished.connect(func(): count[0] += 1)
	session.next()
	check("not yet", count[0], 0)
	session.next()
	session.finish()
	check("once", count[0], 1)

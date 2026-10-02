@tool
extends RefCounted

# Puts an expanded template into a TextEdit.

const Expander = preload("res://addons/gdscript-templates/scripts/template_expander.gd")
const TabStopSession = preload("res://addons/gdscript-templates/scripts/tab_stop_session.gd")

# replaces the text from `from` to `to` (line, column) with the template body in one undo step,
# returns the tab stops of the template, null when there is nothing to tab through
static func insert(text_edit: TextEdit, body: String, from: Vector2i, to: Vector2i, params: Array = [], selection: String = "", variables: Dictionary = {}) -> TabStopSession:
	var indent := Expander.leading_whitespace(text_edit.get_line(from.x))
	var expanded := Expander.expand(body, params, indent, indent_unit(text_edit), selection, variables)

	text_edit.deselect()
	text_edit.begin_complex_operation()
	text_edit.remove_text(from.x, from.y, to.x, to.y)
	text_edit.insert_text(expanded.text, from.x, from.y)
	text_edit.end_complex_operation()

	var session := TabStopSession.new(text_edit, expanded, from.x, from.y)
	session.start()
	return session if session.active else null

# what a tab in the template becomes: spaces or a tab, as the editor is set
static func indent_unit(text_edit: TextEdit) -> String:
	if text_edit is CodeEdit and text_edit.indent_use_spaces:
		return " ".repeat(text_edit.indent_size)
	return "\t"

@tool
extends RefCounted

# Helpers for the panels drawn over the script (template browser, choices) and the code views of the dialog.

# the look of a panel: solid like a tooltip, with the accent color on the left
static func create_panel_style(text_edit: TextEdit) -> StyleBoxFlat:
	var scale := EditorInterface.get_editor_scale()
	var style := StyleBoxFlat.new()
	style.bg_color = _opaque_background(text_edit)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = int(10 * scale)
	style.border_color = EditorInterface.get_editor_theme().get_color("accent_color", "Editor")
	style.border_width_left = int(3 * scale)
	style.set_border_width(SIDE_TOP, 1)
	style.set_border_width(SIDE_BOTTOM, 1)
	style.set_content_margin_all(6 * scale)
	style.set_corner_radius_all(int(3 * scale))
	return style

# same font and zoom as the script
static func use_font_of(text_edit: TextEdit, controls: Array) -> void:
	for control in controls:
		control.add_theme_font_override("font", text_edit.get_theme_font("font"))
		control.add_theme_font_size_override("font_size", text_edit.get_theme_font_size("font_size"))

# top of a panel placed under a line whose bottom edge is at `line_pos_y` (get_pos_at_line_column()),
# above the line when there is no room below it
static func y_near_line(text_edit: TextEdit, line_pos_y: float, panel_height: float) -> float:
	var y := line_pos_y + 2.0
	var above := line_pos_y - text_edit.get_line_height() - panel_height - 2.0
	if y + panel_height > text_edit.size.y and above >= 0:
		return above
	return y

# GDScript syntax highlighting for a code view, null in an editor without GDScript
static func create_gdscript_highlighter() -> SyntaxHighlighter:
	if ClassDB.class_exists("GDScriptSyntaxHighlighter"):
		return ClassDB.instantiate("GDScriptSyntaxHighlighter")
	return null

# the script editor's background_color is often transparent
static func _opaque_background(text_edit: TextEdit) -> Color:
	var bg := text_edit.get_theme_color("background_color")
	if bg.a < 0.9:
		bg = EditorInterface.get_editor_theme().get_color("base_color", "Editor")
	bg.a = 1.0
	return bg.lightened(0.05)

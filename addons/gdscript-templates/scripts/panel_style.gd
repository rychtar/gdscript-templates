@tool
extends RefCounted

# The look of the panels drawn over the script (template browser, choices): solid like a tooltip,
# with the accent color on the left, in the font of the script.

static func create(text_edit: TextEdit) -> StyleBoxFlat:
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

# the script editor's background_color is often transparent
static func _opaque_background(text_edit: TextEdit) -> Color:
	var bg := text_edit.get_theme_color("background_color")
	if bg.a < 0.9:
		bg = EditorInterface.get_editor_theme().get_color("base_color", "Editor")
	bg.a = 1.0
	return bg.lightened(0.05)

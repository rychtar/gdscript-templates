@tool
extends PanelContainer

# The choices of a template parameter ({name|a,b,c}) under the selected parameter, drawn inside the script
# like the template browser. It doesn't take the focus: the keys go to the script and the plugin handles them,
# a click on a choice picks it.

signal choice_picked(index: int)

const PanelStyle = preload("res://addons/gdscript-templates/scripts/panel_style.gd")

var _text_edit: TextEdit
# line and column of the parameter
var _anchor := Vector2i.ZERO
var _list: ItemList

func _init() -> void:
	_list = ItemList.new()
	_list.focus_mode = Control.FOCUS_NONE
	_list.auto_height = true
	_list.item_selected.connect(func(index): choice_picked.emit(index))
	add_child(_list)

# shows the choices under the parameter at `anchor`, `current` is highlighted (-1 for none)
func show_choices(text_edit: TextEdit, anchor: Vector2i, choices: PackedStringArray, current: int) -> void:
	if _text_edit != text_edit:
		_text_edit = text_edit
		text_edit.add_child(self)
		add_theme_stylebox_override("panel", PanelStyle.create(text_edit))
		PanelStyle.use_font_of(text_edit, [_list])
	_anchor = anchor

	var font := text_edit.get_theme_font("font")
	var font_size := text_edit.get_theme_font_size("font_size")
	var width := 0.0
	_list.clear()
	for choice in choices:
		_list.add_item(choice)
		width = maxf(width, font.get_string_size(choice, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	_list.custom_minimum_size.x = width + 24 * EditorInterface.get_editor_scale()
	if current != -1:
		_list.select(current)
	_reposition()

func close() -> void:
	if not is_queued_for_deletion():
		queue_free()

# every frame: scrolling and resizing have no single signal to hook
func _process(_delta: float) -> void:
	_reposition()

# under the line of the parameter, above it when there is no room, hidden when scrolled out of view
func _reposition() -> void:
	if not is_instance_valid(_text_edit):
		return
	size = get_combined_minimum_size()
	var pos := _text_edit.get_pos_at_line_column(_anchor.x, _anchor.y)
	visible = pos.y >= 0
	if not visible:
		return
	var y := pos.y + 2.0
	var above := pos.y - _text_edit.get_line_height() - size.y - 2.0
	if y + size.y > _text_edit.size.y and above >= 0:
		y = above
	position = Vector2(clampf(pos.x, 0.0, maxf(_text_edit.size.x - size.x, 0.0)), y)

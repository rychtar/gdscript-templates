@tool
extends PopupPanel

# Template browser (Ctrl+Space)

signal template_chosen(keyword: String)
signal edit_requested

const Settings = preload("res://addons/gdscript-templates/scripts/settings.gd")
const Expander = preload("res://addons/gdscript-templates/scripts/template_expander.gd")

var _templates: Dictionary = {}
var _keys: Array[String] = []

var _search: LineEdit
var _list: ItemList
var _info: Label
var _preview: CodeEdit

func setup(templates: Dictionary, filter: String, popup_size: Vector2i) -> void:
	_templates = templates
	title = "GDScript Templates"
	borderless = false
	unresizable = false
	size = popup_size

	_build()
	_search.text = filter
	_refilter()

	popup_hide.connect(queue_free)

func _build() -> void:
	var editor_theme = EditorInterface.get_editor_theme()
	var scale = EditorInterface.get_editor_scale()
	var code_font = editor_theme.get_font("source", "EditorFonts")
	var code_font_size = editor_theme.get_font_size("source_size", "EditorFonts")
	theme = editor_theme

	var root = VBoxContainer.new()
	add_child(root)

	var top = HBoxContainer.new()
	root.add_child(top)

	_search = LineEdit.new()
	_search.placeholder_text = "Search templates..."
	_search.clear_button_enabled = true
	_search.right_icon = editor_theme.get_icon("Search", "EditorIcons")
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_text): _refilter())
	_search.text_submitted.connect(func(_text): _choose_selected())
	_search.gui_input.connect(_on_search_gui_input)
	top.add_child(_search)

	var edit_button = Button.new()
	edit_button.text = "Edit Templates..."
	edit_button.icon = editor_theme.get_icon("Edit", "EditorIcons")
	edit_button.focus_mode = Control.FOCUS_NONE
	edit_button.pressed.connect(func():
		hide()
		edit_requested.emit()
	)
	top.add_child(edit_button)

	var split = HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(220, 0) * scale
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_stretch_ratio = 0.7
	_list.add_theme_font_override("font", code_font)
	_list.add_theme_font_size_override("font_size", code_font_size)
	_list.item_selected.connect(_show_preview)
	_list.item_activated.connect(_choose)
	_list.gui_input.connect(_on_list_gui_input)
	split.add_child(_list)

	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)

	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_info)

	_preview = CodeEdit.new()
	_preview.editable = false
	_preview.focus_mode = Control.FOCUS_NONE
	_preview.context_menu_enabled = false
	_preview.custom_minimum_size = Vector2(300, 0) * scale
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.syntax_highlighter = Settings.create_gdscript_highlighter()
	_preview.add_theme_font_override("font", code_font)
	_preview.add_theme_font_size_override("font_size", code_font_size)
	right.add_child(_preview)

	var hint = Label.new()
	hint.text = "Enter / Tab: insert     ↑ ↓: select     Esc: close"
	hint.modulate.a = 0.6
	root.add_child(hint)

# opens below the caret, in the text edit's window (main or floating)
func popup_at_caret(text_edit: TextEdit) -> void:
	var parent_window = text_edit.get_window()
	parent_window.add_child(self)

	var caret_pos = text_edit.get_global_transform_with_canvas() * text_edit.get_caret_draw_pos()
	var popup_pos = Vector2i(caret_pos) + Vector2i(0, text_edit.get_line_height() / 2)

	# keep inside the screen, or the window when popups are embedded
	var embedded = parent_window.is_embedded() or parent_window.gui_embed_subwindows
	var bounds = Rect2i(Vector2i.ZERO, parent_window.size) if embedded \
		else DisplayServer.screen_get_usable_rect(parent_window.current_screen)
	var window_origin = Vector2i.ZERO if embedded else parent_window.position
	var abs_pos = window_origin + popup_pos
	var margin = 20
	abs_pos.x = clampi(abs_pos.x, bounds.position.x + margin, max(bounds.position.x + margin, bounds.end.x - size.x - margin))
	abs_pos.y = clampi(abs_pos.y, bounds.position.y + margin, max(bounds.position.y + margin, bounds.end.y - size.y - margin))

	popup_on_parent(Rect2i(abs_pos - window_origin, size))
	_search.grab_focus.call_deferred()
	_search.caret_column = _search.text.length()

func _refilter() -> void:
	var query = _search.text.strip_edges()
	var scored = []
	for keyword in _templates:
		var score = match_score(query, keyword, _templates[keyword].description)
		if score >= 0:
			scored.append([score, keyword])
	scored.sort_custom(func(a, b): return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])

	_list.clear()
	_keys.clear()
	for item in scored:
		var keyword: String = item[1]
		var params = Expander.get_params(_templates[keyword].body)
		var display = keyword
		if not params.is_empty():
			display += "  " + " ".join(Array(params).map(func(p): return "{%s}" % p))
		_keys.append(keyword)
		_list.add_item(display)
		_list.set_item_tooltip(_list.item_count - 1, _templates[keyword].description)

	if _keys.is_empty():
		_info.text = "No matching template."
		_preview.text = ""
	else:
		_select(0)

# higher is better, -1 = no match
static func match_score(query: String, keyword: String, description: String) -> int:
	if query.is_empty():
		return 0
	var q = query.to_lower()
	var k = keyword.to_lower()
	if k == q:
		return 1000
	if k.begins_with(q):
		return 900 - k.length()
	var index = k.find(q)
	if index != -1:
		return 700 - index
	var gaps = _subsequence_gaps(q, k)
	if gaps != -1:
		return 500 - gaps
	if description.to_lower().contains(q):
		return 100
	return -1

# number of skipped characters when query chars appear in order, -1 otherwise
static func _subsequence_gaps(query: String, text: String) -> int:
	var pos = 0
	var gaps = 0
	for c in query:
		var found = text.find(c, pos)
		if found == -1:
			return -1
		gaps += found - pos
		pos = found + 1
	return gaps

func _select(index: int) -> void:
	_list.select(index)
	_list.ensure_current_is_visible()
	_show_preview(index)

func _move_selection(step: int) -> void:
	if _keys.is_empty():
		return
	var selected = _list.get_selected_items()
	var index = selected[0] + step if selected.size() > 0 else 0
	_select(clampi(index, 0, _keys.size() - 1))

func _show_preview(index: int) -> void:
	var entry = _templates[_keys[index]]
	var info: String = entry.description
	var params = Expander.get_params(entry.body)
	if not params.is_empty():
		info += ("\n" if not info.is_empty() else "") + "Parameters: " + ", ".join(params)
	_info.text = info
	_preview.text = Expander.get_preview(entry.body)

func _choose(index: int) -> void:
	var keyword = _keys[index]
	template_chosen.emit(keyword)
	hide()

func _choose_selected() -> void:
	var selected = _list.get_selected_items()
	if selected.size() > 0:
		_choose(selected[0])

func _on_search_gui_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	match event.keycode:
		KEY_UP:
			_move_selection(-1)
		KEY_DOWN:
			_move_selection(1)
		KEY_PAGEUP:
			_move_selection(-10)
		KEY_PAGEDOWN:
			_move_selection(10)
		KEY_TAB:
			_choose_selected()
		_:
			return
	_search.accept_event()

func _on_list_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_list.accept_event()
		_choose_selected()

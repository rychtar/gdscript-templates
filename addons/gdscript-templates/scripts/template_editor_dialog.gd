@tool
extends ConfirmationDialog

# Template editor. A changed default template is saved as a user template
# with the same keyword, Revert removes it.

signal templates_saved(user_templates: Dictionary)

const Settings = preload("res://addons/gdscript-templates/scripts/settings.gd")
const TemplateStore = preload("res://addons/gdscript-templates/scripts/template_store.gd")

const KIND_DEFAULT = "default"
const KIND_MODIFIED = "modified"
const KIND_CUSTOM = "custom"

var _defaults: Dictionary = {}
var _user: Dictionary = {}
var _use_defaults: bool = true
var _keys: Array[String] = []
var _selected: String = ""
var _updating: bool = false

var _search: LineEdit
var _list: ItemList
var _duplicate_button: Button
var _remove_button: Button
var _details: Control
var _keyword: LineEdit
var _keyword_error: Label
var _description: LineEdit
var _status: Label
var _body: CodeEdit

func setup(defaults: Dictionary, user: Dictionary, use_defaults: bool) -> void:
	_defaults = defaults
	_user = user.duplicate(true)
	_use_defaults = use_defaults

	title = "GDScript Templates"
	ok_button_text = "Save"
	add_button("Show File", true, "show_file")

	_build()
	_refresh_list()

	confirmed.connect(func(): templates_saved.emit(_user))
	custom_action.connect(_on_custom_action)
	visibility_changed.connect(func():
		if not visible:
			queue_free()
	)

# window = null opens the dialog in the main editor window
func show_dialog(window: Window = null) -> void:
	var dialog_size = Vector2i(Vector2(1000, 640) * EditorInterface.get_editor_scale())
	if window and window != EditorInterface.get_base_control().get_window():
		window.add_child(self)
		popup_centered(dialog_size)
	else:
		EditorInterface.popup_dialog_centered(self, dialog_size)

func _build() -> void:
	var editor_theme = EditorInterface.get_editor_theme()
	var scale = EditorInterface.get_editor_scale()
	var code_font = editor_theme.get_font("source", "EditorFonts")
	var code_font_size = editor_theme.get_font_size("source_size", "EditorFonts")

	var split = HSplitContainer.new()
	add_child(split)

	var left = VBoxContainer.new()
	left.custom_minimum_size = Vector2(240, 0) * scale
	split.add_child(left)

	_search = LineEdit.new()
	_search.placeholder_text = "Filter templates"
	_search.clear_button_enabled = true
	_search.right_icon = editor_theme.get_icon("Search", "EditorIcons")
	_search.text_changed.connect(func(_text): _refresh_list())
	left.add_child(_search)

	if not _use_defaults:
		var defaults_off = Label.new()
		defaults_off.text = "Default templates are disabled in Editor Settings."
		defaults_off.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		defaults_off.modulate.a = 0.6
		left.add_child(defaults_off)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_font_override("font", code_font)
	_list.add_theme_font_size_override("font_size", code_font_size)
	_list.item_selected.connect(func(index): _load(_keys[index]))
	left.add_child(_list)

	var buttons = HBoxContainer.new()
	left.add_child(buttons)
	buttons.add_child(_create_button("Add", "Add", _on_add_pressed))
	_duplicate_button = _create_button("Duplicate", "Duplicate", _on_duplicate_pressed)
	buttons.add_child(_duplicate_button)
	_remove_button = _create_button("Delete", "Remove", _on_remove_pressed)
	buttons.add_child(_remove_button)

	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	_details = right

	var grid = GridContainer.new()
	grid.columns = 2
	right.add_child(grid)

	grid.add_child(_create_label("Keyword"))
	_keyword = LineEdit.new()
	_keyword.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_keyword.text_changed.connect(_on_keyword_changed)
	grid.add_child(_keyword)

	grid.add_child(Control.new())
	_keyword_error = Label.new()
	_keyword_error.add_theme_color_override("font_color", editor_theme.get_color("error_color", "Editor"))
	grid.add_child(_keyword_error)

	grid.add_child(_create_label("Description"))
	_description = LineEdit.new()
	_description.placeholder_text = "Optional, shown in the templates popup"
	_description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_description.text_changed.connect(func(_text): _on_entry_changed())
	grid.add_child(_description)

	_status = Label.new()
	_status.modulate.a = 0.6
	right.add_child(_status)

	_body = CodeEdit.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.gutters_draw_line_numbers = true
	_body.indent_use_spaces = false
	_body.syntax_highlighter = Settings.create_gdscript_highlighter()
	_body.add_theme_font_override("font", code_font)
	_body.add_theme_font_size_override("font_size", code_font_size)
	_body.text_changed.connect(_on_entry_changed)
	right.add_child(_body)

	var help = Label.new()
	help.text = "{name} - parameter, filled from words typed after the keyword or selected with Tab after expansion\n" \
		+ "|CURSOR| - caret position after expansion\n" \
		+ "Options and shortcuts: Editor Settings > Plugins > GDScript Templates (enable Advanced Settings)"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.modulate.a = 0.6
	right.add_child(help)

func _create_button(text: String, icon_name: String, callback: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.icon = EditorInterface.get_editor_theme().get_icon(icon_name, "EditorIcons")
	button.pressed.connect(callback)
	return button

func _create_label(text: String) -> Label:
	var label = Label.new()
	label.text = text
	return label

func _exists(keyword: String) -> bool:
	return _user.has(keyword) or (_use_defaults and _defaults.has(keyword))

func _kind(keyword: String) -> String:
	var is_default = _use_defaults and _defaults.has(keyword)
	if not _user.has(keyword):
		return KIND_DEFAULT
	return KIND_MODIFIED if is_default else KIND_CUSTOM

func _get_entry(keyword: String) -> Dictionary:
	return _user[keyword] if _user.has(keyword) else _defaults[keyword]

func _item_text(keyword: String) -> String:
	match _kind(keyword):
		KIND_MODIFIED:
			return keyword + "   (modified)"
		KIND_CUSTOM:
			return keyword + "   (custom)"
	return keyword

func _refresh_list(select_keyword: String = _selected) -> void:
	var query = _search.text.strip_edges().to_lower()
	var all_keys = _user.keys()
	if _use_defaults:
		for keyword in _defaults:
			if not _user.has(keyword):
				all_keys.append(keyword)

	_keys.clear()
	for keyword in all_keys:
		if query.is_empty() or keyword.to_lower().contains(query) or _get_entry(keyword).description.to_lower().contains(query):
			_keys.append(keyword)
	_keys.sort()

	_list.clear()
	for keyword in _keys:
		_list.add_item(_item_text(keyword))

	var index = _keys.find(select_keyword)
	if index == -1 and not _keys.is_empty():
		index = 0
	if index == -1:
		_load("")
	else:
		_list.select(index)
		_list.ensure_current_is_visible()
		_load(_keys[index])

func _load(keyword: String) -> void:
	_updating = true
	_selected = keyword
	_details.visible = not keyword.is_empty()
	_keyword_error.text = ""

	if not keyword.is_empty():
		var entry = _get_entry(keyword)
		_keyword.text = keyword
		_description.text = entry.description
		_body.text = entry.body
		_body.clear_undo_history()

	_update_state()
	_updating = false

func _update_state() -> void:
	var kind = _kind(_selected) if not _selected.is_empty() else ""
	_keyword.editable = kind == KIND_CUSTOM
	match kind:
		KIND_DEFAULT:
			_status.text = "Default template - your changes are saved as your own version."
		KIND_MODIFIED:
			_status.text = "Modified default template - use Revert to restore the original."
		KIND_CUSTOM:
			_status.text = "Custom template."

	var is_modified = kind == KIND_MODIFIED
	_remove_button.text = "Revert" if is_modified else "Delete"
	_remove_button.icon = EditorInterface.get_editor_theme().get_icon("Reload" if is_modified else "Remove", "EditorIcons")
	_remove_button.disabled = kind != KIND_MODIFIED and kind != KIND_CUSTOM
	_duplicate_button.disabled = _selected.is_empty()

	var index = _keys.find(_selected)
	if index != -1:
		_list.set_item_text(index, _item_text(_selected))

func _on_entry_changed() -> void:
	if _updating or _selected.is_empty():
		return
	var entry = {"body": _body.text, "description": _description.text.strip_edges()}
	if _use_defaults and _defaults.has(_selected) and _defaults[_selected] == entry:
		_user.erase(_selected)
	else:
		_user[_selected] = entry
	_update_state()

func _on_keyword_changed(new_text: String) -> void:
	if _updating or _selected.is_empty():
		return
	var keyword = new_text.strip_edges()
	var error = _validate_keyword(keyword)
	_keyword_error.text = error
	if not error.is_empty() or keyword == _selected:
		return

	var entry = _user[_selected]
	_user.erase(_selected)
	_user[keyword] = entry
	_keys[_keys.find(_selected)] = keyword
	_selected = keyword
	_update_state()

func _validate_keyword(keyword: String) -> String:
	if keyword.is_empty():
		return "Keyword can't be empty."
	if RegEx.create_from_string("\\s").search(keyword):
		return "Keyword can't contain spaces."
	if keyword != _selected and _exists(keyword):
		return "Template \"%s\" already exists." % keyword
	return ""

func _unique_keyword(base: String) -> String:
	if not _exists(base):
		return base
	var i = 2
	while _exists("%s_%d" % [base, i]):
		i += 1
	return "%s_%d" % [base, i]

func _on_add_pressed() -> void:
	var keyword = _unique_keyword("new_template")
	_user[keyword] = {"body": "|CURSOR|", "description": ""}
	_search.text = ""
	_refresh_list(keyword)
	_keyword.grab_focus()
	_keyword.select_all()

func _on_duplicate_pressed() -> void:
	if _selected.is_empty():
		return
	var keyword = _unique_keyword(_selected + "_copy")
	_user[keyword] = _get_entry(_selected).duplicate()
	_search.text = ""
	_refresh_list(keyword)
	_keyword.grab_focus()
	_keyword.select_all()

func _on_remove_pressed() -> void:
	if not _user.has(_selected):
		return
	var kind = _kind(_selected)
	var index = _keys.find(_selected)
	_user.erase(_selected)
	if kind == KIND_MODIFIED:
		_refresh_list(_selected)
	else:
		_keys.remove_at(index)
		_refresh_list(_keys[mini(index, _keys.size() - 1)] if not _keys.is_empty() else "")

func _on_custom_action(action: StringName) -> void:
	if action == "show_file":
		var path = TemplateStore.get_user_path()
		OS.shell_show_in_file_manager(path if FileAccess.file_exists(path) else path.get_base_dir())

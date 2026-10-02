@tool
extends ConfirmationDialog

# Template editor. A changed default template is saved as a user template
# with the same keyword, Revert removes it. User templates are available in all projects
# or only in this one (project templates).

signal templates_saved(user_templates: Dictionary, project_templates: Dictionary)

const Settings = preload("res://addons/gdscript-templates/scripts/settings.gd")
const TemplateStore = preload("res://addons/gdscript-templates/scripts/template_store.gd")
const Expander = preload("res://addons/gdscript-templates/scripts/template_expander.gd")

const KIND_DEFAULT = "default"
const KIND_MODIFIED = "modified"
const KIND_CUSTOM = "custom"

const SCOPE_ALL = 0
const SCOPE_PROJECT = 1

# size of the dialog at the editor scale 1
const DIALOG_SIZE = Vector2(920, 520)

# shown in the preview of templates with {selection}
const SAMPLE_SELECTION = "# selected code"

var _defaults: Dictionary = {}
var _user: Dictionary = {}
var _project: Dictionary = {}
# templates when opened, to detect unsaved changes
var _saved_user: Dictionary = {}
var _saved_project: Dictionary = {}
var _confirm_discard: bool = false
var _use_defaults: bool = true
# values of {@name} in the preview
var _variables: Dictionary = {}
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
var _keyword_error_spacer: Control
var _add_button: Button
var _help_button: Button
var _help_popup: PopupPanel
var _description: LineEdit
var _category: LineEdit
var _category_menu: MenuButton
var _scope: OptionButton
var _status: Label
var _body: CodeEdit
var _preview: CodeEdit
var _params_info: Label

func setup(defaults: Dictionary, user: Dictionary, project: Dictionary, use_defaults: bool, variables: Dictionary = {}) -> void:
	_defaults = defaults
	_user = user.duplicate(true)
	_project = project.duplicate(true)
	_saved_user = user.duplicate(true)
	_saved_project = project.duplicate(true)
	_use_defaults = use_defaults
	_variables = variables

	title = "GDScript Templates"
	ok_button_text = "Save"
	add_button("Show File", true, "show_file")

	_build()
	_refresh_list()

	confirmed.connect(func(): templates_saved.emit(_user, _project))
	custom_action.connect(_on_custom_action)
	# Cancel, Esc and the close button all emit canceled before the dialog hides
	canceled.connect(func(): _confirm_discard = _user != _saved_user or _project != _saved_project)
	visibility_changed.connect(func():
		if visible:
			return
		if _confirm_discard:
			_confirm_discard = false
			# deferred: the window is still the exclusive child while it's hiding
			_ask_to_save.call_deferred()
		else:
			queue_free()
	)

# window = null opens the dialog in the main editor window
func show_dialog(window: Window = null) -> void:
	var dialog_size := Vector2i(DIALOG_SIZE * EditorInterface.get_editor_scale())
	if window and window != EditorInterface.get_base_control().get_window():
		window.add_child(self)
		popup_centered(dialog_size)
	else:
		EditorInterface.popup_dialog_centered(self, dialog_size)

# the dialog is already hidden, Keep Editing opens it again
func _ask_to_save() -> void:
	var ask := ConfirmationDialog.new()
	ask.title = "Unsaved Changes"
	ask.dialog_text = "Save changes to the templates before closing?"
	ask.ok_button_text = "Save"
	ask.cancel_button_text = "Keep Editing"
	ask.add_button("Discard", true, "discard")
	ask.confirmed.connect(func():
		templates_saved.emit(_user, _project)
		queue_free()
	)
	ask.custom_action.connect(func(_action):
		ask.hide()
		queue_free()
	)
	# deferred: the question hides deferred too, only one exclusive dialog at a time
	ask.canceled.connect(func(): popup.call_deferred())
	ask.visibility_changed.connect(func():
		if not ask.visible:
			ask.queue_free()
	)
	get_parent().add_child(ask)
	ask.popup_centered()

func _build() -> void:
	var split := HSplitContainer.new()
	add_child(split)
	split.add_child(_build_list_panel())

	_details = VBoxContainer.new()
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(_details)
	_details.add_child(_build_fields())

	_status = Label.new()
	_status.modulate.a = 0.6
	_details.add_child(_status)

	_details.add_child(_build_editors())

	_params_info = Label.new()
	_params_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.add_child(_params_info)
	_details.add_child(_build_help())

# the search, the list of templates and the buttons under it
func _build_list_panel() -> Control:
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(240, 0) * EditorInterface.get_editor_scale()

	_search = LineEdit.new()
	_search.placeholder_text = "Filter templates"
	_search.clear_button_enabled = true
	_search.right_icon = EditorInterface.get_editor_theme().get_icon("Search", "EditorIcons")
	_search.text_changed.connect(func(_text): _refresh_list())
	left.add_child(_search)

	if not _use_defaults:
		var defaults_off := Label.new()
		defaults_off.text = "Default templates are disabled in Editor Settings."
		defaults_off.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		defaults_off.modulate.a = 0.6
		left.add_child(defaults_off)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_use_code_font(_list)
	_list.item_selected.connect(func(index): _load(_keys[index]))
	left.add_child(_list)

	var buttons := HBoxContainer.new()
	left.add_child(buttons)
	_add_button = _create_button("Add", "Add", _on_add_pressed)
	buttons.add_child(_add_button)
	_duplicate_button = _create_button("Duplicate", "Duplicate", _on_duplicate_pressed)
	buttons.add_child(_duplicate_button)
	_remove_button = _create_button("Delete", "Remove", _on_remove_pressed)
	buttons.add_child(_remove_button)
	return left

# keyword, description, category and where the template is available
func _build_fields() -> Control:
	var editor_theme := EditorInterface.get_editor_theme()
	var grid := GridContainer.new()
	grid.columns = 2

	grid.add_child(_create_label("Keyword"))
	_keyword = LineEdit.new()
	_keyword.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_keyword.text_changed.connect(_on_keyword_changed)
	grid.add_child(_keyword)

	_keyword_error_spacer = Control.new()
	grid.add_child(_keyword_error_spacer)
	_keyword_error = Label.new()
	_keyword_error.add_theme_color_override("font_color", editor_theme.get_color("error_color", "Editor"))
	grid.add_child(_keyword_error)
	_set_keyword_error("")

	grid.add_child(_create_label("Description"))
	_description = LineEdit.new()
	_description.placeholder_text = "Optional, shown in the templates popup"
	_description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_description.text_changed.connect(func(_text): _on_entry_changed())
	grid.add_child(_description)

	grid.add_child(_create_label("Category"))
	var category_row := HBoxContainer.new()
	category_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(category_row)
	_category = LineEdit.new()
	_category.placeholder_text = "Optional, groups the templates in the templates popup"
	_category.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_category.text_changed.connect(func(_text): _on_entry_changed())
	category_row.add_child(_category)
	# pick one of the existing categories
	_category_menu = MenuButton.new()
	_category_menu.icon = editor_theme.get_icon("GuiDropdown", "EditorIcons")
	_category_menu.tooltip_text = "Existing categories"
	_category_menu.flat = true
	_category_menu.about_to_popup.connect(_fill_category_menu)
	_category_menu.get_popup().index_pressed.connect(func(index):
		_category.text = _category_menu.get_popup().get_item_text(index)
		_on_entry_changed()
	)
	category_row.add_child(_category_menu)

	grid.add_child(_create_label("Available in"))
	_scope = OptionButton.new()
	_scope.add_item("All projects", SCOPE_ALL)
	_scope.add_item("This project only", SCOPE_PROJECT)
	_scope.tooltip_text = "Project templates are saved to %s, you can commit it and share it with your team." % TemplateStore.PROJECT_PATH
	_scope.item_selected.connect(_on_scope_selected)
	grid.add_child(_scope)
	return grid

# the template and what it expands to, the divider is movable
func _build_editors() -> Control:
	var scale := EditorInterface.get_editor_scale()
	var editors := VSplitContainer.new()
	editors.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_body = CodeEdit.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.custom_minimum_size = Vector2(0, 90) * scale
	_body.gutters_draw_line_numbers = true
	_body.indent_use_spaces = false
	_body.syntax_highlighter = Settings.create_gdscript_highlighter()
	_use_code_font(_body)
	_body.text_changed.connect(_on_entry_changed)
	editors.add_child(_body)

	var preview_box := VBoxContainer.new()
	preview_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editors.add_child(preview_box)
	var preview_title := _create_label("Preview")
	preview_title.modulate.a = 0.6
	preview_box.add_child(preview_title)
	_preview = CodeEdit.new()
	_preview.editable = false
	_preview.focus_mode = Control.FOCUS_NONE
	_preview.context_menu_enabled = false
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.custom_minimum_size = Vector2(0, 60) * scale
	_preview.syntax_highlighter = Settings.create_gdscript_highlighter()
	_use_code_font(_preview)
	preview_box.add_child(_preview)
	return editors

# the syntax reference opens in a small panel above the button, so the dialog keeps its size
func _build_help() -> Control:
	_help_button = Button.new()
	_help_button.text = "Template syntax"
	var editor_theme := EditorInterface.get_editor_theme()
	_help_button.icon = editor_theme.get_icon("NodeInfo" if editor_theme.has_icon("NodeInfo", "EditorIcons") else "Help", "EditorIcons")
	_help_button.flat = true
	_help_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_help_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_help_button.pressed.connect(_show_help)

	_help_popup = _build_help_popup()
	add_child(_help_popup)
	return _help_button

func _build_help_popup() -> PopupPanel:
	var scale := EditorInterface.get_editor_scale()
	var editor_theme := EditorInterface.get_editor_theme()

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(10 * scale))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(6 * scale))
	margin.add_child(box)

	var title := Label.new()
	title.text = "Template syntax"
	title.add_theme_color_override("font_color", editor_theme.get_color("accent_color", "Editor"))
	box.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", int(18 * scale))
	box.add_child(grid)
	for row in [
		["{name}", "parameter, filled from the words after the keyword"],
		["{name=value}", "parameter with a default value"],
		["{name|a,b,c}", "parameter with choices, the first is the default"],
		["{selection}", "the selected code"],
		["{@filename}", "file name of the script"],
		["{@class}", "the same as a class name (PlayerController)"],
		["{@date}", "today's date"],
		["|CURSOR|", "caret position after expansion"],
	]:
		var syntax := Label.new()
		syntax.text = row[0]
		_use_code_font(syntax)
		grid.add_child(syntax)
		var meaning := Label.new()
		meaning.text = row[1]
		meaning.modulate.a = 0.7
		grid.add_child(meaning)

	var more := Label.new()
	more.text = "Shortcuts: Editor Settings > Plugins > GDScript Templates"
	more.modulate.a = 0.5
	box.add_child(more)

	# a frame so the panel doesn't blend into the dialog
	var style := StyleBoxFlat.new()
	style.bg_color = editor_theme.get_color("base_color", "Editor").lightened(0.06)
	style.border_color = editor_theme.get_color("accent_color", "Editor")
	style.set_border_width_all(1)
	style.border_width_left = int(3 * scale)
	style.set_corner_radius_all(int(3 * scale))
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = int(8 * scale)

	var popup := PopupPanel.new()
	popup.add_theme_stylebox_override("panel", style)
	popup.add_child(margin)
	return popup

# above the button, as far left as it fits in the dialog
func _show_help() -> void:
	var help_size := Vector2i(_help_popup.get_contents_minimum_size())
	var button_rect := Rect2i(_help_button.get_global_rect())
	var left := clampi(button_rect.position.x, 0, maxi(size.x - help_size.x, 0))
	var top := maxi(button_rect.position.y - help_size.y - 4, 0)
	_help_popup.popup_on_parent(Rect2i(Vector2i(left, top), help_size))

# the font of the script editor
func _use_code_font(control: Control) -> void:
	var editor_theme := EditorInterface.get_editor_theme()
	control.add_theme_font_override("font", editor_theme.get_font("source", "EditorFonts"))
	control.add_theme_font_size_override("font_size", editor_theme.get_font_size("source_size", "EditorFonts"))

func _create_button(text: String, icon_name: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.icon = EditorInterface.get_editor_theme().get_icon(icon_name, "EditorIcons")
	button.pressed.connect(callback)
	return button

func _create_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label

# user or project template (a new one, or a changed default)
func _is_own(keyword: String) -> bool:
	return _user.has(keyword) or _project.has(keyword)

# where the template is saved - project templates override user ones
func _own_templates(keyword: String) -> Dictionary:
	return _project if _project.has(keyword) else _user

func _exists(keyword: String) -> bool:
	return _is_own(keyword) or (_use_defaults and _defaults.has(keyword))

func _kind(keyword: String) -> String:
	var is_default := _use_defaults and _defaults.has(keyword)
	if not _is_own(keyword):
		return KIND_DEFAULT
	return KIND_MODIFIED if is_default else KIND_CUSTOM

func _get_entry(keyword: String) -> Dictionary:
	return _own_templates(keyword)[keyword] if _is_own(keyword) else _defaults[keyword]

func _item_text(keyword: String) -> String:
	var tags := PackedStringArray()
	match _kind(keyword):
		KIND_MODIFIED:
			tags.append("modified")
		KIND_CUSTOM:
			tags.append("custom")
	if _project.has(keyword):
		tags.append("project")
	return keyword + ("   (%s)" % ", ".join(tags) if not tags.is_empty() else "")

func _refresh_list(select_keyword: String = _selected) -> void:
	var query := _search.text.strip_edges().to_lower()
	var all_keys := {}
	if _use_defaults:
		all_keys.merge(_defaults)
	all_keys.merge(_user)
	all_keys.merge(_project)

	_keys.clear()
	for keyword in all_keys:
		var entry := _get_entry(keyword)
		if query.is_empty() or keyword.to_lower().contains(query) or entry.description.to_lower().contains(query) \
				or entry.category.to_lower().contains(query):
			_keys.append(keyword)
	_keys.sort()

	_list.clear()
	for keyword in _keys:
		_list.add_item(_item_text(keyword))

	var index := _keys.find(select_keyword)
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
	_set_keyword_error("")

	if keyword.is_empty():
		_keyword.text = ""
		_description.text = ""
		_category.text = ""
		_body.text = ""
	else:
		var entry := _get_entry(keyword)
		_keyword.text = keyword
		_description.text = entry.description
		_category.text = entry.category
		# changed before 1.4 - offer the original category
		if entry.category.is_empty() and _use_defaults and _defaults.has(keyword):
			_category.text = _defaults[keyword].category
		_body.text = entry.body
		_body.clear_undo_history()

	_update_state()
	_updating = false

func _update_state() -> void:
	var has_selection := not _selected.is_empty()
	var kind := _kind(_selected) if has_selection else ""
	# nothing selected (no match, no templates): the fields stay, empty and locked
	_keyword.editable = kind == KIND_CUSTOM
	_description.editable = has_selection
	_category.editable = has_selection
	_category_menu.disabled = not has_selection
	_body.editable = has_selection
	match kind:
		KIND_DEFAULT:
			_status.text = "Default template - your changes are saved as your own version."
		KIND_MODIFIED:
			_status.text = "Modified default template - use Revert to restore the original."
		KIND_CUSTOM:
			_status.text = "Custom template."
		_:
			var query := _search.text.strip_edges()
			_status.text = ("No template matches \"%s\". " % query if not query.is_empty() else "No templates. ") \
				+ "Click Add to create one."
	_highlight_add_button(not has_selection)

	# a default template gets a scope when it's changed
	_scope.disabled = kind == KIND_DEFAULT or not has_selection
	_scope.select(SCOPE_PROJECT if _project.has(_selected) else SCOPE_ALL)
	_update_params_info()

	var is_modified := kind == KIND_MODIFIED
	_remove_button.text = "Revert" if is_modified else "Delete"
	_remove_button.icon = EditorInterface.get_editor_theme().get_icon("Reload" if is_modified else "Remove", "EditorIcons")
	_remove_button.disabled = kind != KIND_MODIFIED and kind != KIND_CUSTOM
	_duplicate_button.disabled = _selected.is_empty()

	var index := _keys.find(_selected)
	if index != -1:
		_list.set_item_text(index, _item_text(_selected))

# the empty line under the keyword only takes room when there is an error to show
func _set_keyword_error(text: String) -> void:
	_keyword_error.text = text
	_keyword_error.visible = not text.is_empty()
	_keyword_error_spacer.visible = not text.is_empty()

# points at Add when there is nothing to edit
func _highlight_add_button(on: bool) -> void:
	var states := ["normal", "hover", "pressed"]
	if not on:
		for state in states:
			_add_button.remove_theme_stylebox_override(state)
		return
	var editor_theme := EditorInterface.get_editor_theme()
	var accent := editor_theme.get_color("accent_color", "Editor")
	var colors := {"normal": accent.darkened(0.3), "hover": accent, "pressed": accent.darkened(0.5)}
	for state in states:
		var style := editor_theme.get_stylebox(state, "Button").duplicate()
		if style is StyleBoxFlat:
			style.bg_color = colors[state]
		_add_button.add_theme_stylebox_override(state, style)

func _fill_category_menu() -> void:
	var categories := PackedStringArray()
	for templates in [_defaults, _user, _project]:
		for keyword in templates:
			var category: String = templates[keyword].category
			if not category.is_empty() and not categories.has(category):
				categories.append(category)
	var menu := _category_menu.get_popup()
	menu.clear()
	for category in categories:
		menu.add_item(category)

func _update_params_info() -> void:
	var body := _body.text
	var described := Expander.describe_params(body)
	var lines := PackedStringArray(["Parameters: " + (", ".join(described) if not described.is_empty() else "none")])
	if Expander.uses_selection(body):
		lines.append("Wraps the selected code.")
	_params_info.text = "\n".join(lines)
	_preview.text = Expander.get_preview(body, [], SAMPLE_SELECTION, _variables)

func _on_entry_changed() -> void:
	if _updating or _selected.is_empty():
		return
	var entry := {"body": _body.text, "description": _description.text.strip_edges(), "category": _category.text.strip_edges()}
	var own := _own_templates(_selected)
	if _use_defaults and _defaults.has(_selected) and _defaults[_selected] == entry:
		own.erase(_selected)
	else:
		own[_selected] = entry
	_update_state()

func _on_scope_selected(index: int) -> void:
	if _updating or not _is_own(_selected):
		return
	var from := _own_templates(_selected)
	var to := _project if _scope.get_item_id(index) == SCOPE_PROJECT else _user
	if is_same(from, to):
		return
	# don't overwrite the template that is already there
	if to.has(_selected):
		_set_keyword_error("\"%s\" already exists in \"%s\"." % [_selected, _scope.get_item_text(index)])
		_scope.select(SCOPE_PROJECT if is_same(from, _project) else SCOPE_ALL)
		return
	_set_keyword_error("")
	to[_selected] = from[_selected]
	from.erase(_selected)
	_update_state()

func _on_keyword_changed(new_text: String) -> void:
	if _updating or _selected.is_empty():
		return
	var keyword := new_text.strip_edges()
	var error := _validate_keyword(keyword)
	_set_keyword_error(error)
	if not error.is_empty() or keyword == _selected:
		return

	var own := _own_templates(_selected)
	var entry: Dictionary = own[_selected]
	own.erase(_selected)
	own[keyword] = entry
	_keys[_keys.find(_selected)] = keyword
	_selected = keyword
	_update_state()

func _validate_keyword(keyword: String) -> String:
	if keyword.is_empty():
		return "Keyword can't be empty."
	if keyword.contains(" ") or keyword.contains("\t"):
		return "Keyword can't contain spaces."
	if keyword != _selected and _exists(keyword):
		return "Template \"%s\" already exists." % keyword
	return ""

func _unique_keyword(base: String) -> String:
	if not _exists(base):
		return base
	var i := 2
	while _exists("%s_%d" % [base, i]):
		i += 1
	return "%s_%d" % [base, i]

func _on_add_pressed() -> void:
	var keyword := _unique_keyword("new_template")
	_user[keyword] = {"body": "|CURSOR|", "description": "", "category": ""}
	_show_new_template(keyword)

func _on_duplicate_pressed() -> void:
	if _selected.is_empty():
		return
	var keyword := _unique_keyword(_selected + "_copy")
	# a copy of a project template stays in the project
	_own_templates(_selected)[keyword] = _get_entry(_selected).duplicate()
	_show_new_template(keyword)

# selects the new template and puts the caret in its keyword
func _show_new_template(keyword: String) -> void:
	_search.text = ""
	_refresh_list(keyword)
	_keyword.grab_focus()
	_keyword.select_all()

func _on_remove_pressed() -> void:
	if not _is_own(_selected):
		return
	var index := _keys.find(_selected)
	_own_templates(_selected).erase(_selected)
	# a reverted default, or a user template that was overridden by a project one
	if _exists(_selected):
		_refresh_list(_selected)
	else:
		_keys.remove_at(index)
		_refresh_list(_keys[mini(index, _keys.size() - 1)] if not _keys.is_empty() else "")

func _on_custom_action(action: StringName) -> void:
	if action == "show_file":
		var path := TemplateStore.get_project_path() if _project.has(_selected) else TemplateStore.get_user_path()
		OS.shell_show_in_file_manager(path if FileAccess.file_exists(path) else path.get_base_dir())

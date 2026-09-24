@tool
extends EditorPlugin

const Debug = preload("res://addons/gdscript-templates/scripts/debug_utils.gd")
const Settings = preload("res://addons/gdscript-templates/scripts/settings.gd")
const TemplateStore = preload("res://addons/gdscript-templates/scripts/template_store.gd")
const TemplateExpander = preload("res://addons/gdscript-templates/scripts/template_expander.gd")
const TabStopSession = preload("res://addons/gdscript-templates/scripts/tab_stop_session.gd")
const CompletionPopup = preload("res://addons/gdscript-templates/scripts/completion_popup.gd")
const TemplateEditorDialog = preload("res://addons/gdscript-templates/scripts/template_editor_dialog.gd")

const TOOL_MENU_ITEM = "GDScript Templates..."
# 1.0 menu item, left behind when updating without editor restart
const LEGACY_TOOL_MENU_ITEM = "GDScript Templates Settings"

var store: TemplateStore
var session: TabStopSession
var hooked_text_edits: Dictionary = {}

func _enter_tree():

	Settings.register()
	store = TemplateStore.new()
	store.use_defaults = Settings.use_default_templates()
	store.load_templates()
	EditorInterface.get_editor_settings().settings_changed.connect(_on_editor_settings_changed)

	remove_tool_menu_item(LEGACY_TOOL_MENU_ITEM)
	add_tool_menu_item(TOOL_MENU_ITEM, _open_template_editor)

	# _input() doesn't get events from the floating script editor, so hook the text edit directly
	var script_editor = EditorInterface.get_script_editor()
	script_editor.editor_script_changed.connect(_on_editor_script_changed)
	_hook_current_text_edit()

	Debug.info("✓ GDScript Templates Plugin activated")

func _exit_tree():
	remove_tool_menu_item(TOOL_MENU_ITEM)

	var editor_settings = EditorInterface.get_editor_settings()
	if editor_settings.settings_changed.is_connected(_on_editor_settings_changed):
		editor_settings.settings_changed.disconnect(_on_editor_settings_changed)

	var script_editor = EditorInterface.get_script_editor()
	if script_editor.editor_script_changed.is_connected(_on_editor_script_changed):
		script_editor.editor_script_changed.disconnect(_on_editor_script_changed)

	for text_edit in hooked_text_edits.values():
		if is_instance_valid(text_edit) and text_edit.gui_input.is_connected(_on_text_edit_gui_input):
			text_edit.gui_input.disconnect(_on_text_edit_gui_input)
	hooked_text_edits.clear()
	session = null

func _on_editor_settings_changed():
	var use_defaults = Settings.use_default_templates()
	if use_defaults != store.use_defaults:
		store.use_defaults = use_defaults
		store.rebuild()

func _on_editor_script_changed(_script):
	_hook_current_text_edit()

func _hook_current_text_edit():
	var text_edit = get_current_script_editor()
	if not text_edit or text_edit.gui_input.is_connected(_on_text_edit_gui_input):
		return
	text_edit.gui_input.connect(_on_text_edit_gui_input.bind(text_edit))
	hooked_text_edits[text_edit.get_instance_id()] = text_edit
	text_edit.tree_exited.connect(func(): hooked_text_edits.erase(text_edit.get_instance_id()), CONNECT_ONE_SHOT)

# gui_input is emitted before CodeEdit handles the event, accept_event() blocks the default action
func _on_text_edit_gui_input(event: InputEvent, text_edit: TextEdit):
	if not (event is InputEventKey and event.pressed):
		return

	if session and session.active and session.text_edit == text_edit:
		if event.keycode == KEY_TAB and not _has_modifiers(event) and not _is_code_completion_active(text_edit):
			if session.next():
				text_edit.accept_event()
				_cancel_code_completion_later(text_edit)
			return
		elif event.keycode == KEY_ESCAPE:
			session.finish()

	if event.echo:
		return

	if Settings.matches_shortcut(Settings.SHORTCUT_EXPAND, event):
		text_edit.accept_event()
		expand_template_at_caret(text_edit)
	elif Settings.matches_shortcut(Settings.SHORTCUT_SHOW, event):
		text_edit.accept_event()
		show_templates_popup(text_edit)

func _has_modifiers(event: InputEventKey) -> bool:
	return event.shift_pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed

func _is_code_completion_active(text_edit: TextEdit) -> bool:
	return text_edit is CodeEdit and text_edit.get_code_completion_selected_index() != -1

func _cancel_code_completion_later(text_edit: TextEdit):
	await get_tree().process_frame
	if is_instance_valid(text_edit) and text_edit is CodeEdit:
		text_edit.cancel_code_completion()

# finds "keyword param1 param2" before the caret, last known keyword wins
# returns {keyword, word, start_column, params} or {} if there is no keyword
func _find_keyword_before_caret(text_edit: TextEdit) -> Dictionary:
	var line_idx = text_edit.get_caret_line()
	var before_caret = text_edit.get_line(line_idx).substr(0, text_edit.get_caret_column())
	var words = RegEx.create_from_string("\\S+").search_all(before_caret)

	for i in range(words.size() - 1, -1, -1):
		var keyword = store.find_keyword(words[i].get_string())
		if keyword.is_empty():
			continue
		return {
			"keyword": keyword,
			"word": words[i].get_string(),
			"start_column": words[i].get_start(),
			"params": words.slice(i + 1).map(func(word): return word.get_string()),
		}
	return {}

func expand_template_at_caret(text_edit: TextEdit) -> bool:
	var found = _find_keyword_before_caret(text_edit)
	if found.is_empty():
		Debug.info("✗ No template found.")
		return false

	Debug.info("Keyword: %s Params: %s" % [found.keyword, found.params])
	insert_template(text_edit, found.keyword, found.start_column, found.params)
	return true

func show_templates_popup(text_edit: TextEdit):
	if text_edit is CodeEdit:
		text_edit.cancel_code_completion()

	# a known keyword (with params after it) or the word before the caret
	# is the initial filter and gets replaced
	var filter = ""
	var start_column = text_edit.get_caret_column()
	var params = []
	var found = _find_keyword_before_caret(text_edit)
	if not found.is_empty():
		filter = found.word
		start_column = found.start_column
		params = found.params
	else:
		var line = text_edit.get_line(text_edit.get_caret_line())
		var partial = RegEx.create_from_string("\\w+$").search(line.substr(0, start_column))
		if partial:
			filter = partial.get_string()
			start_column = partial.get_start()

	var popup = CompletionPopup.new()
	popup.setup(store.templates, filter, Settings.popup_size())
	popup.template_chosen.connect(func(keyword):
		if is_instance_valid(text_edit):
			insert_template(text_edit, keyword, start_column, params)
	)
	popup.edit_requested.connect(func(): _open_template_editor(text_edit.get_window()))
	popup.popup_hide.connect(func():
		if is_instance_valid(text_edit):
			text_edit.grab_focus()
	)
	popup.popup_at_caret(text_edit)

# replaces text from start_column to the caret with the template
func insert_template(text_edit: TextEdit, keyword: String, start_column: int, params: Array = []):
	if session:
		session.finish()
		session = null

	var line_idx = text_edit.get_caret_line()
	var caret_column = text_edit.get_caret_column()
	var line = text_edit.get_line(line_idx)
	var indent = line.substr(0, line.length() - line.strip_edges(true, false).length())
	var expanded = TemplateExpander.expand(store.templates[keyword].body, params, indent, _get_indent_unit(text_edit))

	text_edit.deselect()
	text_edit.begin_complex_operation()
	text_edit.remove_text(line_idx, start_column, line_idx, caret_column)
	text_edit.insert_text(expanded.text, line_idx, start_column)
	text_edit.end_complex_operation()

	session = TabStopSession.new(text_edit, expanded, line_idx, start_column)
	session.start()
	if not session.active:
		session = null

	text_edit.grab_focus()
	_cancel_code_completion_later(text_edit)
	Debug.info("✓ Template Completed!")

func _get_indent_unit(text_edit: TextEdit) -> String:
	if text_edit is CodeEdit and text_edit.indent_use_spaces:
		return " ".repeat(text_edit.indent_size)
	return "\t"

func _open_template_editor(window: Window = null):
	var dialog = TemplateEditorDialog.new()
	dialog.setup(store.defaults, store.user, store.use_defaults)
	dialog.templates_saved.connect(func(user_templates): store.save_user_templates(user_templates))
	dialog.show_dialog(window)

func get_current_script_editor() -> TextEdit:
	var current_editor = EditorInterface.get_script_editor().get_current_editor()
	if current_editor:
		return _find_text_edit(current_editor)
	return null

func _find_text_edit(node: Node) -> TextEdit:
	if node is TextEdit:
		return node

	for child in node.get_children():
		var result = _find_text_edit(child)
		if result:
			return result

	return null

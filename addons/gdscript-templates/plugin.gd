@tool
extends EditorPlugin

const Debug = preload("res://addons/gdscript-templates/scripts/debug_utils.gd")
const Settings = preload("res://addons/gdscript-templates/scripts/settings.gd")
const TemplateStore = preload("res://addons/gdscript-templates/scripts/template_store.gd")
const Expander = preload("res://addons/gdscript-templates/scripts/template_expander.gd")
const TabStopSession = preload("res://addons/gdscript-templates/scripts/tab_stop_session.gd")
const TemplateInserter = preload("res://addons/gdscript-templates/scripts/template_inserter.gd")
const TemplateVariables = preload("res://addons/gdscript-templates/scripts/template_variables.gd")
const CaretContext = preload("res://addons/gdscript-templates/scripts/caret_context.gd")
const ChoicePopup = preload("res://addons/gdscript-templates/scripts/choice_popup.gd")
const CompletionPopup = preload("res://addons/gdscript-templates/scripts/completion_popup.gd")
const TemplateEditorDialog = preload("res://addons/gdscript-templates/scripts/template_editor_dialog.gd")

const TOOL_MENU_ITEM = "GDScript Templates..."

# code completion options with this value prefix are templates
const COMPLETION_MARKER = "gdscript_templates:"
# templates are offered in code completion after this many typed characters
const COMPLETION_MIN_PREFIX = 2
# the usage counts are written to the file this many seconds after the last insertion
const USAGE_SAVE_DELAY = 5.0

var _store: TemplateStore
var _session: TabStopSession
var _popup: CompletionPopup
var _usage_timer: Timer
# the choices of the selected parameter, {name|a,b}
var _choice_popup: ChoicePopup
var _hooked_text_edits: Array[TextEdit] = []

func _enter_tree() -> void:
	Settings.register()
	_store = TemplateStore.new()
	_store.use_defaults = Settings.use_default_templates()
	_store.load_templates()
	_usage_timer = Timer.new()
	_usage_timer.one_shot = true
	_usage_timer.wait_time = USAGE_SAVE_DELAY
	_usage_timer.timeout.connect(_store.save_usage)
	add_child(_usage_timer)
	EditorInterface.get_editor_settings().settings_changed.connect(_on_editor_settings_changed)

	add_tool_menu_item(TOOL_MENU_ITEM, _open_template_editor)

	# _input() doesn't get events from the floating script editor, so hook the text edit directly
	var script_editor := EditorInterface.get_script_editor()
	script_editor.editor_script_changed.connect(_on_editor_script_changed)
	_hook_current_text_edit()

	Debug.info("✓ GDScript Templates Plugin activated")

func _exit_tree() -> void:
	remove_tool_menu_item(TOOL_MENU_ITEM)
	_close_templates_popup()
	_close_choice_popup()
	_store.save_usage()

	var editor_settings := EditorInterface.get_editor_settings()
	if editor_settings.settings_changed.is_connected(_on_editor_settings_changed):
		editor_settings.settings_changed.disconnect(_on_editor_settings_changed)

	var script_editor := EditorInterface.get_script_editor()
	if script_editor.editor_script_changed.is_connected(_on_editor_script_changed):
		script_editor.editor_script_changed.disconnect(_on_editor_script_changed)

	for text_edit in _hooked_text_edits:
		if is_instance_valid(text_edit):
			_unhook_text_edit(text_edit)
	_hooked_text_edits.clear()
	_session = null

func _on_editor_settings_changed() -> void:
	var use_defaults := Settings.use_default_templates()
	if use_defaults != _store.use_defaults:
		_store.use_defaults = use_defaults
		_store.rebuild()

func _on_editor_script_changed(_script: Script) -> void:
	_hook_current_text_edit()

func _hook_current_text_edit() -> void:
	var text_edit := get_current_script_editor()
	if not text_edit or text_edit.gui_input.is_connected(_on_text_edit_gui_input):
		return
	text_edit.gui_input.connect(_on_text_edit_gui_input.bind(text_edit))
	# connected after the script editor, so the script's own options are already added
	if text_edit is CodeEdit:
		text_edit.code_completion_requested.connect(_on_code_completion_requested.bind(text_edit))
	_hooked_text_edits.append(text_edit)
	text_edit.tree_exited.connect(_on_hooked_text_edit_exited.bind(text_edit), CONNECT_ONE_SHOT)

func _unhook_text_edit(text_edit: TextEdit) -> void:
	if text_edit.tree_exited.is_connected(_on_hooked_text_edit_exited):
		text_edit.tree_exited.disconnect(_on_hooked_text_edit_exited)
	if text_edit.gui_input.is_connected(_on_text_edit_gui_input):
		text_edit.gui_input.disconnect(_on_text_edit_gui_input)
	if text_edit is CodeEdit and text_edit.code_completion_requested.is_connected(_on_code_completion_requested):
		text_edit.code_completion_requested.disconnect(_on_code_completion_requested)

func _on_hooked_text_edit_exited(text_edit: TextEdit) -> void:
	_hooked_text_edits.erase(text_edit)

# gui_input is emitted before CodeEdit handles the event, accept_event() blocks the default action
func _on_text_edit_gui_input(event: InputEvent, text_edit: TextEdit) -> void:
	if not (event is InputEventKey and event.pressed):
		return

	if _is_code_completion_active(text_edit) and _confirm_template_completion(text_edit, event):
		text_edit.accept_event()
		return

	if _handle_tab_stop_key(event, text_edit):
		return

	if event.echo:
		return

	if Settings.matches_shortcut(Settings.SHORTCUT_EXPAND, event):
		text_edit.accept_event()
		# selected code or no keyword - pick the template in the browser
		if text_edit.has_selection() or not expand_template_at_caret(text_edit):
			show_templates_popup(text_edit)
	elif Settings.matches_shortcut(Settings.SHORTCUT_SHOW, event):
		text_edit.accept_event()
		show_templates_popup(text_edit)

# Tab and Shift+Tab move between the parameters of the inserted template, Esc ends it
# returns true when the key is dealt with
func _handle_tab_stop_key(event: InputEventKey, text_edit: TextEdit) -> bool:
	if not (_session and _session.active and _session.text_edit == text_edit):
		return false
	if event.keycode == KEY_ESCAPE:
		_session.finish()
		return false
	if _is_code_completion_active(text_edit) or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return false
	if _handle_choice_key(event, text_edit):
		return true
	if event.keycode != KEY_TAB:
		return false

	var consumed := _session.previous() if event.shift_pressed else _session.next()
	if consumed:
		text_edit.accept_event()
		_cancel_code_completion_later(text_edit)
		_update_choice_popup(text_edit)
	return true

# on a parameter with choices: Up and Down change the choice, Enter confirms it like Tab
func _handle_choice_key(event: InputEventKey, text_edit: TextEdit) -> bool:
	if event.shift_pressed or _session.current_choices().is_empty():
		return false
	var done := false
	match event.keycode:
		KEY_UP:
			done = _session.cycle_choice(-1)
		KEY_DOWN:
			done = _session.cycle_choice(1)
		KEY_ENTER, KEY_KP_ENTER:
			done = _session.next()
	if done:
		text_edit.accept_event()
		_update_choice_popup(text_edit)
	return done

# shows the choices of the selected parameter, closes the list when it has none
func _update_choice_popup(text_edit: TextEdit) -> void:
	var choices := _session.current_choices() if _session else PackedStringArray()
	if choices.is_empty():
		_close_choice_popup()
		return
	if not is_instance_valid(_choice_popup):
		_choice_popup = ChoicePopup.new()
		_choice_popup.choice_picked.connect(_on_choice_picked)
	_choice_popup.show_choices(text_edit, _session.current_position(), choices, _session.current_choice_index())

func _on_choice_picked(index: int) -> void:
	if _session and _session.choose(index):
		_update_choice_popup(_session.text_edit)

func _close_choice_popup() -> void:
	if is_instance_valid(_choice_popup):
		_choice_popup.close()
	_choice_popup = null

# adds the templates matching the word before the caret to the code completion popup
func _on_code_completion_requested(text_edit: CodeEdit) -> void:
	if not Settings.show_in_code_completion():
		return
	var word := CaretContext.completion_word(text_edit)
	if word.length() < COMPLETION_MIN_PREFIX:
		return
	var word_lower := word.to_lower()
	var keywords := _store.templates.keys().filter(func(keyword): return keyword.to_lower().begins_with(word_lower))
	if keywords.is_empty():
		return

	# update_code_completion_options() replaces the options, add the script's ones again
	for option in text_edit.get_code_completion_options():
		text_edit.add_code_completion_option(option.kind, option.display_text, option.insert_text,
			option.font_color, option.icon, option.default_value, option.location)
	var editor_theme := EditorInterface.get_editor_theme()
	var icon := editor_theme.get_icon("Script", "EditorIcons")
	var color := editor_theme.get_color("font_color", "Editor")
	for keyword in keywords:
		var display: String = keyword
		var params := Expander.format_params(_store.templates[keyword].body)
		if not params.is_empty():
			display += " " + params
		# insert_text is used when the option is picked with the mouse, Ctrl+E then expands it
		text_edit.add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, display + "  (template)", keyword,
			color, icon, COMPLETION_MARKER + keyword)
	text_edit.update_code_completion_options(false)

# Enter / Tab on a template in the code completion popup expands it
func _confirm_template_completion(text_edit: CodeEdit, event: InputEventKey) -> bool:
	if not (event.is_action("ui_text_completion_accept", true) or event.is_action("ui_text_completion_replace", true)):
		return false
	var option := text_edit.get_code_completion_option(text_edit.get_code_completion_selected_index())
	var value: Variant = option.get("default_value")
	if not (value is String and value.begins_with(COMPLETION_MARKER)):
		return false
	var keyword: String = value.trim_prefix(COMPLETION_MARKER)
	if not _store.templates.has(keyword):
		return false

	text_edit.cancel_code_completion()
	var word := CaretContext.word_before_caret(text_edit)
	insert_template(text_edit, keyword, word.from, word.to)
	return true

func _is_code_completion_active(text_edit: TextEdit) -> bool:
	return text_edit is CodeEdit and text_edit.get_code_completion_selected_index() != -1

func _cancel_code_completion_later(text_edit: TextEdit) -> void:
	await get_tree().process_frame
	if is_instance_valid(text_edit) and text_edit is CodeEdit:
		text_edit.cancel_code_completion()

func expand_template_at_caret(text_edit: TextEdit) -> bool:
	_store.reload_if_changed()
	var found := CaretContext.find_keyword_before_caret(text_edit, _store.find_keyword)
	if found.is_empty():
		Debug.info("✗ No template found.")
		return false

	Debug.info("Keyword: %s Params: %s" % [found.keyword, found.params])
	insert_template(text_edit, found.keyword, found.from, found.to, found.params)
	return true

func show_templates_popup(text_edit: TextEdit) -> void:
	_store.reload_if_changed()
	if text_edit is CodeEdit:
		text_edit.cancel_code_completion()

	var target := CaretContext.get_popup_target(text_edit, _store.find_keyword)
	_close_templates_popup()
	_popup = CompletionPopup.new()
	_popup.setup(_store.templates, target.filter, target.selection, _store.usage, _store.get_categories(), _get_variables())
	_popup.template_chosen.connect(func(keyword, params):
		if is_instance_valid(text_edit):
			insert_template(text_edit, keyword, target.from, target.to, params, target.selection)
	)
	_popup.edit_requested.connect(func(): _open_template_editor(text_edit.get_window()))
	_popup.closed.connect(func(): _popup = null)
	_popup.open(text_edit)

func _close_templates_popup() -> void:
	if is_instance_valid(_popup):
		_popup.close(false)
	_popup = null

# replaces the text from `from` to `to` (line, column) with the template
func insert_template(text_edit: TextEdit, keyword: String, from: Vector2i, to: Vector2i,
		params: Array = [], selection: String = "") -> void:
	if _session:
		_session.finish()
		_session = null

	_session = TemplateInserter.insert(text_edit, _store.templates[keyword].body, from, to, params, selection, _get_variables())
	if _session:
		_session.finished.connect(_close_choice_popup)
		_update_choice_popup(text_edit)
	_store.record_use(keyword)
	if _usage_timer.is_stopped():
		_usage_timer.start()

	text_edit.grab_focus()
	_cancel_code_completion_later(text_edit)
	Debug.info("✓ Template Completed!")

# values of {@filename}, {@class} and {@date} for the script being edited
func _get_variables() -> Dictionary:
	var script := EditorInterface.get_script_editor().get_current_script()
	return TemplateVariables.build(script.resource_path if script else "")

func _open_template_editor(window: Window = null) -> void:
	_store.reload_if_changed()
	var dialog := TemplateEditorDialog.new()
	dialog.setup(_store.defaults, _store.user, _store.project, _store.use_defaults, _get_variables())
	dialog.templates_saved.connect(_store.save_templates)
	dialog.show_dialog(window)

func get_current_script_editor() -> TextEdit:
	var current_editor := EditorInterface.get_script_editor().get_current_editor()
	if not current_editor:
		return null
	var text_edits := current_editor.find_children("*", "TextEdit", true, false)
	return text_edits[0] if not text_edits.is_empty() else null

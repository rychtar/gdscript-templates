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
var popup: CompletionPopup
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
	_close_templates_popup()

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
		if event.keycode == KEY_TAB and not _is_code_completion_active(text_edit) \
				and not (event.ctrl_pressed or event.alt_pressed or event.meta_pressed):
			var consumed = session.previous() if event.shift_pressed else session.next()
			if consumed:
				text_edit.accept_event()
				_cancel_code_completion_later(text_edit)
			return
		elif event.keycode == KEY_ESCAPE:
			session.finish()

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
		# odd number of quotes before the word - it's inside a string or a quoted param
		if keyword.is_empty() or before_caret.substr(0, words[i].get_start()).count("\"") % 2 == 1:
			continue
		# "quoted text" is one param
		var params = TemplateExpander.split_args(before_caret.substr(words[i].get_end()))
		return {
			"keyword": keyword,
			"word": words[i].get_string(),
			"start_column": words[i].get_start(),
			"params": params.map(func(param): return param.value),
			# as typed, with quotes
			"raw_params": params.map(func(param): return param.raw),
		}
	return {}

func expand_template_at_caret(text_edit: TextEdit) -> bool:
	store.reload_if_changed()
	var found = _find_keyword_before_caret(text_edit)
	if found.is_empty():
		Debug.info("✗ No template found.")
		return false

	Debug.info("Keyword: %s Params: %s" % [found.keyword, found.params])
	var line_idx = text_edit.get_caret_line()
	insert_template(text_edit, found.keyword, Vector2i(line_idx, found.start_column), Vector2i(line_idx, text_edit.get_caret_column()), found.params)
	return true

func show_templates_popup(text_edit: TextEdit):
	store.reload_if_changed()
	if text_edit is CodeEdit:
		text_edit.cancel_code_completion()

	var line_idx = text_edit.get_caret_line()
	var from = Vector2i(line_idx, text_edit.get_caret_column())
	var to = from
	var selection = ""
	var filter = ""

	if text_edit.has_selection():
		var selected = _get_selected_range(text_edit)
		from = selected.from
		to = selected.to
		selection = selected.text
	else:
		# a known keyword (with params after it) or the word before the caret
		# is the initial filter and gets replaced
		var found = _find_keyword_before_caret(text_edit)
		if not found.is_empty():
			# params typed after the keyword go into the search, where they can be edited
			filter = " ".join([found.word] + found.raw_params)
			from.y = found.start_column
		else:
			var line = text_edit.get_line(line_idx)
			var partial = RegEx.create_from_string("\\w+$").search(line.substr(0, from.y))
			if partial:
				filter = partial.get_string()
				from.y = partial.get_start()

	_close_templates_popup()
	popup = CompletionPopup.new()
	popup.setup(store.templates, filter, selection, store.usage)
	popup.template_chosen.connect(func(keyword, params):
		if is_instance_valid(text_edit):
			insert_template(text_edit, keyword, from, to, params, selection)
	)
	popup.edit_requested.connect(func(): _open_template_editor(text_edit.get_window()))
	popup.closed.connect(func(): popup = null)
	popup.open(text_edit)

# selection spanning more lines is extended to whole lines (without the first line's indentation),
# returns {from, to, text} with the text dedented
func _get_selected_range(text_edit: TextEdit) -> Dictionary:
	var from = Vector2i(text_edit.get_selection_from_line(), text_edit.get_selection_from_column())
	var to = Vector2i(text_edit.get_selection_to_line(), text_edit.get_selection_to_column())
	if from.x != to.x:
		# selecting whole lines ends at the start of the next line
		if to.y == 0:
			to.x -= 1
		to.y = text_edit.get_line(to.x).length()
		var first_line = text_edit.get_line(from.x)
		from.y = first_line.length() - first_line.strip_edges(true, false).length()
	var text = _get_text_between(text_edit, from, to)
	return {"from": from, "to": to, "text": TemplateExpander.dedent(text.strip_edges(false, true))}

static func _get_text_between(text_edit: TextEdit, from: Vector2i, to: Vector2i) -> String:
	if from.x == to.x:
		return text_edit.get_line(from.x).substr(from.y, to.y - from.y)
	var lines = [text_edit.get_line(from.x).substr(from.y)]
	for line_idx in range(from.x + 1, to.x):
		lines.append(text_edit.get_line(line_idx))
	lines.append(text_edit.get_line(to.x).substr(0, to.y))
	return "\n".join(lines)

func _close_templates_popup():
	if is_instance_valid(popup):
		popup.close(false)
	popup = null

# replaces the text from `from` to `to` (line, column) with the template
func insert_template(text_edit: TextEdit, keyword: String, from: Vector2i, to: Vector2i, params: Array = [], selection: String = ""):
	if session:
		session.finish()
		session = null

	var line = text_edit.get_line(from.x)
	var indent = line.substr(0, line.length() - line.strip_edges(true, false).length())
	var expanded = TemplateExpander.expand(store.templates[keyword].body, params, indent, _get_indent_unit(text_edit), selection)

	text_edit.deselect()
	text_edit.begin_complex_operation()
	text_edit.remove_text(from.x, from.y, to.x, to.y)
	text_edit.insert_text(expanded.text, from.x, from.y)
	text_edit.end_complex_operation()
	store.record_use(keyword)

	session = TabStopSession.new(text_edit, expanded, from.x, from.y)
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
	store.reload_if_changed()
	var dialog = TemplateEditorDialog.new()
	dialog.setup(store.defaults, store.user, store.project, store.use_defaults)
	dialog.templates_saved.connect(store.save_templates)
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

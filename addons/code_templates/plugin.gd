@tool
extends EditorPlugin

const DEBUG_MODE = true

#OS specific vars
var is_macos = OS.get_name() == "macOS"

# paths
var config_path: String = "res://addons/code_templates/templates.json"
var user_config_path: String = "user://code_templates.json"
var settings_path: String = "user://code_templates_settings.json"

# templates
var use_default_templates: bool = true
var templates: Dictionary = {}

var code_completion_prefixes: PackedStringArray = []

func _enter_tree():
	# load data and prepare cache
	load_settings()
	load_templates()
	update_code_completion_cache()
	
	# add plugin to the menu
	add_tool_menu_item("Code Templates Settings", _open_settings)
	
	# logs
	debug_print("✓ Code Templates Plugin activated")
	debug_print("  Ctrl+E = Complete code from template")
	debug_print("  Ctrl+Space = Show available templates")

func _exit_tree():
	remove_tool_menu_item("Code Templates Settings")

# TODO: custom shortcut in settings + auto detection?
func _input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed and event.keycode == KEY_E:
			_on_expand_pressed()
			get_viewport().set_input_as_handled()
		elif event.ctrl_pressed and event.keycode == KEY_SPACE:
			_show_code_completion()
			get_viewport().set_input_as_handled()

func _on_expand_pressed():
	if try_expand_template():
		debug_print("✓ Template Completed!")
	else:
		debug_print("✗ No template found.")

func _show_code_completion():
	var text_edit = get_current_script_editor()
	if not text_edit:
		return
		
	# cancel current code completition	
	text_edit.cancel_code_completion()
	await get_tree().process_frame
	
	var line_idx = text_edit.get_caret_line()
	var col = text_edit.get_caret_column()
	var line = text_edit.get_line(line_idx)
	var before_cursor = line.substr(0, col).strip_edges()
	
	# Get the last word
	var words = before_cursor.split(" ", false)
	var partial = words[-1] if words.size() > 0 else ""
	
	# show pop up window with help
	_create_centered_completion_popup(text_edit, partial)

func _create_centered_completion_popup(text_edit: TextEdit, partial: String):
	# find matches
	var matches = []
	var partial_lower = partial.to_lower()
	
	for keyword in templates.keys():
		if partial.is_empty() or keyword.to_lower().begins_with(partial_lower):
			var template = templates[keyword]
			var params = _extract_params_from_template(template)
			var display = keyword
			if params.size() > 0:
				display += " " + " ".join(params)
			matches.append({"keyword": keyword, "display": display})
	
	if matches.is_empty():
		return
	
	# sort by keyword
	matches.sort_custom(func(a, b): return a.keyword < b.keyword)
	
	# setting macos retina specific adjustments	
	var size_multiplier = 1.3 if is_macos else 1.0
	
	# create window
	var window = Window.new()
	window.title = "Code Templates"
	var base_width = int(1200 * size_multiplier)
	var base_height = int(min(matches.size() * 60 + 80, 800) * size_multiplier)
	window.size = Vector2i(base_width, base_height)
	window.min_size = Vector2i(int(1000 * size_multiplier), int(400 * size_multiplier))
	window.unresizable = false
	window.wrap_controls = true
	
	# Main container with margin
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin_size = int(15 * size_multiplier)
	margin.add_theme_constant_override("margin_left", margin_size)
	margin.add_theme_constant_override("margin_right", margin_size)
	margin.add_theme_constant_override("margin_top", margin_size)
	margin.add_theme_constant_override("margin_bottom", margin_size)
	
	# HSplitContainer for list and preview
	var hsplit = HSplitContainer.new()
	hsplit.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	# Left side - ItemList
	var item_panel = PanelContainer.new()
	var item_vbox = VBoxContainer.new()
	
	var item_label = Label.new()
	item_label.text = "Templates"
	item_label.add_theme_font_size_override("font_size", int(20 * size_multiplier))
	item_vbox.add_child(item_label)
		
	var item_list = ItemList.new()
	item_list.custom_minimum_size = Vector2i(int(400 * size_multiplier), 0)
	var font_size = int(24 * size_multiplier)
	item_list.add_theme_font_size_override("font_size", font_size)
	item_list.fixed_icon_size = Vector2i(0, 0)
	item_list.allow_reselect = true
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	for i in range(matches.size()):
		item_list.add_item(matches[i].display)
	
	# Select first item
	if matches.size() > 0:
		item_list.select(0)
		
		
	item_vbox.add_child(item_list)	
	item_panel.add_child(item_vbox)
	
	# Right side - Preview panel
	var preview_panel = PanelContainer.new()
	preview_panel.focus_mode = Control.FOCUS_NONE
	
	var preview_vbox = VBoxContainer.new()
	preview_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	var preview_label = Label.new()
	preview_label.text = "Preview"
	preview_label.add_theme_font_size_override("font_size", int(20 * size_multiplier))
	preview_vbox.add_child(preview_label)
	
	var preview_text = TextEdit.new()
	preview_text.editable = false
	preview_text.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	preview_text.add_theme_font_size_override("font_size", int(24 * size_multiplier))
	preview_text.custom_minimum_size = Vector2i(int(500 * size_multiplier), 0)
	preview_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_text.focus_mode = Control.FOCUS_NONE
	preview_text.context_menu_enabled = false	
	
	# Show first template
	if matches.size() > 0:
		var first_template = templates[matches[0].keyword]
		preview_text.text = first_template
	
	preview_vbox.add_child(preview_text)	
	preview_panel.add_child(preview_vbox)
	
	# Add to split container
	hsplit.add_child(item_panel)
	hsplit.add_child(preview_panel)
	
	margin.add_child(hsplit)
	
	# Update preview when selection changes
	item_list.item_selected.connect(func(index):
		var selected = matches[index]
		var template_text = templates[selected.keyword]
		preview_text.text = template_text
	)
	
	# Signal and enter
	item_list.item_activated.connect(func(index):
		var selected = matches[index]
		_insert_completion(text_edit, partial, selected.keyword)
		window.queue_free()
	)
	
		
	window.add_child(margin)
	get_editor_interface().get_base_control().add_child(window)
	
	# setting up window vs caret possition
	var text_edit_global = text_edit.get_screen_position()
	var caret_line = text_edit.get_caret_line()
	var caret_column = text_edit.get_caret_column()
	var line_height = text_edit.get_line_height()
	var first_visible_line = text_edit.get_first_visible_line()
	
	# caret possition
	var char_width = 9
	var caret_x = text_edit_global.x + (caret_column * char_width) + 70
	var caret_y = text_edit_global.y + ((caret_line - first_visible_line) * line_height)
	
	# Window offset to not block caret
	var base_offset_y = (line_height * 2) + 40  
	var offset_x = 50  
	var offset_y = int(base_offset_y * (2.0 if is_macos else 1.0))
	
	var x_pos = caret_x + offset_x
	var y_pos = caret_y + offset_y
	
	# Outside window placement fix
	var screen_size = DisplayServer.screen_get_size()
	if x_pos + window.size.x > screen_size.x:
		x_pos = screen_size.x - window.size.x - 20 
	if y_pos + window.size.y > screen_size.y:
		y_pos = screen_size.y - window.size.y - 20
	
	x_pos = max(20, x_pos)
	y_pos = max(20, y_pos)
	
	window.position = Vector2i(x_pos, y_pos)
	window.popup()
	
	# set focus for window
	await get_tree().process_frame
	item_list.grab_focus()
	
	# close when focus is lost
	window.close_requested.connect(func(): window.queue_free())
	
	# other item_list inputs
	item_list.gui_input.connect(func(event):
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_ESCAPE:
				window.queue_free()
			elif event.keycode == KEY_TAB:
				var selected_items = item_list.get_selected_items()
				if selected_items.size() > 0:
					var index = selected_items[0]
					var selected = matches[index]
					_insert_completion(text_edit, partial, selected.keyword)
					window.queue_free()
	)

func _extract_params_from_template(template: String) -> Array:
	var params = []
	var regex = RegEx.new()
	regex.compile("\\{([^}]+)\\}") 
	
	for result in regex.search_all(template):
		var param_name = result.get_string(1) 
		if param_name != "CURSOR":
			params.append("{" + param_name + "}")
	
	return params

func _insert_completion(text_edit: TextEdit, partial: String, keyword: String):
	var line_idx = text_edit.get_caret_line()
	var col = text_edit.get_caret_column()
	
	# find start
	var start_col = col - partial.length()
	
	var has_params = false
	if keyword in templates:
		var template = templates[keyword]
		var params = _extract_params_from_template(template)
		has_params = params.size() > 0
	
	if has_params:
		# template has params
		text_edit.select(line_idx, start_col, line_idx, col)
		text_edit.insert_text_at_caret(keyword + " ")
		
		# show hints
		if keyword in templates:
			var template = templates[keyword]
			var params = _extract_params_from_template(template)
			var hint_text = " ".join(params)
			await get_tree().process_frame
			text_edit.set_code_hint(hint_text)
	else:
		# template is paramless expand it
		text_edit.select(line_idx, start_col, line_idx, col)
		text_edit.insert_text_at_caret(keyword)
		
		# Expand template
		try_expand_template()

func get_current_script_editor() -> TextEdit:
	var script_editor = get_editor_interface().get_script_editor()
	var current_editor = script_editor.get_current_editor()
	
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

func try_expand_template() -> bool:
	var text_edit = get_current_script_editor()
	if not text_edit:
		debug_print("✗ Text Editor not found")
		return false
	
	var line_idx = text_edit.get_caret_line()
	var col = text_edit.get_caret_column()
	var line = text_edit.get_line(line_idx)
	
	# get current indent
	var current_indent = ""
	var indent_match = line.substr(0, col)
	for i in range(indent_match.length()):
		if indent_match[i] in [' ', '\t']:
			current_indent += indent_match[i]
		else:
			break
	
	# text before cursor
	var before_cursor = line.substr(0, col).strip_edges()
	
	if before_cursor.is_empty():
		return false
	
	# split keyword and params
	var parts = before_cursor.split(" ", false)
	if parts.is_empty():
		return false
	
	var keyword = parts[0]
	var params = parts.slice(1) if parts.size() > 1 else []
	
	# check whether template exists
	var keyword_lower = keyword.to_lower()
	var found_template = ""
	
	for template_key in templates.keys():
		if template_key.to_lower() == keyword_lower:
			found_template = template_key
			break
	
	if found_template.is_empty():
		return false
	
	# Complete template
	var template_text = templates[found_template]
	var expanded = expand_template(template_text, params)
	
	# Fix indent
	expanded = apply_indentation(expanded, current_indent)
	
	var keyword_start = 0
	for i in range(line.length()):
		if line[i] not in [' ', '\t']:
			keyword_start = i
			break
	
	# delete original text and place update template
	text_edit.begin_complex_operation()
	text_edit.select(line_idx, keyword_start, line_idx, col)
	text_edit.delete_selection()
	text_edit.insert_text_at_caret(expanded)
	
	# place cursor
	position_cursor_with_indent(text_edit, template_text, expanded, line_idx, keyword_start, current_indent)
	text_edit.end_complex_operation()
	return true

func expand_template(template: String, params: Array) -> String:
	var result = template
	
	var regex = RegEx.new()
	regex.compile("\\{([^}]+)\\}")
	
	var matches = regex.search_all(template)
	
	# replace parameters
	for i in range(min(params.size(), matches.size())):
		var placeholder = matches[i].get_string(0) 
		result = result.replace(placeholder, params[i])	
	
	return result

func apply_indentation(text: String, base_indent: String) -> String:
	var lines = text.split("\n")
	var result = []
	
	for i in range(lines.size()):
		var line = lines[i]
		
		if i == 0:
			# first line is correct
			result.append(line)
		else:
			# next lines - adding indent
			result.append(base_indent + line)
	
	return "\n".join(result)

func position_cursor_with_indent(text_edit: TextEdit, original_template: String, expanded: String, start_line: int, start_col: int, base_indent: String):
	var cursor_marker = "|CURSOR|"
	
	var line_idx = start_line
	var found = false
	var marker_line = -1
	var marker_col = -1
	
	# Find cursor
	for i in range(20):  # Max 20 řádků
		var line = text_edit.get_line(line_idx + i)
		var pos = line.find(cursor_marker)
		if pos != -1:
			marker_line = line_idx + i
			marker_col = pos
			found = true
			break
	
	if found:
		# delete marker
		text_edit.select(marker_line, marker_col, marker_line, marker_col + cursor_marker.length())
		text_edit.delete_selection()
		
		# setting up caret position
		text_edit.set_caret_line(marker_line)
		text_edit.set_caret_column(marker_col)
		
		# cancel autocompleting
		await get_tree().process_frame
		text_edit.cancel_code_completion()

func load_templates():
	templates.clear()
	
	if use_default_templates:
		templates = load_json_file(config_path)
		debug_print("✓ Loaded ", templates.size(), " templates from ", config_path)
	
	var user_templates = load_json_file(user_config_path)
	debug_print("✓ Loaded ", user_templates.size(), " templates from ", user_config_path)
	templates.merge(user_templates, true)
		
	update_code_completion_cache()

func update_code_completion_cache():
	code_completion_prefixes.clear()
	for keyword in templates.keys():
		code_completion_prefixes.append(keyword)

func save_default_templates():
	# Save default templates
	var file = FileAccess.open(config_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(templates, "\t"))
		file.close()
		debug_print("✓ Default templates saved in ", config_path)

func save_templates():
	# Save do user templates
	var file = FileAccess.open(user_config_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(templates, "\t"))
		file.close()
		debug_print("✓ User Templates saved in ", user_config_path)

func _open_settings():
	
	# dialog definition
	var dialog = AcceptDialog.new()
	dialog.title = "Code Templates Settings"
	dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	
	dialog.ok_button_text = "Close"
	dialog.add_button("Save", false, "save")
	
	# content definition
	
	var vbox = VBoxContainer.new()	
	var label = Label.new()
	label.text = "Adjust templates in JSON format:\nUsage: {0}, {1} for params, |CURSOR| cursor position after code completition"
	vbox.add_child(label)
	
	var use_defaults_checkbox = CheckBox.new()
	use_defaults_checkbox.text = "Use default templates"
	use_defaults_checkbox.button_pressed = use_default_templates
	vbox.add_child(use_defaults_checkbox)
		
	var text_edit = TextEdit.new()
		
	var user_templates_only = load_json_file(user_config_path)
		
	text_edit.text = JSON.stringify(user_templates_only, "\t")
	text_edit.custom_minimum_size = Vector2(800, 800)
	vbox.add_child(text_edit)
		
	dialog.custom_action.connect(func(action):
		if action == "save":
			use_default_templates = use_defaults_checkbox.button_pressed
			save_settings()
			
			var json = JSON.new()
			if json.parse(text_edit.text) == OK:
				var new_user_templates = json.get_data()
				if new_user_templates is Dictionary:
					var file = FileAccess.open(user_config_path, FileAccess.WRITE)
					if file:
						file.store_string(JSON.stringify(new_user_templates, "\t"))
						file.close()
					
					load_templates()
					update_code_completion_cache()
					dialog.hide()
					debug_print("✓ User Config saved!")
			else:
				debug_print("✗ Error in JSON format!")
	)

	dialog.add_child(vbox)
	
	get_editor_interface().popup_dialog_centered(dialog)
	
func debug_print(a1 = "", a2 = "", a3 = "", a4 = "", a5 = "") -> void:
	if DEBUG_MODE:
		print("[Code_Templates_plugin] ", a1, a2, a3, a4, a5)
		
func load_settings():
	var settings = load_json_file(settings_path)
	if settings.has("use_default_templates"):
		use_default_templates = settings.use_default_templates
		debug_print("✓ Settings loaded: use_default_templates = ", use_default_templates)

func save_settings():
	var settings = {
		"use_default_templates": use_default_templates
	}
	if save_json_file(settings_path, settings):
		debug_print("✓ Settings saved")
	else:
		debug_print("✓ Settings not saved")
		
func load_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	
	var json = JSON.new()
	var content = file.get_as_text()
	file.close()
	
	if json.parse(content) == OK:
		return json.get_data()
	
	return {}

func save_json_file(path: String, data: Dictionary) -> bool:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		return true
	return false

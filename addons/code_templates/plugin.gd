@tool
extends EditorPlugin

var templates: Dictionary = {}
var config_path: String = "res://addons/code_templates/templates.json"
var user_config_path: String = "user://code_templates.json"
var shortcut: Shortcut
var code_completion_prefixes: PackedStringArray = []

func _enter_tree():
	load_templates()
	update_code_completion_cache()
		
	# Add plugin to the menu
	add_tool_menu_item("Code Templates Settings", _open_settings)
	
	# Create shortcut
	shortcut = Shortcut.new()
	var event = InputEventKey.new()
	event.ctrl_pressed = true
	event.keycode = KEY_E
	shortcut.events = [event]
	
	print("✓ Code Templates Plugin activated")
	print("  Ctrl+E = Complete code from template")
	print("  Ctrl+Space = Show available templates")

func _exit_tree():
	remove_tool_menu_item("Code Templates Settings")

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
		print("✓ Template Completed!")
	else:
		print("✗ No template found.")

func _show_code_completion():
	var text_edit = get_current_script_editor()
	if not text_edit:
		return
	
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
	var is_macos = OS.get_name() == "macOS"
	var size_multiplier = 1.3 if is_macos else 1.0
	
	# create window
	var window = Window.new()
	window.title = "Code Templates"
	var base_width = int(800 * size_multiplier)
	var base_height = int(min(matches.size() * 60 + 80, 800) * size_multiplier)
	window.size = Vector2i(base_width, base_height)
	window.min_size = Vector2i(int(700 * size_multiplier), int(400 * size_multiplier))
	window.unresizable = false
	window.wrap_controls = true
	
	# ItemList
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin_size = int(15 * size_multiplier)
	margin.add_theme_constant_override("margin_left", margin_size)
	margin.add_theme_constant_override("margin_right", margin_size)
	margin.add_theme_constant_override("margin_top", margin_size)
	margin.add_theme_constant_override("margin_bottom", margin_size)
	
	var item_list = ItemList.new()
	item_list.set_anchors_preset(Control.PRESET_FULL_RECT)
	var font_size = int(24 * size_multiplier)
	item_list.add_theme_font_size_override("font_size", font_size)
	item_list.fixed_icon_size = Vector2i(0, 0)
	item_list.allow_reselect = true
	item_list.auto_height = true
	
	for i in range(matches.size()):
		item_list.add_item(matches[i].display)
	
	# Select first item
	if matches.size() > 0:
		item_list.select(0)
	
	margin.add_child(item_list)
	
	# Signal - click and enter
	item_list.item_activated.connect(func(index):
		var selected = matches[index]
		_insert_completion(text_edit, partial, selected.keyword)
		window.queue_free()
	)
	
	# doubleclick
	item_list.item_clicked.connect(func(index, _at_position, mouse_button_index):
		if mouse_button_index == MOUSE_BUTTON_LEFT:
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
	
	# close on ESC
	item_list.gui_input.connect(func(event):
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			window.queue_free()
	)

func _extract_params_from_template(template: String) -> Array:
	var params = []
	var regex = RegEx.new()
	regex.compile("\\{(\\d+)\\}")
	
	for result in regex.search_all(template):
		var param_num = int(result.get_string(1))
		while params.size() <= param_num:
			params.append("{" + str(params.size()) + "}")
	
	return params

func _insert_completion(text_edit: TextEdit, partial: String, keyword: String):
	var line_idx = text_edit.get_caret_line()
	var col = text_edit.get_caret_column()
	
	# find start
	var start_col = col - partial.length()
	
	# change for keyword
	text_edit.select(line_idx, start_col, line_idx, col)
	text_edit.insert_text_at_caret(keyword + " ")

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
		print("✗ Text Editor not found")
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
	text_edit.select(line_idx, keyword_start, line_idx, col)
	text_edit.delete_selection()
	text_edit.insert_text_at_caret(expanded)
	
	# place cursor
	position_cursor_with_indent(text_edit, template_text, expanded, line_idx, keyword_start, current_indent)
	
	return true

func expand_template(template: String, params: Array) -> String:
	var result = template
	
	# put parameters
	for i in range(params.size()):
		var placeholder = "{" + str(i) + "}"
		result = result.replace(placeholder, params[i])
	
	# remove cursor mark
	result = result.replace("|CURSOR|", "")
	
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
	var cursor_pos = original_template.find(cursor_marker)
	
	if cursor_pos == -1:
		return
	
	# count rows before cursor
	var before_cursor = original_template.substr(0, cursor_pos)
	var lines = before_cursor.split("\n")
	
	var target_line = start_line + lines.size() - 1
	var target_col = 0
	
	if lines.size() == 1:
		# cursor is on line 1
		target_col = start_col + cursor_pos
	else:
		# cursor is on next line - adding indent
		target_col = base_indent.length() + lines[-1].length()
	
	text_edit.set_caret_line(target_line)
	text_edit.set_caret_column(target_col)

func load_templates():
	# Load base plugin templates
	if FileAccess.file_exists(config_path):
		var file = FileAccess.open(config_path, FileAccess.READ)
		if file:
			var json = JSON.new()
			var content = file.get_as_text()
			file.close()
			
			if json.parse(content) == OK:
				templates = json.get_data()
				print("✓ Loaded ", templates.size(), " templates from ", config_path)
			else:
				print("✗ Error during parsing ", config_path)
				_load_default_templates()
	else:
		print("✗ File ", config_path, " does not exist, creating default...")
		_load_default_templates()
		save_default_templates()
	
	# Load user created tempaltes
	if FileAccess.file_exists(user_config_path):
		var file = FileAccess.open(user_config_path, FileAccess.READ)
		if file:
			var json = JSON.new()
			var content = file.get_as_text()
			file.close()
			
			if json.parse(content) == OK:
				var user_templates = json.get_data()
				if user_templates is Dictionary:
					templates.merge(user_templates, true)
					print("✓ Loaded ", user_templates.size(), " templates from ", user_config_path)
	
	update_code_completion_cache()

func update_code_completion_cache():
	code_completion_prefixes.clear()
	for keyword in templates.keys():
		code_completion_prefixes.append(keyword)

func _load_default_templates():
	# Default templates
	templates = {
		"prnt": 'print("|CURSOR|")',
		"fori": "for i in range({0}):\n\t|CURSOR|",
		"fore": "for {0} in {1}:\n\t|CURSOR|",
		"ifn": "if {0} != null:\n\t|CURSOR|",
		"ife": "if {0} == {1}:\n\t|CURSOR|",
		"elif": "elif {0}:\n\t|CURSOR|",
		"else": "else:\n\t|CURSOR|",
		"ready": "func _ready():\n\t|CURSOR|",
		"process": "func _process(delta):\n\t|CURSOR|",
		"physics": "func _physics_process(delta):\n\t|CURSOR|",
		"input": "func _input(event):\n\t|CURSOR|",
		"func": "func {0}():\n\t|CURSOR|",
		"funcr": "func {0}() -> {1}:\n\t|CURSOR|\n\treturn",
		"signal": "signal {0}",
		"export": "@export var {0}: {1}",
		"onready": "@onready var {0} = ${1}",
		"match": "match {0}:\n\t{1}:\n\t\t|CURSOR|",
		"class": "class_name {0}\nextends {1}\n\n|CURSOR|",
		"var": "var {0}: {1} = {2}|CURSOR|",
		"const": "const {0}: {1} = {2}|CURSOR|",
	}

func save_default_templates():
	# Save default templates
	var file = FileAccess.open(config_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(templates, "\t"))
		file.close()
		print("✓ Default templates saved in ", config_path)

func save_templates():
	# Save do user templates
	var file = FileAccess.open(user_config_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(templates, "\t"))
		file.close()
		print("✓ User Templates saved in ", user_config_path)

func _open_settings():
	var dialog = AcceptDialog.new()
	dialog.title = "Code Templates Settings"
	dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	
	var vbox = VBoxContainer.new()
	
	var label = Label.new()
	label.text = "Adjust templates in JSON format:\nUsage: {0}, {1} for params, |CURSOR| cursor position after code completition"
	vbox.add_child(label)
	
	var text_edit = TextEdit.new()
	text_edit.text = JSON.stringify(templates, "\t")
	text_edit.custom_minimum_size = Vector2(600, 400)
	vbox.add_child(text_edit)
	
	var button_box = HBoxContainer.new()
	button_box.alignment = BoxContainer.ALIGNMENT_END
	
	var save_button = Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(func():
		var json = JSON.new()
		if json.parse(text_edit.text) == OK:
			var new_templates = json.get_data()
			if new_templates is Dictionary:
				templates = new_templates
				save_templates()
				update_code_completion_cache()
				dialog.hide()
				print("✓ Templates saved!")
		else:
			print("✗ Error in JSON format!")
	)
	
	button_box.add_child(save_button)
	vbox.add_child(button_box)
	
	margin.add_child(vbox)
	dialog.add_child(margin)
	
	get_editor_interface().popup_dialog_centered(dialog)

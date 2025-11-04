@tool
extends EditorPlugin

# tools
const FileUtils = preload("res://addons/gdscript-templates/scripts/file_utils.gd")
const Debug = preload("res://addons/gdscript-templates/scripts/debug_utils.gd")

# plugin related constants
const CURSOR = "CURSOR"
const CURSOR_MARKER = "|CURSOR|"

#OS specific vars
var is_macos = OS.get_name() == "macOS"
var size_multiplier = 1.3 if is_macos else 1.0

# templates
var use_default_templates: bool = true
var templates: Dictionary = {}

var code_completion_prefixes: PackedStringArray = []
var awaiting_expand: bool = false 

func _enter_tree():
	
	# load data and prepare cache
	load_settings()
	load_templates()
	update_code_completion_cache()
	
	# add plugin to the menu
	add_tool_menu_item("GDScript Templates Settings", _open_settings)
	
	# logs
	Debug.info("✓ GDScript Templates Plugin activated")
	Debug.info("  Ctrl+E = Complete code from template")
	Debug.info("  Ctrl+Space = Show available templates")

func _exit_tree():
	remove_tool_menu_item("GDScript Templates Settings")

# TODO: custom shortcut in settings + auto detection?
func _input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed and event.keycode == KEY_E:
			_on_expand_pressed()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_TAB and awaiting_expand:
			_on_expand_pressed()
			get_viewport().set_input_as_handled()
		elif event.ctrl_pressed and event.keycode == KEY_SPACE:
			_show_code_completion()
			get_viewport().set_input_as_handled()

func _on_expand_pressed():
	if try_expand_template():
		Debug.info("✓ Template Completed!")
	else:
		Debug.info("✗ No template found.")

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
	
	# get the last word
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
	
	var popup = PopupPanel.new()
	
	# create window
	popup.title = "GDScript Templates"
	var base_width = int(1200 * size_multiplier)
	var base_height = int(min(matches.size() * 60 + 80, 800) * size_multiplier)
	popup.size = Vector2i(base_width, base_height)
	popup.min_size = Vector2i(int(1000 * size_multiplier), int(400 * size_multiplier))
	popup.borderless = false
	popup.unresizable = false
	popup.wrap_controls = true
	
	# main container
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	# HSplitContainer for list and preview
	var hsplit = HSplitContainer.new()
	hsplit.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	# itemList - Left side
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
	
	# select first item
	if matches.size() > 0:
		item_list.select(0)
		
	item_vbox.add_child(item_list)	
	
	# right side - Preview panel
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
	
	# show first template
	if matches.size() > 0:
		var first_template = templates[matches[0].keyword]
		preview_text.text = first_template
		
		var preview_display = first_template
		var regex = RegEx.new()
		regex.compile("\\{([^}]+)\\}")
		
		for match in regex.search_all(first_template):
			var placeholder = match.get_string(0)
			var param_name = match.get_string(1)
			if param_name != CURSOR:
				preview_display = preview_display.replace(placeholder, param_name)
	
		preview_text.text = preview_display
	
	preview_vbox.add_child(preview_text)	
	preview_panel.add_child(preview_vbox)
	
	# add to split container
	hsplit.add_child(item_vbox)
	hsplit.add_child(preview_panel)
	
	margin.add_child(hsplit)
	
	# update preview when selection changes
	item_list.item_selected.connect(func(index):
		var selected = matches[index]
		var template_text = templates[selected.keyword]
		
		var preview_display = template_text
		var regex = RegEx.new()
		regex.compile("\\{([^}]+)\\}")
		
		for match in regex.search_all(template_text):
			var placeholder = match.get_string(0)  # {name}
			var param_name = match.get_string(1)   # name
			if param_name != CURSOR: 
				preview_display = preview_display.replace(placeholder, param_name)
		
		preview_text.text = preview_display
	)
	
	# signal and enter
	item_list.item_activated.connect(func(index):
		var selected = matches[index]
		_insert_completion(text_edit, partial, selected.keyword)
		popup.queue_free()
	)	
		
	popup.add_child(margin)
	
	# setting up window vs caret possition
	var text_edit_global = text_edit.get_screen_position()
	var caret_line = text_edit.get_caret_line()
	var caret_column = text_edit.get_caret_column()
	var line_height = text_edit.get_line_height()
	var first_visible_line = text_edit.get_first_visible_line()
	
	# caret position
	var char_width = 9
	var caret_x = text_edit_global.x + (caret_column * char_width) + 70
	var caret_y = text_edit_global.y + ((caret_line - first_visible_line) * line_height)
	
	# window offset to not block caret
	var base_offset_y = (line_height * 2) + 40  
	var offset_x = 50  
	var offset_y = int(base_offset_y * (2.0 if is_macos else 1.0))
	
	var x_pos = caret_x + offset_x
	var y_pos = caret_y + offset_y
	
	# outside window placement fix
	var screen_size = DisplayServer.screen_get_size()
	if x_pos + popup.size.x > screen_size.x:
		x_pos = screen_size.x - popup.size.x - 20 
	if y_pos + popup.size.y > screen_size.y:
		y_pos = screen_size.y - popup.size.y - 20
	
	x_pos = max(20, x_pos)
	y_pos = max(20, y_pos)
	
	get_editor_interface().get_base_control().add_child(popup)
	popup.position = Vector2i(x_pos, y_pos)  
	popup.popup()
	
	# set focus for window
	await get_tree().process_frame
	item_list.grab_focus()
	
	# close when focus is lost
	popup.close_requested.connect(func(): popup.queue_free())
	
	# other item_list inputs
	item_list.gui_input.connect(func(event):
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_ESCAPE:
				popup.queue_free()
			elif event.keycode == KEY_TAB:
				var selected_items = item_list.get_selected_items()
				if selected_items.size() > 0:
					var index = selected_items[0]
					var selected = matches[index]
					_insert_completion(text_edit, partial, selected.keyword)
					popup.queue_free()
	)

func _extract_params_from_template(template: String) -> Array:
	var params = []
	var seen_params = {}
	var regex = RegEx.new()
	regex.compile("\\{([^}]+)\\}") 
	
	for result in regex.search_all(template):
		var param_name = result.get_string(1) 
		if param_name != CURSOR:
			if not param_name in seen_params:
				params.append("{" + param_name + "}")
				seen_params[param_name] = true
	
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
		
		awaiting_expand = true
		
		# show hints		
		var template = templates[keyword]
		var params = _extract_params_from_template(template)
		var hint_text = "Params: " + " ".join(params)
				
		_show_parameter_tooltip(text_edit, hint_text)			
	else:
		# template is paramless
		text_edit.select(line_idx, start_col, line_idx, col)
		text_edit.insert_text_at_caret(keyword)
		
		# expand template
		try_expand_template()

func _show_parameter_tooltip(text_edit: TextEdit, hint_text: String):
	
	var tooltip = PanelContainer.new()
	tooltip.name = "ParameterTooltip"
	
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.2, 0.2, 0.2, 0.95)
	style_box.border_color = Color(0.4, 0.6, 1.0)
	
	style_box.set_border_width_all(2)
	style_box.set_corner_radius_all(10)
	
	tooltip.add_theme_stylebox_override("panel", style_box)
	
	var label = Label.new()
	label.text = hint_text
	label.add_theme_font_size_override("font_size", 20 * size_multiplier)
	label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	
	tooltip.add_child(label)	
	text_edit.add_child(tooltip)
	
	await get_tree().process_frame
	var caret_line = text_edit.get_caret_line()
	var caret_column = text_edit.get_caret_column()
	var line_height = text_edit.get_line_height()
	var first_visible = text_edit.get_first_visible_line()
	
	var x_pos = caret_column * 8 + 10
	var y_pos = (caret_line - first_visible + 1) * line_height + 5
	
	tooltip.position = Vector2(x_pos, y_pos)

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
	awaiting_expand = false
	var text_edit = get_current_script_editor()
	if not text_edit:
		Debug.warn("✗ Text Editor not found")
		return false
		
	var tooltip = text_edit.get_node_or_null("ParameterTooltip")
	if tooltip:
		tooltip.queue_free()

	var line_idx = text_edit.get_caret_line()
	var col = text_edit.get_caret_column()
	var line = text_edit.get_line(line_idx)
	
	# get text before cursor
	var text_before_cursor = line.substr(0, col).strip_edges()
	
	# split into words
	var words = text_before_cursor.split(" ", false)
	
	if words.is_empty():
		return false
	
	# find template keyword from right to left
	var keyword = ""
	var params = []
	var keyword_start_idx = -1
	
	for i in range(words.size() - 1, -1, -1):
		var potential_keyword = words[i].to_lower()
		
		# is it a template keyword?
		var is_template = false
		for template_key in templates.keys():
			if template_key.to_lower() == potential_keyword:
				keyword = words[i]
				keyword_start_idx = i
				# everything after is params
				params = words.slice(i + 1)
				is_template = true
				break
		
		if is_template:
			break
	
	if keyword.is_empty():
		return false
	
	Debug.info("Keyword: %s Params: %s" % [keyword, params])
	
	# find exact position of keyword in line
	var template_expression = keyword
	for param in params:
		template_expression += " " + param
	
	# find where this expression starts in text_before_cursor
	var expr_start_in_before_cursor = text_before_cursor.rfind(template_expression)
	
	if expr_start_in_before_cursor == -1:
		# backup - find at least keyword
		expr_start_in_before_cursor = text_before_cursor.rfind(keyword)
		
	# get template
	var found_template = ""
	for template_key in templates.keys():
		if template_key.to_lower() == keyword.to_lower():
			found_template = template_key
			break
	
	if found_template.is_empty():
		return false
	
	# complete template
	var template_text = templates[found_template]
	var expanded = expand_template(template_text, params)
	
	# get indent from keyword position
	var keyword_indent = ""
	var actual_keyword_start = line.find(template_expression)
	
	if actual_keyword_start == -1:
		# Backup - find keyword
		actual_keyword_start = line.find(keyword)
	
	for i in range(actual_keyword_start):
		if line[i] in [' ', '\t']:
			keyword_indent += line[i]
		else:
			break
	
	# fix indent
	expanded = apply_indentation(expanded, keyword_indent)
		
	# delete original text and place update template
	text_edit.begin_complex_operation()
	text_edit.select(line_idx, actual_keyword_start, line_idx, col)
	text_edit.delete_selection()
	text_edit.insert_text_at_caret(expanded)
	
	# place cursor
	position_cursor_with_indent(text_edit, template_text, expanded, line_idx, actual_keyword_start, keyword_indent)
	text_edit.end_complex_operation()
	return true

func expand_template(template: String, params: Array) -> String:
	var result = template
	
	var regex = RegEx.new()
	regex.compile("\\{([^}]+)\\}")
	
	var matches = regex.search_all(template)
	
	# loop placeholders
	for i in range(matches.size()):
		var placeholder = matches[i].get_string(0)  
		var param_name = matches[i].get_string(1)  
		
		if i < params.size():
			# parameter provided - replace placeholder with value
			result = result.replace(placeholder, params[i])
		else:
			# parameter not provided - keep its name
			result = result.replace(placeholder, param_name)
	
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
	
	var line_idx = start_line
	var found = false
	var marker_line = -1
	var marker_col = -1
	
	# Find cursor
	for i in range(20):  
		var line = text_edit.get_line(line_idx + i)
		var pos = line.find(CURSOR_MARKER)
		if pos != -1:
			marker_line = line_idx + i
			marker_col = pos
			found = true
			break
	
	if found:
		# delete marker
		text_edit.select(marker_line, marker_col, marker_line, marker_col + CURSOR_MARKER.length())
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
		templates = FileUtils.load_json_file(FileUtils.CONFIG_PATH)
			
	var user_templates = FileUtils.load_json_file(FileUtils.USER_CONFIG_PATH)
	templates.merge(user_templates, true)
		
	update_code_completion_cache()

func update_code_completion_cache():
	code_completion_prefixes.clear()
	for keyword in templates.keys():
		code_completion_prefixes.append(keyword)

func _open_settings():
	
	# dialog definition
	var dialog = AcceptDialog.new()
	dialog.title = "GDScript Templates Settings"
	dialog.ok_button_text = "Close"
	dialog.add_button("Save", false, "save")
	
	# content definition	
	var vbox = VBoxContainer.new()	
	var label = Label.new()
	
	var hint_text = """
	User Templates (append defaults)
	
	Format: "keyword": "template_code"
	
	Parameters:
		  {name}, {type}, {value}  - Replaced by user input
		  %s                       - Cursor position
	
	Examples:
		  "myvar": "var {name}: {type} = {value}%s"
		  Usage: myvar health int 100
		  Result: var health: int = 100
	
	Tips:
		  • Use \\n for new lines
		  • Use \\t for tabs
		  • Partial params: vec2 10 → Vector2(10, y)
	
	""" % [CURSOR_MARKER, CURSOR_MARKER]

	label.text = "Adjust user templates in JSON format; by default, they are appended to the default templates."
	vbox.add_child(label)
	
	var use_defaults_checkbox = CheckBox.new()
	use_defaults_checkbox.text = "Use default templates"
	use_defaults_checkbox.button_pressed = use_default_templates
	use_defaults_checkbox.tooltip_text = "When enabled, default templates are combined with user templates.\nDisable to use only user templates."
	vbox.add_child(use_defaults_checkbox)
		
	var text_edit = TextEdit.new()
	text_edit.tooltip_text = hint_text
		
	var user_templates_only = FileUtils.load_json_file(FileUtils.USER_CONFIG_PATH)
		
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
					# save file
					FileUtils.save_json_file(new_user_templates, FileUtils.USER_CONFIG_PATH)
			
					load_templates()
					update_code_completion_cache()
					dialog.hide()
					
			else:
				Debug.info("✗ Error in JSON format!")
	)

	dialog.add_child(vbox)
	
	get_editor_interface().popup_dialog_centered(dialog)
			
func load_settings():
	var settings = FileUtils.load_json_file(FileUtils.SETTINGS_PATH)
	if settings.has("use_default_templates"):
		use_default_templates = settings.use_default_templates

func save_settings():
	var settings = {
		"use_default_templates": use_default_templates
	}
	
	FileUtils.save_json_file(settings, FileUtils.SETTINGS_PATH)

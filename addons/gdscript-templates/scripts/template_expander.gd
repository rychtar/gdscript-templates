@tool
extends RefCounted

# Template syntax:
#   {name}    parameter
#   |CURSOR|  caret position after expansion
#   \t        one indent level (converted to spaces if needed)

const CURSOR = "CURSOR"
const CURSOR_MARKER = "|CURSOR|"
const PLACEHOLDER_PATTERN = "\\|CURSOR\\||\\{([A-Za-z_][A-Za-z0-9_]*)\\}"

static var _regex: RegEx

static func _get_regex() -> RegEx:
	if _regex == null:
		_regex = RegEx.create_from_string(PLACEHOLDER_PATTERN)
	return _regex

# unique parameter names in order of first appearance
static func get_params(body: String) -> PackedStringArray:
	var params = PackedStringArray()
	for result in _get_regex().search_all(body):
		var param_name = result.get_string(1)
		if not param_name.is_empty() and param_name != CURSOR and not params.has(param_name):
			params.append(param_name)
	return params

static func get_preview(body: String) -> String:
	return expand(body).text

# returns {text, cursor, stops} - stops are params without a value: [{name, offset, length}]
static func expand(body: String, values: Array = [], indent: String = "", indent_unit: String = "\t") -> Dictionary:
	var params = get_params(body)
	var source = _apply_indentation(body, indent, indent_unit)

	var text = ""
	var stops: Array[Dictionary] = []
	var cursor = -1
	var last_end = 0

	for result in _get_regex().search_all(source):
		text += source.substr(last_end, result.get_start() - last_end)
		last_end = result.get_end()

		var param_name = result.get_string(1)
		if param_name.is_empty() or param_name == CURSOR:
			if cursor == -1:
				cursor = text.length()
			continue

		var index = params.find(param_name)
		if index < values.size():
			text += str(values[index])
		else:
			# no value - keep the name and make it a tab stop
			stops.append({"name": param_name, "offset": text.length(), "length": param_name.length()})
			text += param_name

	text += source.substr(last_end)
	if cursor == -1:
		cursor = text.length()

	return {"text": text, "stops": stops, "cursor": cursor}

# indents all lines except the first one
static func _apply_indentation(body: String, indent: String, indent_unit: String) -> String:
	var lines = body.split("\n")
	for i in range(lines.size()):
		var line = lines[i]
		var tabs = 0
		while tabs < line.length() and line[tabs] == "\t":
			tabs += 1
		line = indent_unit.repeat(tabs) + line.substr(tabs)
		if i > 0 and not line.is_empty():
			line = indent + line
		lines[i] = line
	return "\n".join(lines)

@tool
extends Object

# tools
const Debug = preload("res://addons/gdscript-templates/scripts/debug_utils.gd")

# paths
const CONFIG_PATH: String = "res://addons/gdscript-templates/templates/templates.json"
const USER_CONFIG_PATH: String = "user://code_templates.json"
const SETTINGS_PATH: String = "user://code_templates_settings.json"

static func load_json_file(path: String) -> Dictionary:
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
		Debug.info("✓ %s loaded!" % path)
	
	return {}

static func save_json_file(data: Dictionary, path: String) -> bool:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		Debug.info("✓ %s saved!" % path)
		return true
	
	return false

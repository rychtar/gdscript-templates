@tool
extends RefCounted

# Variables for {@name} in templates:
#   {@filename}  name of the script without the extension: player_controller
#   {@class}     the same in PascalCase: PlayerController
#   {@date}      today, YYYY-MM-DD

# name of a script that has no file (new or built-in into a scene)
const UNSAVED_NAME = "script"

# script_path: path of the script the template is inserted into, "" when unknown
static func build(script_path: String) -> Dictionary:
	# built-in scripts are "res://scene.tscn::GDScript_abc12"
	var filename := script_path.get_file().get_basename() if not script_path.contains("::") else ""
	if filename.is_empty():
		filename = UNSAVED_NAME
	return {
		"filename": filename,
		"class": filename.to_pascal_case(),
		"date": Time.get_date_string_from_system(),
	}

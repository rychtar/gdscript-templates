@tool
extends RefCounted

# User templates live in the editor config folder, so all projects share them.
# Entry: {body, description}. JSON value is a body string or {"body", "description"}.

const FileUtils = preload("res://addons/gdscript-templates/scripts/file_utils.gd")
const Debug = preload("res://addons/gdscript-templates/scripts/debug_utils.gd")

const DEFAULTS_PATH = "res://addons/gdscript-templates/templates/templates.json"
const USER_FILE_NAME = "gdscript_templates.json"

# 1.0 user templates (per project)
const LEGACY_USER_PATH = "user://code_templates.json"

var defaults: Dictionary = {}
var user: Dictionary = {}
var use_defaults: bool = true

# defaults merged with user templates
var templates: Dictionary = {}

static func get_user_path() -> String:
	return EditorInterface.get_editor_paths().get_config_dir().path_join(USER_FILE_NAME)

func load_templates() -> void:
	defaults = normalize(FileUtils.load_json_file(DEFAULTS_PATH))

	var user_path = get_user_path()
	if not FileAccess.file_exists(user_path) and FileAccess.file_exists(LEGACY_USER_PATH):
		var legacy = FileUtils.load_json_file(LEGACY_USER_PATH)
		if not legacy.is_empty() and FileUtils.save_json_file(legacy, user_path):
			Debug.info("✓ User templates migrated to %s" % user_path)

	user = normalize(FileUtils.load_json_file(user_path))
	rebuild()

func rebuild() -> void:
	templates = defaults.duplicate(true) if use_defaults else {}
	templates.merge(user, true)

func save_user_templates(new_user: Dictionary) -> bool:
	user = new_user.duplicate(true)
	rebuild()
	return FileUtils.save_json_file(serialize(user), get_user_path())

# case insensitive, "" when not found
func find_keyword(word: String) -> String:
	if templates.has(word):
		return word
	var word_lower = word.to_lower()
	for keyword in templates:
		if keyword.to_lower() == word_lower:
			return keyword
	return ""

static func normalize(raw: Dictionary) -> Dictionary:
	var result = {}
	for keyword in raw:
		var value = raw[keyword]
		if value is String:
			result[keyword] = {"body": value, "description": ""}
		elif value is Dictionary and value.has("body"):
			result[keyword] = {"body": str(value.body), "description": str(value.get("description", ""))}
		else:
			push_warning("GDScript Templates: invalid template \"%s\" skipped" % keyword)
	return result

static func serialize(entries: Dictionary) -> Dictionary:
	var result = {}
	for keyword in entries:
		var entry = entries[keyword]
		if entry.description.is_empty():
			result[keyword] = entry.body
		else:
			result[keyword] = {"body": entry.body, "description": entry.description}
	return result

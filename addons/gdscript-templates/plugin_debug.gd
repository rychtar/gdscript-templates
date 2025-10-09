@tool
extends Object

# debug is enabled only for this project
const EXPECTED_PROJECT_NAME := "gdscript-templates"

static var ENABLE_DEBUG := _detect_dev_mode()

static func _detect_dev_mode() -> bool:
	var project_name = ProjectSettings.get("application/config/name")	
	return project_name == EXPECTED_PROJECT_NAME

static func log(msg: String) -> void:
	if ENABLE_DEBUG:
		print("[gdscript-templates:LOG] %s" % msg)

static func info(msg: String) -> void:
	if ENABLE_DEBUG:
		print("[gdscript-templates:INFO] %s" % msg)

static func warn(msg: String) -> void:
	if ENABLE_DEBUG:
		push_warning("[code-templates-plugin:WARN] %s" % msg)
		print("[gdscript-templates:WARN] %s" % msg)


static func error(msg: String) -> void:
	if ENABLE_DEBUG:
		push_error("[code-templates-plugin:ERROR] %s" % msg)
		print("[gdscript-templates:ERROR] %s" % msg)
		

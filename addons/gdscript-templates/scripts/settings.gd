@tool
extends RefCounted

# Editor Settings > Plugins > GDScript Templates

const PREFIX = "plugins/gdscript_templates/"
const USE_DEFAULT_TEMPLATES = PREFIX + "use_default_templates"
const SHOW_IN_CODE_COMPLETION = PREFIX + "show_in_code_completion"
const SHORTCUT_SHOW = PREFIX + "show_templates_shortcut"
const SHORTCUT_EXPAND = PREFIX + "expand_template_shortcut"

static func register() -> void:
	var settings = EditorInterface.get_editor_settings()

	_add_setting(settings, USE_DEFAULT_TEMPLATES, true, TYPE_BOOL)
	_add_setting(settings, SHOW_IN_CODE_COMPLETION, true, TYPE_BOOL)

	_add_shortcut_setting(settings, SHORTCUT_SHOW, KEY_SPACE)
	_add_shortcut_setting(settings, SHORTCUT_EXPAND, KEY_E)

# the setting and its initial value are separate instances - the inspector edits the shortcut in place
static func _add_shortcut_setting(settings: EditorSettings, name: String, keycode: Key) -> void:
	if not settings.has_setting(name):
		settings.set_setting(name, _create_shortcut(keycode))
	_add_setting(settings, name, _create_shortcut(keycode), TYPE_OBJECT, PROPERTY_HINT_RESOURCE_TYPE, "Shortcut")

static func _add_setting(settings: EditorSettings, name: String, default_value, type: int, hint: int = PROPERTY_HINT_NONE, hint_string: String = "") -> void:
	if not settings.has_setting(name):
		settings.set_setting(name, default_value)
	settings.set_initial_value(name, default_value, false)
	settings.add_property_info({"name": name, "type": type, "hint": hint, "hint_string": hint_string})

static func _create_shortcut(keycode: Key) -> Shortcut:
	var event = InputEventKey.new()
	event.keycode = keycode
	event.ctrl_pressed = true

	var shortcut = Shortcut.new()
	shortcut.events = [event]
	return shortcut

static func matches_shortcut(path: String, event: InputEvent) -> bool:
	var shortcut = EditorInterface.get_editor_settings().get_setting(path)
	return shortcut is Shortcut and shortcut.matches_event(event)

static func create_gdscript_highlighter() -> SyntaxHighlighter:
	if ClassDB.class_exists("GDScriptSyntaxHighlighter"):
		return ClassDB.instantiate("GDScriptSyntaxHighlighter")
	return null

static func use_default_templates() -> bool:
	return EditorInterface.get_editor_settings().get_setting(USE_DEFAULT_TEMPLATES)

static func show_in_code_completion() -> bool:
	return EditorInterface.get_editor_settings().get_setting(SHOW_IN_CODE_COMPLETION)

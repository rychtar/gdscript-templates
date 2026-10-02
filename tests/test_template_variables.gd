extends "res://tests/assertions.gd"

const Variables = preload("res://addons/gdscript-templates/scripts/template_variables.gd")
const TemplateStore = preload("res://addons/gdscript-templates/scripts/template_store.gd")

func test_filename_and_class() -> void:
	var variables := Variables.build("res://scripts/player_controller.gd")
	check("filename", variables.filename, "player_controller")
	check("class", variables.class, "PlayerController")

func test_script_without_a_file() -> void:
	check("no path", Variables.build("").filename, "script")
	check("built-in script", Variables.build("res://main.tscn::GDScript_abc12").filename, "script")
	check("class of an unsaved script", Variables.build("").class, "Script")

func test_date() -> void:
	var date: String = Variables.build("").date
	check("format", RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$").search(date) != null, true)

func test_default_templates_use_known_variables() -> void:
	var known := Variables.build("").keys()
	var regex := RegEx.create_from_string("\\{@(\\w+)\\}")
	var templates := TemplateStore.normalize(JSON.parse_string(FileAccess.get_file_as_string(TemplateStore.DEFAULTS_PATH)))
	for keyword in templates:
		for found in regex.search_all(templates[keyword].body):
			check("variable %s in template %s" % [found.get_string(1), keyword], known.has(found.get_string(1)), true)


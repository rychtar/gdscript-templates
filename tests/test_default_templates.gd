extends "res://tests/assertions.gd"

const Expander = preload("res://addons/gdscript-templates/scripts/template_expander.gd")
const TemplateStore = preload("res://addons/gdscript-templates/scripts/template_store.gd")

func _defaults() -> Dictionary:
	return TemplateStore.normalize(JSON.parse_string(FileAccess.get_file_as_string(TemplateStore.DEFAULTS_PATH)))

func test_every_template_expands_cleanly() -> void:
	# |CURSOR|, {@variable}, {name}, {name=x} and {name|a,b} must all be gone
	var leftover := RegEx.create_from_string("\\|CURSOR\\||\\{@|\\{[A-Za-z_]\\w*[=|}]")
	var templates := _defaults()
	for keyword in templates:
		var text: String = Expander.expand(templates[keyword].body, [], "", "\t", "code", {"filename": "f", "class": "F", "date": "d"}).text
		check("template %s has no placeholder left" % keyword, leftover.search(text) == null, true)
		check("template %s has a description and a category" % keyword,
			not templates[keyword].description.is_empty() and not templates[keyword].category.is_empty(), true)

func test_choices_are_valid() -> void:
	var templates := _defaults()
	for keyword in templates:
		var body: String = templates[keyword].body
		var choices := Expander.get_choices(body)
		var defaults := Expander.get_defaults(body)
		for param in choices:
			check("template %s: the default of %s is its first choice" % [keyword, param], defaults[param], choices[param][0])

func test_templates_with_choices_expand_as_before() -> void:
	var templates := _defaults()
	check("export", Expander.expand(templates.export.body, ["speed"]).text, "@export var speed: float")
	check("const", Expander.expand(templates["const"].body, ["MAX"]).text, "const MAX: int = ")
	check("func", Expander.expand(templates["func"].body, ["jump"]).text, "func jump() -> void:\n\t")
	check("mouse button", Expander.expand(templates.ims.body).text, "Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)")

func test_choices_in_templates() -> void:
	var templates := _defaults()
	check("export type", Expander.get_choices(templates.export.body).type.size() > 3, true)
	check("return type", Expander.get_choices(templates["func"].body).return_type[0], "void")
	check("mouse button", Expander.get_choices(templates.ims.body).button, PackedStringArray(["LEFT", "RIGHT", "MIDDLE"]))

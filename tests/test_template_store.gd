extends "res://tests/assertions.gd"

const TemplateStore = preload("res://addons/gdscript-templates/scripts/template_store.gd")
const CompletionPopup = preload("res://addons/gdscript-templates/scripts/completion_popup.gd")

# invalid entries print warnings
func test_normalize() -> void:
	var result = TemplateStore.normalize({
		"a": "body",
		"b": {"body": "x", "description": "d", "category": "c"},
		"c": {"body": "y"},
		"bad": 5,
		"bad2": {"description": "no body"},
	})
	check("string is a body", result.a, {"body": "body", "description": "", "category": ""})
	check("full entry", result.b, {"body": "x", "description": "d", "category": "c"})
	check("missing fields", result.c, {"body": "y", "description": "", "category": ""})
	check("invalid ones are skipped", result.keys(), ["a", "b", "c"])

func test_serialize_roundtrip() -> void:
	var entries = {
		"a": {"body": "x", "description": "", "category": ""},
		"b": {"body": "y", "description": "d", "category": ""},
		"c": {"body": "z", "description": "", "category": "cat"},
	}
	var serialized = TemplateStore.serialize(entries)
	check("plain body is a string", serialized.a, "x")
	check("only filled fields", serialized.b, {"body": "y", "description": "d"})
	check("category only", serialized.c, {"body": "z", "category": "cat"})
	check("roundtrip", TemplateStore.normalize(serialized), entries)

func test_find_keyword() -> void:
	var store = TemplateStore.new()
	store.templates = {"Timer": {}, "vec": {}}
	check("exact", store.find_keyword("vec"), "vec")
	check("case insensitive", store.find_keyword("timer"), "Timer")
	check("case sensitive only", store.find_keyword("timer", true), "")
	check("unknown", store.find_keyword("nope"), "")

func test_rebuild_priority() -> void:
	var store = TemplateStore.new()
	store.defaults = TemplateStore.normalize({"a": {"body": "default", "category": "Cat"}, "b": "default"})
	store.user = TemplateStore.normalize({"a": "user", "b": "user"})
	store.project = TemplateStore.normalize({"b": "project"})
	store.rebuild()
	check("user overrides default, keeps the category", store.templates.a, {"body": "user", "description": "", "category": "Cat"})
	check("project overrides user", store.templates.b.body, "project")

	store.use_defaults = false
	store.rebuild()
	check("without defaults the category is not taken", store.templates.a.category, "")

func test_match_score() -> void:
	var exact = CompletionPopup.match_score("vec", "vec", "")
	var prefix = CompletionPopup.match_score("ve", "vec", "")
	var contains = CompletionPopup.match_score("ec", "vec", "")
	var fuzzy = CompletionPopup.match_score("vc", "vec", "")
	var description = CompletionPopup.match_score("point", "vec", "A point")
	check("ranking", exact > prefix and prefix > contains and contains > fuzzy and fuzzy > description and description > 0, true)
	check("no match", CompletionPopup.match_score("xyz", "vec", ""), -1)
	check("kinds", [exact, prefix, contains, fuzzy, description].map(CompletionPopup.match_kind), [4, 3, 2, 1, 0])

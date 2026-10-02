extends "res://tests/assertions.gd"

const TemplateStore = preload("res://addons/gdscript-templates/scripts/template_store.gd")
const CompletionPopup = preload("res://addons/gdscript-templates/scripts/completion_popup.gd")

# invalid entries print warnings
func test_normalize() -> void:
	var result := TemplateStore.normalize({
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
	var entries := {
		"a": {"body": "x", "description": "", "category": ""},
		"b": {"body": "y", "description": "d", "category": ""},
		"c": {"body": "z", "description": "", "category": "cat"},
	}
	var serialized := TemplateStore.serialize(entries)
	check("plain body is a string", serialized.a, "x")
	check("only filled fields", serialized.b, {"body": "y", "description": "d"})
	check("category only", serialized.c, {"body": "z", "category": "cat"})
	check("roundtrip", TemplateStore.normalize(serialized), entries)

func test_find_keyword() -> void:
	var store := TemplateStore.new()
	store.templates = {"Timer": {}, "vec": {}}
	check("exact", store.find_keyword("vec"), "vec")
	check("case insensitive", store.find_keyword("timer"), "Timer")
	check("case sensitive only", store.find_keyword("timer", true), "")
	check("unknown", store.find_keyword("nope"), "")

func test_rebuild_priority() -> void:
	var store := TemplateStore.new()
	store.defaults = TemplateStore.normalize({"a": {"body": "default", "category": "Cat"}, "b": "default"})
	store.user = TemplateStore.normalize({"a": "user", "b": "user"})
	store.project = TemplateStore.normalize({"b": "project"})
	store.rebuild()
	check("user overrides default, keeps the category", store.templates.a, {"body": "user", "description": "", "category": "Cat"})
	check("project overrides user", store.templates.b.body, "project")

	store.use_defaults = false
	store.rebuild()
	check("without defaults the category is not taken", store.templates.a.category, "")

# a store that uses files in a temporary folder
func _make_store(dir: String) -> TemplateStore:
	var store := TemplateStore.new()
	store.use_defaults = false
	store.user_path = dir.path_join("user.json")
	store.project_path = dir.path_join("project.json")
	store.usage_path = dir.path_join("usage.json")
	return store

func test_load_merges_the_files() -> void:
	var dir := make_temp_dir()
	write_file(dir.path_join("user.json"), '{"a": "user", "b": "user"}')
	write_file(dir.path_join("project.json"), '{"b": {"body": "project", "category": "Team"}}')
	write_file(dir.path_join("usage.json"), '{"a": 3}')
	var store := _make_store(dir)
	store.load_templates()
	check("keywords", store.templates.keys(), ["a", "b"])
	check("project overrides user", store.templates.b, {"body": "project", "description": "", "category": "Team"})
	check("usage", int(store.usage.a), 3)

func test_missing_files_are_empty() -> void:
	var store := _make_store(make_temp_dir())
	store.load_templates()
	check("no templates", store.templates, {})
	check("no usage", store.usage, {})

func test_save_and_load_again() -> void:
	var dir := make_temp_dir()
	var store := _make_store(dir)
	store.load_templates()
	var entry := {"body": "x", "description": "d", "category": "c"}
	check("saved", store.save_templates({"mine": entry}, {"shared": entry}), true)

	var other := _make_store(dir)
	other.load_templates()
	check("user", other.user, {"mine": entry})
	check("project", other.project, {"shared": entry})

func test_no_empty_project_file() -> void:
	var dir := make_temp_dir()
	var store := _make_store(dir)
	store.load_templates()
	store.save_templates({"mine": {"body": "x", "description": "", "category": ""}}, {})
	check("user file", FileAccess.file_exists(store.user_path), true)
	check("no project file", FileAccess.file_exists(store.project_path), false)

func test_project_file_is_emptied_when_it_exists() -> void:
	var dir := make_temp_dir()
	write_file(dir.path_join("project.json"), '{"b": "project"}')
	var store := _make_store(dir)
	store.load_templates()
	store.save_templates({}, {})
	var other := _make_store(dir)
	other.load_templates()
	check("project templates removed from the file", other.project, {})

# the files keep the modified time in seconds, so the stored time is made older instead of waiting
func test_reload_if_changed() -> void:
	var dir := make_temp_dir()
	write_file(dir.path_join("user.json"), '{"a": "one"}')
	var store := _make_store(dir)
	store.load_templates()
	check("nothing changed", store.reload_if_changed(), false)

	write_file(dir.path_join("user.json"), '{"a": "two"}')
	store._loaded_times[store.user_path] = -1
	check("changed", store.reload_if_changed(), true)
	check("reloaded", store.templates.a.body, "two")
	check("only once", store.reload_if_changed(), false)

func test_usage_is_counted_and_saved_when_changed() -> void:
	var dir := make_temp_dir()
	var store := _make_store(dir)
	store.load_templates()
	store.save_usage()
	check("nothing to save", FileAccess.file_exists(store.usage_path), false)

	store.record_use("a")
	store.record_use("a")
	store.record_use("b")
	check("counted", store.usage, {"a": 2, "b": 1})
	check("not saved yet", FileAccess.file_exists(store.usage_path), false)
	store.save_usage()
	var other := _make_store(dir)
	other.load_templates()
	check("saved", [int(other.usage.a), int(other.usage.b)], [2, 1])

	DirAccess.remove_absolute(store.usage_path)
	store.save_usage()
	check("not written again", FileAccess.file_exists(store.usage_path), false)

func test_categories_order() -> void:
	var store := TemplateStore.new()
	store.defaults = TemplateStore.normalize({
		"a": {"body": "x", "category": "Second"},
		"b": {"body": "x", "category": "First"},
	})
	store.user = TemplateStore.normalize({
		"c": {"body": "x", "category": "Zoo"},
		"d": {"body": "x", "category": "Apple"},
		"e": "no category",
		"f": {"body": "x", "category": "First"},
	})
	store.rebuild()
	check("defaults in their order, others alphabetically, no category last",
		store.get_categories(), PackedStringArray(["Second", "First", "Apple", "Zoo", ""]))


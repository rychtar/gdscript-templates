extends "res://tests/assertions.gd"

const Catalog = preload("res://addons/gdscript-templates/scripts/template_catalog.gd")

func _entry(body: String, description: String = "", category: String = "") -> Dictionary:
	return {"body": body, "description": description, "category": category}

func _catalog(user: Dictionary = {}, project: Dictionary = {}, use_defaults: bool = true) -> Catalog:
	var defaults := {
		"alpha": _entry("A", "First one", "Letters"),
		"beta": _entry("B", "", "Letters"),
		"one": _entry("1", "Number", "Digits"),
	}
	return Catalog.new(defaults, user, project, use_defaults)

func test_keywords_are_sorted_and_merged() -> void:
	var catalog := _catalog({"zed": _entry("z")}, {"gamma": _entry("g")})
	check("all", catalog.keywords(), ["alpha", "beta", "gamma", "one", "zed"])
	check("without defaults", _catalog({"zed": _entry("z")}, {}, false).keywords(), ["zed"])

func test_keywords_filter() -> void:
	var catalog := _catalog()
	check("keyword", catalog.keywords("ALP"), ["alpha"])
	check("description", catalog.keywords("number"), ["one"])
	check("category", catalog.keywords(" letters "), ["alpha", "beta"])
	check("nothing", catalog.keywords("zzz"), [])

func test_kind_and_scope() -> void:
	var catalog := _catalog({"alpha": _entry("changed"), "mine": _entry("m")}, {"shared": _entry("s")})
	check("default", catalog.kind("beta"), Catalog.KIND_DEFAULT)
	check("modified", catalog.kind("alpha"), Catalog.KIND_MODIFIED)
	check("custom", catalog.kind("mine"), Catalog.KIND_CUSTOM)
	check("scope of a user template", catalog.scope("mine"), Catalog.SCOPE_ALL)
	check("scope of a project template", catalog.scope("shared"), Catalog.SCOPE_PROJECT)
	check("with defaults off a changed default is custom", _catalog({"alpha": _entry("x")}, {}, false).kind("alpha"), Catalog.KIND_CUSTOM)

func test_entry_and_override() -> void:
	var catalog := _catalog({"alpha": _entry("user")}, {"alpha": _entry("project")})
	check("project wins", catalog.entry("alpha").body, "project")
	check("default", catalog.entry("beta").body, "B")

func test_editing_entry_offers_the_original_category() -> void:
	var catalog := _catalog({"alpha": _entry("x"), "mine": _entry("m")})
	check("a changed default without a category", catalog.editing_entry("alpha").category, "Letters")
	check("a custom one is as it is", catalog.editing_entry("mine").category, "")
	check("the stored entry is not touched", catalog.entry("alpha").category, "")

func test_set_entry() -> void:
	var catalog := _catalog()
	catalog.set_entry("alpha", _entry("mine", "First one", "Letters"))
	check("a changed default is saved as a user template", catalog.user.keys(), ["alpha"])
	check("modified", catalog.kind("alpha"), Catalog.KIND_MODIFIED)
	catalog.set_entry("alpha", _entry("A", "First one", "Letters"))
	check("the original content removes it again", catalog.user, {})
	check("default", catalog.kind("alpha"), Catalog.KIND_DEFAULT)

func test_set_entry_stays_in_the_project() -> void:
	var catalog := _catalog({}, {"shared": _entry("s")})
	catalog.set_entry("shared", _entry("changed"))
	check("project template", catalog.project.shared.body, "changed")
	check("not in user", catalog.user, {})

func test_validate_keyword() -> void:
	var catalog := _catalog({"mine": _entry("m")})
	check("fine", catalog.validate_keyword("new_one", "mine"), "")
	check("the same keyword", catalog.validate_keyword("mine", "mine"), "")
	check("empty", catalog.validate_keyword("", "mine"), "Keyword can't be empty.")
	check("space", catalog.validate_keyword("a b", "mine"), "Keyword can't contain spaces.")
	check("tab", catalog.validate_keyword("a\tb", "mine"), "Keyword can't contain spaces.")
	check("taken by a default", catalog.validate_keyword("alpha", "mine"), "Template \"alpha\" already exists.")
	check("a default that is turned off is free", _catalog({"mine": _entry("m")}, {}, false).validate_keyword("alpha", "mine"), "")

func test_unique_keyword() -> void:
	var catalog := _catalog({"new_template": _entry("x"), "new_template_2": _entry("x")})
	check("free", catalog.unique_keyword("fresh"), "fresh")
	check("taken", catalog.unique_keyword("new_template"), "new_template_3")
	check("taken by a default", catalog.unique_keyword("alpha"), "alpha_2")

func test_add() -> void:
	var catalog := _catalog()
	check("keyword", catalog.add(), "new_template")
	check("second", catalog.add(), "new_template_2")
	check("a custom user template", [catalog.kind("new_template"), catalog.entry("new_template").body], [Catalog.KIND_CUSTOM, "|CURSOR|"])

func test_duplicate() -> void:
	var catalog := _catalog({"mine": _entry("m")}, {"shared": _entry("s")})
	check("user", catalog.duplicate("mine"), "mine_copy")
	check("it is a copy", catalog.entry("mine_copy"), _entry("m"))
	check("project", catalog.duplicate("shared"), "shared_copy")
	check("a copy of a project template stays in the project", catalog.scope("shared_copy"), Catalog.SCOPE_PROJECT)
	check("a copy of a default is a user template", [catalog.duplicate("beta"), catalog.scope("beta_copy")], ["beta_copy", Catalog.SCOPE_ALL])
	check("a copy of a copy", catalog.duplicate("mine"), "mine_copy_2")

func test_remove_and_revert() -> void:
	var catalog := _catalog({"mine": _entry("m"), "alpha": _entry("changed")})
	catalog.remove("mine")
	check("a custom template is gone", catalog.exists("mine"), false)
	catalog.remove("alpha")
	check("a changed default is restored", [catalog.exists("alpha"), catalog.kind("alpha")], [true, Catalog.KIND_DEFAULT])
	catalog.remove("beta")
	check("a default can't be removed", catalog.exists("beta"), true)

func test_remove_a_user_template_hidden_by_a_project_one() -> void:
	var catalog := _catalog({"x": _entry("user")}, {"x": _entry("project")})
	catalog.remove("x")
	check("the project template is removed first", [catalog.project, catalog.entry("x").body], [{}, "user"])

func test_rename() -> void:
	var catalog := _catalog({"mine": _entry("m")}, {"shared": _entry("s")})
	catalog.rename("mine", "yours")
	catalog.rename("shared", "team")
	check("user", catalog.user.keys(), ["yours"])
	check("project", catalog.project.keys(), ["team"])
	check("content is kept", catalog.entry("yours"), _entry("m"))

func test_move_to_scope() -> void:
	var catalog := _catalog({"mine": _entry("m")})
	check("moved", catalog.move_to_scope("mine", Catalog.SCOPE_PROJECT), "")
	check("now in the project", [catalog.user, catalog.project.keys()], [{}, ["mine"]])
	check("and back", catalog.move_to_scope("mine", Catalog.SCOPE_ALL), "")
	check("in user", [catalog.user.keys(), catalog.project], [["mine"], {}])
	check("the same scope", catalog.move_to_scope("mine", Catalog.SCOPE_ALL), "")
	check("a default has no scope to change", [catalog.move_to_scope("beta", Catalog.SCOPE_PROJECT), catalog.project], ["", {}])

func test_move_to_scope_does_not_overwrite() -> void:
	# the same keyword in both files, the project one is shown
	var catalog := _catalog({"x": _entry("user")}, {"x": _entry("project")})
	check("error", catalog.move_to_scope("x", Catalog.SCOPE_ALL), "\"x\" already exists in \"All projects\".")
	check("nothing moved", [catalog.user.x.body, catalog.project.x.body], ["user", "project"])

func test_has_changes() -> void:
	var catalog := _catalog({"mine": _entry("m")})
	check("nothing changed", catalog.has_changes(), false)
	catalog.set_entry("mine", _entry("other"))
	check("changed", catalog.has_changes(), true)
	catalog.set_entry("mine", _entry("m"))
	check("changed back", catalog.has_changes(), false)
	catalog.add()
	check("added", catalog.has_changes(), true)

func test_the_given_templates_are_copied() -> void:
	var user := {"mine": _entry("m")}
	var catalog := _catalog(user)
	catalog.set_entry("mine", _entry("changed"))
	check("the original dictionary is not changed", user.mine.body, "m")

func test_categories() -> void:
	var catalog := _catalog({"mine": _entry("m", "", "Mine")}, {"shared": _entry("s", "", "Letters")})
	check("defaults first, no duplicates", catalog.categories(), PackedStringArray(["Letters", "Digits", "Mine"]))

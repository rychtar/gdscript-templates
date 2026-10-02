extends "res://tests/assertions.gd"

const CompletionPopup = preload("res://addons/gdscript-templates/scripts/completion_popup.gd")

func _template(body: String, description: String = "", category: String = "") -> Dictionary:
	return {"body": body, "description": description, "category": category}

func test_match_score() -> void:
	var exact := CompletionPopup.match_score("vec", "vec", "")
	var prefix := CompletionPopup.match_score("ve", "vec", "")
	var contains := CompletionPopup.match_score("ec", "vec", "")
	var fuzzy := CompletionPopup.match_score("vc", "vec", "")
	var description := CompletionPopup.match_score("point", "vec", "A point")
	check("ranking", exact > prefix and prefix > contains and contains > fuzzy and fuzzy > description and description > 0, true)
	check("no match", CompletionPopup.match_score("xyz", "vec", ""), -1)
	check("kinds", [exact, prefix, contains, fuzzy, description].map(CompletionPopup.match_kind), [4, 3, 2, 1, 0])

func test_rank_by_kind_of_match() -> void:
	var templates := {
		"a_vec": _template("x"), "vector": _template("x"), "vec": _template("x"), "v_e_c": _template("x"), "other": _template("x"),
	}
	check("exact, prefix, contains, fuzzy, no match is left out",
		CompletionPopup.rank_templates(templates, "vec", {}, 0, ""), ["vec", "vector", "a_vec", "v_e_c"])

func test_rank_description_and_category_match() -> void:
	var templates := {"a": _template("x", "Draws a line"), "b": _template("x", "", "Lines"), "c": _template("x")}
	check("found by description and category",
		CompletionPopup.rank_templates(templates, "line", {}, 0, ""), ["a", "b"])

func test_rank_prefers_templates_that_take_all_typed_values() -> void:
	var templates := {"f1": _template("{a}"), "f2": _template("{a} {b}")}
	check("one value", CompletionPopup.rank_templates(templates, "f", {}, 1, ""), ["f1", "f2"])
	check("two values", CompletionPopup.rank_templates(templates, "f", {}, 2, ""), ["f2", "f1"])

func test_rank_prefers_templates_that_wrap_the_selection() -> void:
	var templates := {"w1": _template("plain"), "w2": _template("{selection}")}
	check("without selection", CompletionPopup.rank_templates(templates, "w", {}, 0, ""), ["w1", "w2"])
	check("with selection", CompletionPopup.rank_templates(templates, "w", {}, 0, "code"), ["w2", "w1"])

func test_rank_prefers_used_templates_then_alphabetical() -> void:
	var templates := {"ab": _template("x"), "ac": _template("x"), "ad": _template("x")}
	check("alphabetical", CompletionPopup.rank_templates(templates, "a", {}, 0, ""), ["ab", "ac", "ad"])
	check("by use", CompletionPopup.rank_templates(templates, "a", {"ad": 5, "ac": 2}, 0, ""), ["ad", "ac", "ab"])

func test_most_used() -> void:
	var templates := {"a": _template("x"), "b": _template("x"), "c": _template("x"), "d": _template("x")}
	var usage := {"a": 1, "b": 4, "c": 4, "d": 0, "gone": 9}
	check("most used first, ties alphabetically, unused and unknown left out",
		CompletionPopup.most_used(templates, usage, 5), ["b", "c", "a"])
	check("limit", CompletionPopup.most_used(templates, usage, 2), ["b", "c"])

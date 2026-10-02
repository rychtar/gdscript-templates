extends "res://tests/assertions.gd"

const CaretContext = preload("res://addons/gdscript-templates/scripts/caret_context.gd")

const KEYWORDS = ["timer", "vec", "if", "onready"]

func _find_keyword(word: String, case_sensitive: bool) -> String:
	for keyword in KEYWORDS:
		if keyword == word or (not case_sensitive and keyword == word.to_lower()):
			return keyword
	return ""

func _find(text: String) -> Dictionary:
	return CaretContext.find_keyword_before_caret(make_edit(text), _find_keyword)

func test_find_keyword_with_params() -> void:
	var found = _find("\tvec 1 \"a b\"")
	check("keyword", found.keyword, "vec")
	check("start", found.start_column, 1)
	check("params", found.params, ["1", "a b"])
	check("raw params", found.raw_params, ["1", "\"a b\""])

func test_find_keyword_exact_match_wins() -> void:
	# "timer" is the keyword, the type "Timer" is its parameter
	var found = _find("onready timer Timer")
	check("keyword", found.keyword, "timer")
	check("params", found.params, ["Timer"])

func test_find_keyword_case_insensitive() -> void:
	check("keyword", _find("x = Timer").get("keyword"), "timer")

func test_find_keyword_none() -> void:
	check("no keyword", _find("foo bar"), {})

func test_find_keyword_ignores_comments_and_strings() -> void:
	check("comment", _find("# vec 1"), {})
	check("string", _find("print(\"vec 1"), {})
	check("single quotes", _find("print('vec 1"), {})

func test_ends_in_string_or_comment() -> void:
	check("open string", CaretContext.ends_in_string_or_comment("a 'b"), true)
	check("closed string", CaretContext.ends_in_string_or_comment("a 'b'"), false)
	check("escaped quote", CaretContext.ends_in_string_or_comment("\"a\\\""), true)
	check("comment", CaretContext.ends_in_string_or_comment("a # b"), true)

func test_word_before_caret() -> void:
	check("word", CaretContext.word_before_caret(make_edit("x = foo")), {"text": "foo", "start_column": 4})
	check("none", CaretContext.word_before_caret(make_edit("x = ")), {"text": "", "start_column": 4})

func test_completion_word() -> void:
	check("word", CaretContext.completion_word(make_edit("var a = vec")), "vec")
	check("start of line", CaretContext.completion_word(make_edit("vec")), "vec")
	check("after a dot", CaretContext.completion_word(make_edit("a.vec")), "")
	check("after $", CaretContext.completion_word(make_edit("$vec")), "")

func test_popup_target_keyword() -> void:
	var target = CaretContext.get_popup_target(make_edit("\tvec 1"), _find_keyword)
	check("replaces the keyword with params", [target.from, target.to], [Vector2i(0, 1), Vector2i(0, 6)])
	check("params go into the filter", target.filter, "vec 1")
	check("no selection", target.selection, "")

func test_popup_target_word() -> void:
	var target = CaretContext.get_popup_target(make_edit("x = fo"), _find_keyword)
	check("replaces the word", [target.from, target.to], [Vector2i(0, 4), Vector2i(0, 6)])
	check("filter", target.filter, "fo")

func test_popup_target_nothing_typed() -> void:
	var target = CaretContext.get_popup_target(make_edit("x = "), _find_keyword)
	check("inserts at the caret", [target.from, target.to], [Vector2i(0, 4), Vector2i(0, 4)])
	check("filter", target.filter, "")

func test_popup_target_selection() -> void:
	var edit = make_edit("\ta = 1\n\t\tb = 2\n\tc = 3")
	edit.select(0, 1, 2, 6)
	var target = CaretContext.get_popup_target(edit, _find_keyword)
	check("range", [target.from, target.to], [Vector2i(0, 1), Vector2i(2, 6)])
	check("selection is dedented", target.selection, "a = 1\n\tb = 2\nc = 3")

func test_popup_target_whole_line_selection() -> void:
	# a selection ending at the start of the next line is the line before it
	var edit = make_edit("\ta = 1\n\tb = 2")
	edit.select(0, 0, 1, 0)
	var target = CaretContext.get_popup_target(edit, _find_keyword)
	check("range", [target.from, target.to], [Vector2i(0, 1), Vector2i(0, 6)])
	check("selection", target.selection, "a = 1")

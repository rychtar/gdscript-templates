extends "res://tests/assertions.gd"

const Expander = preload("res://addons/gdscript-templates/scripts/template_expander.gd")

func test_get_params() -> void:
	check("unique, in order, without selection and cursor",
		Expander.get_params("{a} {b=1} {a} {selection} |CURSOR|"), PackedStringArray(["a", "b"]))

func test_get_defaults() -> void:
	check("first default wins, empty default",
		Expander.get_defaults("{a=x} {a=y} {b=} {c}"), {"a": "x", "b": ""})

func test_uses_selection() -> void:
	check("with selection", Expander.uses_selection("if x:\n\t{selection}"), true)
	check("without selection", Expander.uses_selection("if {x}:"), false)

func test_format_params() -> void:
	check("params", Expander.format_params("{a} {b=1} {a}"), "{a} {b}")
	check("separator", Expander.format_params("{a} {b}", "  "), "{a}  {b}")
	check("none", Expander.format_params("x"), "")

func test_leading_whitespace() -> void:
	check("tabs and spaces", Expander.leading_whitespace("\t  x "), "\t  ")
	check("none", Expander.leading_whitespace("x"), "")
	check("only whitespace", Expander.leading_whitespace("  "), "  ")

func test_split_args() -> void:
	var args = Expander.split_args("a \"b c\" d")
	check("values", args.map(func(arg): return arg.value), ["a", "b c", "d"])
	check("raw keeps quotes", args.map(func(arg): return arg.raw), ["a", "\"b c\"", "d"])
	check("unclosed quote runs to the end", Expander.split_args("a \"b c").map(func(arg): return arg.value), ["a", "b c"])

func test_expand_values_and_defaults() -> void:
	check("given value, default", Expander.expand("vec {x=1} {y=2}", ["5"]).text, "vec 5 2")
	check("name when there is no default", Expander.expand("f({x})").text, "f(x)")

func test_expand_stops() -> void:
	var result = Expander.expand("{a} {b=1} {a}", ["x"])
	check("stops are params without a value", result.stops.map(func(stop): return stop.name), ["b"])
	check("stop offset and length", [result.stops[0].offset, result.stops[0].length], [2, 1])

func test_expand_cursor() -> void:
	var result = Expander.expand("a |CURSOR| b")
	check("text", result.text, "a  b")
	check("cursor", result.cursor, 2)
	check("no cursor - at the end", Expander.expand("abc").cursor, 3)

func test_expand_cursor_order() -> void:
	check("after the text, behind all stops", Expander.expand("{a} {b}").cursor_order, 1.5)
	check("before the first stop", Expander.expand("|CURSOR|{a}").cursor_order, -0.5)
	check("between stops", Expander.expand("{a}|CURSOR|{b}").cursor_order, 0.5)
	check("the first |CURSOR| wins", Expander.expand("a|CURSOR|b|CURSOR|c").cursor, 1)
	check("a filled parameter is not a stop", Expander.expand("{a}|CURSOR|", ["x"]).cursor_order, -0.5)

func test_expand_indentation() -> void:
	check("tabs become the indent unit, following lines get the indent",
		Expander.expand("a\n\tb", [], "\t", "    ").text, "a\n\t    b")

func test_expand_selection() -> void:
	check("selection lines follow the indent of the placeholder",
		Expander.expand("if x:\n\t{selection}", [], "\t\t", "\t", "a\nb").text, "if x:\n\t\t\ta\n\t\t\tb")

func test_dedent() -> void:
	check("shared indentation", Expander.dedent("\t\ta\n\t\t\tb\n\n\t\tc"), "a\n\tb\n\nc")
	check("partly shared", Expander.dedent("  a\n b"), " a\nb")

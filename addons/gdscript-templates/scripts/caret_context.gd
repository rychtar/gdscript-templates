@tool
extends RefCounted

# Reads the text around the caret or the selection in a TextEdit: the keyword to expand,
# the word being completed, the code to wrap. Doesn't change the text.
# Positions are Vector2i(line, column).

const Expander = preload("res://addons/gdscript-templates/scripts/template_expander.gd")

# the word being completed: after a space or an operator, not after "." "$" "%" "@"
static var _completion_word_regex := RegEx.create_from_string("(^|[^.$%@\\w])(\\w+)$")
static var _trailing_word_regex := RegEx.create_from_string("\\w+$")
static var _non_space_regex := RegEx.create_from_string("\\S+")

# the line text before the caret
static func text_before_caret(text_edit: TextEdit) -> String:
	return text_edit.get_line(text_edit.get_caret_line()).substr(0, text_edit.get_caret_column())

# the word right before the caret: {text, start_column}, "" starting at the caret when there is none
static func word_before_caret(text_edit: TextEdit) -> Dictionary:
	var word = _trailing_word_regex.search(text_before_caret(text_edit))
	if word:
		return {"text": word.get_string(), "start_column": word.get_start()}
	return {"text": "", "start_column": text_edit.get_caret_column()}

# the word being completed, "" in strings, comments and after "." "$" "%" "@"
static func completion_word(text_edit: CodeEdit) -> String:
	var line_idx = text_edit.get_caret_line()
	var column = text_edit.get_caret_column()
	if text_edit.is_in_string(line_idx, column) != -1 or text_edit.is_in_comment(line_idx, column) != -1:
		return ""
	var result = _completion_word_regex.search(text_before_caret(text_edit))
	return result.get_string(2) if result else ""

# finds "keyword param1 param2" before the caret, last known keyword wins
# find_keyword(word: String, case_sensitive: bool) -> String returns the template keyword or ""
# returns {keyword, word, start_column, params, raw_params} or {} if there is no keyword
static func find_keyword_before_caret(text_edit: TextEdit, find_keyword: Callable) -> Dictionary:
	var before_caret = text_before_caret(text_edit)
	var words = _non_space_regex.search_all(before_caret)

	# an exact match wins over a case insensitive one: in "onready timer Timer" the keyword is
	# "timer", the type "Timer" is its parameter
	for case_sensitive in [true, false]:
		for i in range(words.size() - 1, -1, -1):
			var keyword = find_keyword.call(words[i].get_string(), case_sensitive)
			if keyword.is_empty() or ends_in_string_or_comment(before_caret.substr(0, words[i].get_start())):
				continue
			# "quoted text" is one param
			var params = Expander.split_args(before_caret.substr(words[i].get_end()))
			return {
				"keyword": keyword,
				"word": words[i].get_string(),
				"start_column": words[i].get_start(),
				"params": params.map(func(param): return param.value),
				# as typed, with quotes
				"raw_params": params.map(func(param): return param.raw),
			}
	return {}

# true when the text ends inside a string or a quoted param, or after a # comment starts
static func ends_in_string_or_comment(text: String) -> bool:
	var quote = ""
	var i = 0
	while i < text.length():
		var c = text[i]
		if quote.is_empty():
			if c == "#":
				return true
			if c == "\"" or c == "'":
				quote = c
		elif c == "\\":
			i += 1
		elif c == quote:
			quote = ""
		i += 1
	return not quote.is_empty()

# what the template browser replaces and starts with: {from, to, selection, filter}
# the selected code, else a known keyword (with params after it) or the word before the caret
static func get_popup_target(text_edit: TextEdit, find_keyword: Callable) -> Dictionary:
	if text_edit.has_selection():
		var selected = get_selected_range(text_edit)
		return {"from": selected.from, "to": selected.to, "selection": selected.text, "filter": ""}

	var caret = Vector2i(text_edit.get_caret_line(), text_edit.get_caret_column())
	var from = caret
	var filter = ""
	var found = find_keyword_before_caret(text_edit, find_keyword)
	if not found.is_empty():
		# params typed after the keyword go into the search, where they can be edited
		filter = " ".join([found.word] + found.raw_params)
		from.y = found.start_column
	else:
		var word = word_before_caret(text_edit)
		filter = word.text
		from.y = word.start_column
	return {"from": from, "to": caret, "selection": "", "filter": filter}

# selection spanning more lines is extended to whole lines (without the first line's indentation),
# returns {from, to, text} with the text dedented
static func get_selected_range(text_edit: TextEdit) -> Dictionary:
	var from = Vector2i(text_edit.get_selection_from_line(), text_edit.get_selection_from_column())
	var to = Vector2i(text_edit.get_selection_to_line(), text_edit.get_selection_to_column())
	if from.x != to.x:
		# selecting whole lines ends at the start of the next line
		if to.y == 0:
			to.x -= 1
		to.y = text_edit.get_line(to.x).length()
		from.y = Expander.leading_whitespace(text_edit.get_line(from.x)).length()
	# whole lines, so the first one keeps its indentation for dedent()
	var text = get_text_between(text_edit, Vector2i(from.x, 0) if from.x != to.x else from, to)
	return {"from": from, "to": to, "text": Expander.dedent(text.strip_edges(false, true))}

static func get_text_between(text_edit: TextEdit, from: Vector2i, to: Vector2i) -> String:
	if from.x == to.x:
		return text_edit.get_line(from.x).substr(from.y, to.y - from.y)
	var lines = [text_edit.get_line(from.x).substr(from.y)]
	for line_idx in range(from.x + 1, to.x):
		lines.append(text_edit.get_line(line_idx))
	lines.append(text_edit.get_line(to.x).substr(0, to.y))
	return "\n".join(lines)

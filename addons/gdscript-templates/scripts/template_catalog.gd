@tool
extends RefCounted

# The templates in the template editor: the default ones and the user's and project's, which can be changed.
# A changed default template is saved as a user template with the same keyword, removing it restores
# the original. User templates are available in all projects or only in this one (project templates),
# a project template overrides a user one. Doesn't know about the UI.

const KIND_DEFAULT = "default"
const KIND_MODIFIED = "modified"
const KIND_CUSTOM = "custom"

const SCOPE_ALL = 0
const SCOPE_PROJECT = 1
const SCOPE_NAMES = ["All projects", "This project only"]

var defaults: Dictionary
var user: Dictionary
var project: Dictionary
var use_defaults: bool

# templates when opened, to detect unsaved changes
var _saved_user: Dictionary
var _saved_project: Dictionary

func _init(p_defaults: Dictionary, p_user: Dictionary, p_project: Dictionary, p_use_defaults: bool) -> void:
	defaults = p_defaults
	user = p_user.duplicate(true)
	project = p_project.duplicate(true)
	use_defaults = p_use_defaults
	_saved_user = p_user.duplicate(true)
	_saved_project = p_project.duplicate(true)

func has_changes() -> bool:
	return user != _saved_user or project != _saved_project

# user or project template (a new one, or a changed default)
func is_own(keyword: String) -> bool:
	return user.has(keyword) or project.has(keyword)

# where an own template is saved
func own_templates(keyword: String) -> Dictionary:
	return project if project.has(keyword) else user

func exists(keyword: String) -> bool:
	return is_own(keyword) or (use_defaults and defaults.has(keyword))

func kind(keyword: String) -> String:
	if not is_own(keyword):
		return KIND_DEFAULT
	return KIND_MODIFIED if use_defaults and defaults.has(keyword) else KIND_CUSTOM

func scope(keyword: String) -> int:
	return SCOPE_PROJECT if project.has(keyword) else SCOPE_ALL

# {body, description, category} of the template as it is now
func entry(keyword: String) -> Dictionary:
	return own_templates(keyword)[keyword] if is_own(keyword) else defaults[keyword]

# a copy for the editor, a template changed before 1.4 (without a category) offers the original category
func editing_entry(keyword: String) -> Dictionary:
	var result := entry(keyword).duplicate()
	if result.category.is_empty() and use_defaults and defaults.has(keyword):
		result.category = defaults[keyword].category
	return result

# all keywords, sorted, only those with the query in the keyword, description or category when it isn't empty
func keywords(query: String = "") -> Array[String]:
	var all := {}
	if use_defaults:
		all.merge(defaults)
	all.merge(user)
	all.merge(project)

	var needle := query.strip_edges().to_lower()
	var result: Array[String] = []
	for keyword in all:
		var template: Dictionary = entry(keyword)
		if needle.is_empty() or keyword.to_lower().contains(needle) or template.description.to_lower().contains(needle) \
				or template.category.to_lower().contains(needle):
			result.append(keyword)
	result.sort()
	return result

# the categories in use, defaults first
func categories() -> PackedStringArray:
	var result := PackedStringArray()
	for templates in [defaults, user, project]:
		for keyword in templates:
			var category: String = templates[keyword].category
			if not category.is_empty() and not result.has(category):
				result.append(category)
	return result

# saves the template, a default template that gets back its original content isn't saved at all
func set_entry(keyword: String, new_entry: Dictionary) -> void:
	var own := own_templates(keyword)
	if use_defaults and defaults.has(keyword) and defaults[keyword] == new_entry:
		own.erase(keyword)
	else:
		own[keyword] = new_entry

# "" when the keyword is fine for the template `current` (a new keyword is checked against the other templates)
func validate_keyword(keyword: String, current: String) -> String:
	if keyword.is_empty():
		return "Keyword can't be empty."
	if keyword.contains(" ") or keyword.contains("\t"):
		return "Keyword can't contain spaces."
	if keyword != current and exists(keyword):
		return "Template \"%s\" already exists." % keyword
	return ""

# the keyword, or keyword_2, keyword_3, ... when it is taken
func unique_keyword(base: String) -> String:
	if not exists(base):
		return base
	var i := 2
	while exists("%s_%d" % [base, i]):
		i += 1
	return "%s_%d" % [base, i]

# a new user template, returns its keyword
func add() -> String:
	var keyword := unique_keyword("new_template")
	user[keyword] = {"body": "|CURSOR|", "description": "", "category": ""}
	return keyword

# a copy next to the template (a copy of a project template stays in the project), returns its keyword
func duplicate(keyword: String) -> String:
	var copy := unique_keyword(keyword + "_copy")
	own_templates(keyword)[copy] = entry(keyword).duplicate()
	return copy

# deletes an own template, or restores a changed default one (it stays in the list then)
func remove(keyword: String) -> void:
	if is_own(keyword):
		own_templates(keyword).erase(keyword)

# only for a valid new keyword, see validate_keyword()
func rename(keyword: String, new_keyword: String) -> void:
	var own := own_templates(keyword)
	var template: Dictionary = own[keyword]
	own.erase(keyword)
	own[new_keyword] = template

# moves an own template between the user and project templates, returns an error and moves nothing
# when the other side already has a template with the keyword
func move_to_scope(keyword: String, new_scope: int) -> String:
	if not is_own(keyword):
		return ""
	var from := own_templates(keyword)
	var to := project if new_scope == SCOPE_PROJECT else user
	if is_same(from, to):
		return ""
	if to.has(keyword):
		return "\"%s\" already exists in \"%s\"." % [keyword, SCOPE_NAMES[new_scope]]
	to[keyword] = from[keyword]
	from.erase(keyword)
	return ""

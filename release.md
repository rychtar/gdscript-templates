# Unreleased

## Added
- Default values for parameters: `{name=value}`. A skipped parameter gets its default,
  so the expanded code is valid right away (`vec 10` → `Vector2(10, 0)`). `{name=}` is an empty default.
- `{selection}`: select code and press `Ctrl+E` / `Ctrl+Space` to wrap it in a template.
  `if`, `ife`, `for`, `fori`, `while`, `region`, `isval`, `isnull`, `dicthas` and `evact` support it.
  The template browser lists templates that wrap the selection first and previews the result.
- Project templates: in the template editor, **Available in → This project only** saves a template
  to `res://.gdscript_templates.json`, which can be committed and shared with the team.
  Project templates override user and default templates with the same keyword.
- `Shift+Tab` goes back to the previous parameter.
- Parameter values with spaces in quotes: `func move "delta: float"`.
- The template browser lists the most used templates first.
- The template editor shows the parameters of the template and their default values.
- Template files changed outside Godot are reloaded automatically.
- New templates: `if`, `tool`, `expgroup`, `expenum`, `expmulti`, `confwarn`, `lambda`, `supercall`,
  `awaitsig`, `evact`, `chscene`, `fread`, `fwrite`, `move2d` (CharacterBody2D platformer movement),
  `statem` (state machine).
- Descriptions for all built-in templates, the browser also searches them.
- The template editor asks to save unsaved changes when it is closed with Cancel, Esc or the close button.

## Changed
- `Ctrl+E` opens the template browser when there is no keyword before the caret (or code is selected),
  instead of doing nothing.
- Built-in templates have default values (`type=float`, `return_type=void`, `count=10`, ...).
- `ife` ends with `else: pass` instead of an empty `else:`.
- Signal handler templates (`collbody`, `collarea`, `timeout`, `pressed`) include the node name
  like Godot does: `_on_area_2d_body_entered`.
- README: `Ctrl+Space` replaces Godot's "request code completion" shortcut and is used by macOS
  to switch keyboard languages, it can be changed in Editor Settings.

## Fixed
- A parameter used more than once was not copied to the other places when the caret left it
  by clicking or with the arrow keys (only `Tab` and `Esc` copied it).
- Keywords inside strings or quoted values are not expanded.

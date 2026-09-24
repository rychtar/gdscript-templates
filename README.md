# GDScript Templates

Code snippets for the Godot 4 script editor. Type a keyword, press `Ctrl+E` and it expands into code.

```
printd health  →  print("health: ", health)
vec 10 20      →  Vector2(10, 20)
fori 5         →  for i in range(5):
```

## Installation

Copy `addons/gdscript-templates` into your project's `addons` folder and enable
**GDScript Templates** in **Project → Project Settings → Plugins**.

Requires Godot 4.2+ (tested with 4.7).

## Usage

| Key | Action |
|-----|--------|
| `Ctrl+E` | Expand the template before the cursor |
| `Ctrl+Space` | Open the template browser |
| `Tab` | Go to the next parameter |
| `Esc` | Stop jumping between parameters |

Words after the keyword fill the template parameters in order. Parameters you
skip are left as placeholders: `vec 10` gives `Vector2(10, y)` with `y` selected,
so you can type its value and press `Tab` to go to the next one. A parameter used
more than once (like `{name}` in `prop`) only needs to be typed once.

The template browser (`Ctrl+Space`) lists all templates with a preview. Type to
filter the list, then press `Enter` or `Tab` to insert the selected template.

There are about 100 built-in templates: functions (`func`, `ready`, `process`),
variables (`export`, `onready`, `prop`), control flow (`ife`, `for`, `fori`, `match`),
signals (`signal`, `sigcon`), nodes (`addch`, `getnode`), tweens, math and more.

## Custom templates

Open **Project → Tools → GDScript Templates...** (or **Edit Templates...** in the
browser). You can add your own templates or change the built-in ones. A changed
built-in template can be reverted to the original.

Your templates are saved to `gdscript_templates.json` in the Godot editor config
folder, so all your projects use the same file. Template syntax:

```json
{
  "myloop": "for {item} in {collection}:\n\tif {item}.{property}:\n\t\t|CURSOR|",
  "log": {
    "body": "print(\"{value}: \", {value})|CURSOR|",
    "description": "Print a value with its name"
  }
}
```

- `{name}` is a parameter
- `|CURSOR|` is where the cursor ends up after expanding
- `\t` is one indent level (converted to spaces if your editor uses spaces)

## Settings

Go to **Editor → Editor Settings → Plugins → GDScript Templates**. Godot only
shows plugin settings when **Advanced Settings** (top right) is turned on.

- **Use Default Templates**: turn off to use only your own templates
- **Show Templates Shortcut**, **Expand Template Shortcut**: keyboard shortcuts

## Screenshots

![Keyword + Preview Window](https://github.com/rychtar/gdscript-templates/blob/main/addons/gdscript-templates/images/keyword.png?raw=true)

![Completed code](https://github.com/rychtar/gdscript-templates/blob/main/addons/gdscript-templates/images/expanded.png?raw=true)

![Default Templates](https://github.com/rychtar/gdscript-templates/blob/main/addons/gdscript-templates/images/templates.png?raw=true)

## License

MIT

# GDScript Templates - Godot Plugin

A powerful code snippet expansion plugin for Godot 4.x that accelerates your workflow with customizable templates and intelligent code completion.

## 🚀 Features

- **Smart Template Expansion** - Type keywords and expand them into full code blocks
- **Descriptive Parameters** - Use meaningful parameter names like `{name}`, `{type}` 
- **Partial Parameter Support** - Fill only some parameters, rest become placeholders (e.g., `vec 10` → `Vector2(10, y)`)
- **Interactive Preview Panel** - See template code before inserting
- **Auto-completion Popup** - Browse available templates with Ctrl+Space
- **Automatic Indentation** - Templates respect your current code indentation
- **Cursor Positioning** - Automatically places cursor at the right spot using `|CURSOR|` marker
- **User Templates** - Override or extend default templates with your own

## ⌨️ Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+Space` | Open template suggestions popup |
| `Ctrl+E` | Expand template on current line |
| `Tab` | Quick expand after selecting from popup |
| `ESC` | Close popup window |
| `↑↓` | Navigate through template list |
| `Enter` | Select template from list |

## 📦 Installation

1. Download or clone this repository
2. Copy the `gdscript-template` folder into your Godot project's `addons` directory
3. Open your project in Godot
4. Go to **Project → Project Settings → Plugins**
5. Find "Code Templates" and set it to **Enable**
6. Restart Godot (recommended)

## 🎯 Usage

### Basic Usage

1. Type a template keyword (e.g., `fori`, `func`, `vec`)
2. Press `Ctrl+E` to expand, or `Ctrl+Space` to browse templates
3. Add parameters after the keyword: `printd health` → `print("health: ", health)`

### Templates Without Parameters

Templates like `ready`, `process` expand immediately when selected from popup.

### Templates With Parameters

Templates like `vec`, `func` wait for parameters:
- `vec 10 20` → `Vector2(10, 20)`
- `vec 10` → `Vector2(10, y)` (partial parameters)
- `func update delta float` → `func update(delta) -> float:`

## ⚙️ Configuration

Access settings via **Project → Tools → Code Templates Settings**

- **Use default templates** - Toggle built-in templates on/off
- **User templates** - Add your own templates in JSON format
- Templates are saved to `user://code_templates.json`

### Template Format
```json
{
  "keyword": "template code with {param1} and {param2}|CURSOR|"
}
```

- Use `{descriptive_name}` for parameters
- Use `|CURSOR|` to mark cursor position after expansion
- Use `\n` for new lines, `\t` for tabs

### Example Custom Template
```json
{
  "myloop": "for {item} in {collection}:\n\tif {item}.{property}:\n\t\t|CURSOR|"
}
```

## 📚 Built-in Templates

The plugin includes 80+ templates for common Godot patterns:
- Functions (`func`, `ready`, `process`, `input`)
- Variables (`export`, `onready`, `const`)
- Control flow (`if`, `for`, `while`, `match`)
- Signals (`signal`, `sigcon`, `sigem`)
- Nodes (`addch`, `getnode`, `inst`)
- Math (`vec2`, `vec3`, `lerp`, `clamp`)
- And many more...

Press `Ctrl+Space` to browse all available templates!

## 🔧 Requirements

- Godot 4.0 or higher

## 📝 License

MIT License - Feel free to use and modify!

## 🐛 Issues & Contributions

Found a bug or have a feature request? Contributions are welcome!


**Happy Coding! 🚀**

## 📸 Screenshots

![Keyword + Preview Window](https://github.com/rychtar/gdscript-templates/blob/main/addons/gdscript-templates/images/keyword.png?raw=true)

![Completed code](https://github.com/rychtar/gdscript-templates/blob/main/addons/gdscript-templates/images/expanded.png?raw=true)

![Default Templates](https://github.com/rychtar/gdscript-templates/blob/main/addons/gdscript-templates/images/templates.png?raw=true)


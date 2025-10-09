# GDScript Templates - Godot Plugin

A powerful code snippet expansion plugin for Godot 4.x that accelerates your workflow with customizable templates and intelligent code completion.

## 🚀 Features

- **Smart Template Expansion** - Type keywords and expand them into full code blocks
- **Descriptive Parameters** - Use meaningful parameter names like `{name}`, `{type}` 
- **Partial Parameter Support** - Fill only some parameters, rest become placeholders (e.g., `vec2 10` → `Vector2(10, y)`)
- **Interactive Preview Panel** - See template code before inserting
- **Auto-completion Popup** - Browse available templates with Ctrl+Space
- **Automatic Indentation** - Templates respect your current code indentation
- **Cursor Positioning** - Automatically places cursor at the right spot using `|CURSOR|` marker
- **User Templates** - Override or extend default templates with your own
- **Platform Aware** - Optimized UI for both macOS Retina and Windows displays
- **Case Insensitive** - Keywords work regardless of capitalization

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
2. Copy the `addons/gdscript-template` folder into your Godot project's `addons/` directory
3. Open your project in Godot
4. Go to **Project → Project Settings → Plugins**
5. Find "Code Templates" and set it to **Enable**
6. Restart Godot (recommended)

## 🎯 Usage

### Basic Usage

1. Type a template keyword (e.g., `prnt`, `func`, `vec2`)
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

## 📸 Screenshots

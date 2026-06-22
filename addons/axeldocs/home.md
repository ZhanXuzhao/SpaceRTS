@title(Welcome to Axeldocs!)
@icon(res://addons/axeldocs/axeldocs.png)

# [tornado radius=5, freq=4]Welcome  to  AxelDocs[/tornado]

# :axeldocs: :axeldocs: :axeldocs: :axeldocs: :axeldocs:

[color=red]No documentation folder has been configured in the project settings, or the configured folder contains no Markdown files.
Please follow the guide below to get started.[/color]

V1.0 - Created by [axelorca](https://axelorca.com)

---

## Getting Started

1. Create a `docs/` folder in your project root
2. Add Markdown (`.md`) files to it. Name one `home.md` to make it open by default
3. Set the path in **Project Settings -> AxelDocs -> Docs Folder**

---

## Tips

- Name a file `home.md` and it will appear at the top of the tree and open automatically
- Use `# Heading` syntax to create page headings and anchor links
- Wrap code in backticks for inline `syntax highlighting`
- Link to Godot class reference with [`Node`](gddoc://Node)

---

# Text Formatting

Regular paragraph text with **bold**, *italic*, ***bold italic***, and ~~strikethrough~~.

Inline `code` is syntax-highlighted. Wrap it in a link to override the auto-generated one: [`Node`](gddoc://Node).

Links work too: [Godot Website](https://godotengine.org) and [cross-page links](readme.md).

---

# Headings

## Heading 2
### Heading 3
#### Heading 4
##### Heading 5
###### Heading 6

---

# Code Blocks

Full code blocks with a background panel, syntax highlighting, and a copy button:

```gdscript
@tool
extends Node

class_name MyClass

const MAX_SPEED: float = 300.0

signal jumped(height: float)

enum State { IDLE, RUN, JUMP }

func _ready() -> void:
	var speed := clamp(MAX_SPEED, 0.0, 500.0)
	print("Ready! speed =", speed)

func move(delta: float) -> Vector2:
	# Move the character
	var dir := Vector2.RIGHT
	return dir * MAX_SPEED * delta

@export var health: int = 100
```

Compact syntax also works: opening and closing fences on the same line as content:

```var x: int = 42
x += 1
print(x)```

---

# GDScript Highlighting

Keywords, types, builtins, annotations, strings, numbers, symbols... all coloured:

```
# Keywords
if condition:
	pass
elif other:
	return
for i in range(10):
	continue
while true:
	break

# Built-in types
var v: Vector2 = Vector2(1.0, 2.0)
var r: Rect2  = Rect2(0, 0, 100, 100)
var c: Color  = Color(1, 0, 0, 1)
var d: Dictionary = {}
var a: Array = [1, 2, 3, 4]

# Numbers
var i: int   = 42
var f: float = 3.14
var h: int   = 0xFF00AA

# Strings
var s: String     = "hello world"
var n: StringName = &"my_signal"

# Annotations
@export var speed: float = 100.0
@onready var label: Label = $Label

# GlobalScope builtins
var len_val := len(a)
var clamped := clamp(f, 0.0, 1.0)
var snapped_val := snapped(f, 0.5)
randomize()

# Function definitions
func _process(delta: float) -> void:
	pass

func helper(x: int, y: int) -> int:
	return x + y
```

---

# Engine & User Classes

Engine classes are auto-detected and linked via ClassDB. Hold **Ctrl** and hover to activate links.

`Node``Sprite2D``CharacterBody2D``RichTextLabel``AnimationPlayer`

User-defined classes (any `class_name` in the project) are also detected and coloured:

`TestClass`

If a class has a dedicated docs page (marked with `@class`), Ctrl+clicking navigates there instead.

---

# Links & Navigation

**Anchor links** jump to a heading on the same page: [jump to Code Blocks](#code-blocks)

**Cross-page links** navigate to another doc: [see Readme](readme.md)

**Godot docs** can be opened with `gddoc://` URLs:
- [`Node`](gddoc://Node) - class reference
- [`add_child()`](gddoc://method:Node:add_child) - method
- [`signal tree_entered`](gddoc://signal:Node:tree_entered) - signal
- [`var process_mode`](gddoc://property:Node:process_mode) - property
- [`const NOTIFICATION_READY`](gddoc://constant:Node:NOTIFICATION_READY) - constant

---

# Lists

Unordered:
- First item
- Second item
  - Nested item
	- Deeply nested
	  - Even deeper

Ordered:
1. First
2. Second
   1. Nested ordered
   2. Another nested
	  1. Triple nested
3. Third

Checkboxes:
- [x] Completed task
- [ ] Pending task
- [x] Another done
  - [ ] Nested pending

---

# Callouts

> A plain blockquote. `code`

> [!NOTE]
> Use this for general notes and extra context.

> [!TIP]
> Helpful tips and shortcuts go here.

> [!IMPORTANT]
> Something the reader must not miss. `code`

> [!WARNING]
> This might cause unexpected behaviour.

> [!CAUTION]
> Destructive or irreversible actions.

---

# Page Annotations

Place these at the top of any `.md` file:

```
@title(My Page)          # sets the tree label
@icon(gdicon://node)      # sets the tree icon (any Godot built-in icon name)
@class(MyClass)          # marks this page as the docs for MyClass. Ctrl+clicking MyClass in any code block navigates here
```

---

# Emojis

Custom emoji images placed in `addons/axeldocs/dock/components/text/custom_emoji/` are referenced with `:name:` syntax.
Examples: 
- `:moondrop:` - :moondrop:
- `:stardrop:` - :stardrop:
- `:note:` - :note:
- `:tip:` - :tip:

## A rich-text content block for Axeldocs.
## Renders either a fenced code block or a Markdown paragraph.
## Overlays styled background panels on [code] spans via [CodeBlockFormatter].
@tool
class_name DocText
extends RichTextLabel

## Emitted whenever [member label_text] is assigned a new value.
signal text_changed

## Reference to the parent [DocView], resolved lazily by walking the scene tree.
var doc_view: DocView:
	get():
		if not doc_view:
			if not is_inside_tree():
				return null
			var p = get_parent()
			while p != null and not p is DocView:
				p = p.get_parent()
			doc_view = p
		return doc_view

## When [code]true[/code], [member label_text] is treated as a fenced code block.
@export var is_code_block: bool:
	set(value):
		is_code_block = value
		refresh()

## Raw Markdown or code source text. Assigning this triggers a full re-render.
@export_multiline var label_text: String:
	set(value):
		label_text = value
		refresh()
		text_changed.emit()


## Whether Ctrl is currently held, enabling clickable hyperlinks in code.
var _links_active: bool = false
## Whether the mouse cursor is over this label.
var _hovered: bool = false
## Incremented on every refresh; stale async coroutines bail out when it changes.
var _update_generation: int = 0
## Guards against queuing more than one deferred formatter call per frame.
var _formatter_pending: bool = false


## Disables per-frame processing by default and performs an initial render.
func _ready() -> void:
	set_process(false)
	refresh()


## Polls Ctrl state while the mouse is hovered and triggers a refresh when it changes.
func _process(_delta: float) -> void:
	var ctrl_held := Input.is_key_pressed(KEY_CTRL)
	if ctrl_held != _links_active:
		_links_active = ctrl_held
		refresh()


## Starts per-frame Ctrl polling when the cursor enters this label.
func _on_mouse_entered() -> void:
	_hovered = true
	set_process(true)


## Stops per-frame polling and clears link highlighting when the cursor leaves.
func _on_mouse_exited() -> void:
	_hovered = false
	set_process(false)
	if _links_active:
		_links_active = false
		refresh()


## Repositions code-block background panels without re-parsing the source text.
## Deferred so that multiple signals arriving in the same frame collapse into one call.
func _run_formatter() -> void:
	if _formatter_pending:
		return
	_formatter_pending = true
	_run_formatter_deferred.call_deferred()


func _run_formatter_deferred() -> void:
	_formatter_pending = false
	if is_code_block:
		CodeBlockFormatter.full(self)
	else:
		CodeBlockFormatter.inline(self)


## Re-parses [member label_text] and reconnects signals.
func refresh():
	_update_text()
	_connect_signals()


## Runs the full Markdown and GDScript formatting pipeline, then waits for layout
## to settle before repositioning code-block background panels.
## Uses a generation counter so that only the most recent call applies its result.
func _update_text():
	_update_generation += 1
	var my_gen := _update_generation
	if is_code_block:
		text = "[code]" + label_text + "[/code]"
		text = GDScriptFormatter.highlight(text, _links_active)
		await Engine.get_main_loop().process_frame
		if _update_generation != my_gen:
			return
		await Engine.get_main_loop().process_frame
		if _update_generation != my_gen:
			return
		CodeBlockFormatter.full(self)
	else:
		text = MarkdownFormatter.highlight(label_text)
		text = GDScriptFormatter.highlight(text, _links_active)
		await Engine.get_main_loop().process_frame
		if _update_generation != my_gen:
			return
		CodeBlockFormatter.inline(self)


## Connects the hyperlink, mouse hover, and content-resize signals.
func _connect_signals():
	if not is_inside_tree() or doc_view == null:
		return
	# Hyperlinks
	if len(meta_clicked.get_connections()) == 0:
		meta_clicked.connect(_go_to_link)
	# Mouse hover for Ctrl+link
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	# Re-run formatter when the content panel resizes (code block backgrounds need repositioning)
	if not doc_view.page_content.item_rect_changed.is_connected(_run_formatter):
		doc_view.page_content.item_rect_changed.connect(_run_formatter)
	# Re-run formatter when this label's own layout settles
	if not item_rect_changed.is_connected(_run_formatter):
		item_rect_changed.connect(_run_formatter)


## Dispatches a clicked meta-link to the appropriate navigation handler.
## Supports [code]anchor:[/code], [code]pageanchor:[/code], [code]classpage:[/code],
## [code]gddoc://[/code], and external URLs.
func _go_to_link(meta: String):
	if typeof(meta) != TYPE_STRING:
		return

	var m := meta as String

	# ---- SAME PAGE ANCHOR ----
	if m.begins_with("anchor:"):
		var anchor := m.substr(7)
		_scroll_to_anchor(anchor)
		return

	# ---- CROSS PAGE ----
	if m.begins_with("pageanchor:"):
		var data := m.substr(11).split("#", false, 1)
		if data.size() == 2:
			var page := data[0]
			var anchor := data[1]

			if doc_view:
				doc_view.open_page_anchor(page, anchor)
		else:
			push_error("axeldocs: malformed pageanchor link (expected 'page#anchor'): '%s'" % m.substr(11))
		return

	# ---- CLASS PAGE ----
	if m.begins_with("classpage:"):
		var page := m.substr(10)
		if doc_view:
			doc_view.navigate_to_page(page)
		return

	# ---- GODOT BUILT-IN DOCS ----
	if m.begins_with("gddoc://"):
		var topic := m.substr(8)
		const PREFIXES := {
			"method:":     "class_method:",
			"signal:":     "class_signal:",
			"property:":   "class_property:",
			"properties:": "class_property:",
			"constant:":   "class_constant:",
			"constants:":  "class_constant:",
		}
		var resolved := false
		for short in PREFIXES:
			if topic.begins_with(short):
				topic = PREFIXES[short] + topic.substr(short.length())
				resolved = true
				break
		if not resolved and ":" not in topic:
			topic = "class_name:" + topic
		EditorInterface.get_script_editor().goto_help(topic)
		return

	# ---- EXTERNAL ----
	var err := OS.shell_open(m)
	if err != OK:
		push_error("axeldocs: failed to open URL '%s' (error %d)" % [m, err])


## Scans all headings on the current page and scrolls to the first one whose
## slug matches [param anchor]. Emits a [code]push_error[/code] if not found.
func _scroll_to_anchor(anchor: String):
	if not doc_view:
		return

	var target_text := MarkdownFormatter.anchor_slugify(anchor)

	for child in doc_view.page_content.get_children():
		if not child is DocText:
			continue

		var doc := child as DocText

		# Only consider headings (they still contain raw markdown)
		var lines := doc.label_text.split("\n")

		for line in lines:
			var stripped := line.strip_edges()

			if stripped.begins_with("#"):
				var title := stripped.lstrip("#").strip_edges()
				var slug := MarkdownFormatter.anchor_slugify(title)

				if slug == target_text:
					await get_tree().process_frame

					var scroll := doc_view.page_content_scroll
					scroll.scroll_vertical = int(child.position.y)
					return

	push_error("axeldocs: anchor '#%s' not found on this page" % anchor)


## Copies the plain-text content of this label to the system clipboard.
func _copy_to_clipboard() -> void:
	DisplayServer.clipboard_set(get_parsed_text())

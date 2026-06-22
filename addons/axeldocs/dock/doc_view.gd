## Main dock controller for Axeldocs.
## Manages the page tree, search bar, and content area.
## Handles tree population, page rendering, and navigation between Markdown pages.
@tool
class_name DocView
extends Control

## Packed scene for image content blocks.
const COMP_IMAGE = preload("res://addons/axeldocs/dock/scenes/image.tscn")
## Packed scene for text and code content blocks.
const COMP_TEXT = preload("res://addons/axeldocs/dock/scenes/text.tscn")
## Packed scene for blockquote content blocks.
const COMP_QUOTE = preload("res://addons/axeldocs/dock/scenes/quote.tscn")
## Packed scene for horizontal dividers.
const COMP_DIVIDER = preload("res://addons/axeldocs/dock/scenes/divider.tscn")
## Packed scene for list item content blocks.
const COMP_BULLET = preload("res://addons/axeldocs/dock/scenes/bullet.tscn")

## Search field for filtering the page tree.
@export var page_search: TextEdit
## Tree widget listing all documentation pages and folders.
@export var page_tree: Tree
## Container that holds the instantiated content components for the current page.
@export var page_content: Control
## Scroll container wrapping [member page_content].
@export var page_content_scroll: ScrollContainer

## Path of the last opened page; used to restore the selection after a refresh.
var last_selected_path: String


## Public entry point. Clears and rebuilds the page tree.
func refresh():
	_populate_tree()


## Clears the tree, wires signals, reads the docs folder setting, and populates the tree.
## Falls back to the built-in home page when the folder is missing or contains no pages.
func _populate_tree() -> void:
	if not is_node_ready():
		await ready
	if not page_tree.item_selected.is_connected(_on_tree_item_selected):
		page_tree.item_selected.connect(_on_tree_item_selected)
	if not page_search.text_changed.is_connected(_on_search_changed):
		page_search.text_changed.connect(_on_search_changed)
	page_tree.clear()
	var root := page_tree.create_item()
	page_tree.hide_root = true
	var folder := ProjectSettings.get_setting("axeldocs/docs_folder", "res://docs") as String
	GDScriptFormatter.class_registry = _build_class_registry()
	if folder.is_empty() or not DirAccess.dir_exists_absolute(folder):
		_load_fallback(root)
		return
	_populate_tree_from_dir(folder, root)
	if not root.get_first_child():
		_load_fallback(root)
		return
	_autoselect_item(root)


## Adds the built-in fallback home page when no docs folder is configured or populated.
## Reads [code]@title[/code] and [code]@icon[/code] annotations from the fallback file.
func _load_fallback(root: TreeItem) -> void:
	const FALLBACK := "res://addons/axeldocs/home.md"
	if not FileAccess.file_exists(FALLBACK):
		return
	var item := page_tree.create_item(root)
	var meta := _get_page_meta(FALLBACK)
	item.set_text(0, meta["title"] if not meta["title"].is_empty() else "Home")
	item.set_metadata(0, FALLBACK)
	if meta["icon"]:
		item.set_icon(0, meta["icon"])
	page_tree.set_selected(item, 0)
	_populate_content(FALLBACK)


## Recursively searches [param item] and its descendants for the page to auto-select.
## Prefers the last visited path; falls back to any file named [code]home.md[/code].
## Returns [code]true[/code] when a match was found and selected.
func _autoselect_item(item: TreeItem) -> bool:
	var child := item.get_first_child()
	while child:
		var meta = child.get_metadata(0)
		if meta is String:
			if not last_selected_path.is_empty() and meta == last_selected_path:
				page_tree.set_selected(child, 0)
				_populate_content(meta)
				return true
			if meta.ends_with("home.md") and last_selected_path.is_empty():
				page_tree.set_selected(child, 0)
				_populate_content(meta)
				return true
		if _autoselect_item(child):
			return true
		child = child.get_next()
	return false


## Recursively populates [param parent] from [param path].
## Ordering: [code]home.md[/code] first, then subfolders, then remaining files alphabetically.
func _populate_tree_from_dir(path: String, parent: TreeItem) -> void:
	var dir := DirAccess.open(path)
	if not dir:
		return

	dir.list_dir_begin()
	var entries: Array[String] = []
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			entries.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	entries.sort()

	# home.md always first
	for e in entries:
		var full_path := path.path_join(e)
		if not DirAccess.dir_exists_absolute(full_path) and e.ends_with(".md") and e.to_lower() == "home.md":
			var item := page_tree.create_item(parent)
			var meta := _get_page_meta(full_path)
			item.set_text(0, meta["title"] if not meta["title"].is_empty() else e.get_basename())
			item.set_metadata(0, full_path)
			if meta["icon"]:
				item.set_icon(0, meta["icon"])

	# Folders next
	for e in entries:
		var full_path := path.path_join(e)
		if DirAccess.dir_exists_absolute(full_path):
			var item := page_tree.create_item(parent)
			item.set_text(0, e)
			item.set_metadata(0, full_path)
			_populate_tree_from_dir(full_path, item)

	randi()
	# Then remaining files alphabetically
	for e in entries:
		var full_path := path.path_join(e)
		if not DirAccess.dir_exists_absolute(full_path) and e.ends_with(".md") and e.to_lower() != "home.md":
			var item := page_tree.create_item(parent)
			var meta := _get_page_meta(full_path)
			item.set_text(0, meta["title"] if not meta["title"].is_empty() else e.get_basename())
			item.set_metadata(0, full_path)
			if meta["icon"]:
				item.set_icon(0, meta["icon"])


## Recursively shows or hides tree items so only those matching [param filter] remain visible.
## Folders are visible when at least one descendant matches.
## Returns [code]true[/code] if [param item] or any of its descendants should be visible.
func _filter_tree(item: TreeItem, filter: String) -> bool:
	var any_visible := false

	var child := item.get_first_child()
	while child:
		var visible := _filter_tree(child, filter)
		child.visible = visible
		if visible:
			any_visible = true
		child = child.get_next()

	# leaf node (a file) — match against its name
	if not item.get_first_child():
		return filter.is_empty() or item.get_text(0).to_lower().contains(filter)

	# folder — visible if any child matched
	return any_visible


## Reads [code]@title[/code], [code]@icon[/code], and [code]@class[/code] annotations
## from the leading lines of [param md_path] before the first non-annotation content.
## Returns a dictionary with keys [code]title[/code], [code]icon[/code], and [code]class[/code].
func _get_page_meta(md_path: String) -> Dictionary:
	# Provide safe defaults
	var result := {"title": "", "icon": null, "class": ""}
	var file := FileAccess.open(md_path, FileAccess.READ)
	if not file:
		return result

	var annotation_regex := RegEx.create_from_string(r"^@(\w+)\((.+)\)$")

	while file.get_position() < file.get_length():
		var line := file.get_line().strip_edges()
		var match := annotation_regex.search(line)
		if match:
			var key := match.get_string(1)
			var value := match.get_string(2)
			if key == "icon":
				if value.begins_with("gdicon://"):
					var icon_name := value.substr(9)
					var theme := EditorInterface.get_editor_theme()
					# Try exact match first
					if theme.has_icon(icon_name, "EditorIcons"):
						result["icon"] = theme.get_icon(icon_name, "EditorIcons")
					else:
						# Case-insensitive fallback: scan all icons
						var lower := icon_name.to_lower()
						for name in theme.get_icon_list("EditorIcons"):
							if name.to_lower() == lower:
								result["icon"] = theme.get_icon(name, "EditorIcons")
								break
				elif ResourceLoader.exists(value):
					var tex := load(value) as Texture2D
					if tex:
						var img := tex.get_image()
						img.resize(20, 20, Image.INTERPOLATE_LANCZOS)
						result["icon"] = ImageTexture.create_from_image(img)
			else:
				result[key] = value
		elif not line.is_empty():
			break

	file.close()
	return result


## Applies the current search field text as a filter on the page tree.
func _on_search_changed() -> void:
	var filter = page_search.text.to_lower().strip_edges()
	var root = page_tree.get_root()
	if root:
		_filter_tree(root, filter)


## Parses [param md_path] line by line and instantiates content components into [member page_content].
## Handles fenced code blocks, blockquotes, images, dividers, lists, and text paragraphs.
func _populate_content(md_path: String) -> void:
	for child in page_content.get_children():
		child.queue_free()

	if md_path.is_empty() or not FileAccess.file_exists(md_path):
		return

	var file := FileAccess.open(md_path, FileAccess.READ)
	if not file:
		return

	var lines := file.get_as_text().split("\n")
	file.close()

	# ---- LIST STATE (indent nesting) ----
	set_meta("indent_stack", [0])

	var i := 0
	# skip @annotation(...) header lines
	var annotation_regex := RegEx.create_from_string(r"^@(\w+)\((.+)\)$")
	while i < lines.size():
		var s := lines[i].strip_edges()
		if annotation_regex.search(s) or s.is_empty():
			i += 1
		else:
			break

	# ---- REGEX (cached once) ----
	var bullet_regex = RegEx.create_from_string(r"^(\s*)([-*]|\d+\.)\s+(.*)")
	var checkbox_regex = RegEx.create_from_string(r"^\[( |x|X)\]\s+(.*)")
	var image_regex = RegEx.create_from_string(r"^!\[([^\]]*)\]\(([^)]+)\)")

	while i < lines.size():
		var line := lines[i]
		var stripped := line.strip_edges()

		# ---------------- CODE BLOCK ----------------
		if stripped.begins_with("```"):
			var after := stripped.substr(3)
			var code_lines: Array[String] = []

			if after.ends_with("```") and after.length() > 3:
				# same-line fence: ```a``` → body is just "a"
				code_lines.append(after.substr(0, after.length() - 3))
				i += 1
			else:
				# if content follows the opening fence (not just a language tag), keep it
				if " " in after:
					code_lines.append(after)
				i += 1
				while i < lines.size():
					var sl := lines[i].strip_edges()
					if sl == "```":
						i += 1
						break
					elif sl.ends_with("```"):
						# closing fence on same line as content: ok```
						var content := sl.substr(0, sl.length() - 3).rstrip(" \t")
						if content != "":
							code_lines.append(content)
						i += 1
						break
					code_lines.append(lines[i])
					i += 1
				# i is now either past the closing fence or at lines.size() — safe either way

			var comp: DocText = COMP_TEXT.instantiate()
			page_content.add_child(comp)
			comp.is_code_block = true
			comp.label_text    = "\n".join(code_lines)
			continue

		# ---------------- QUOTE ----------------
		if stripped.begins_with(">"):
			var quote_lines: Array[String] = []

			while i < lines.size() and lines[i].begins_with(">"):
				quote_lines.append(lines[i].substr(1).strip_edges())
				i += 1

			var comp: DocQuote = COMP_QUOTE.instantiate()
			page_content.add_child(comp)

			var first := quote_lines[0] if quote_lines.size() > 0 else ""
			var body_start := 0

			if first.begins_with("[!") and first.ends_with("]"):
				var type_str := first.substr(2, first.length() - 3).to_upper()
				if type_str in DocQuote.TYPE.keys():
					comp.quote_type = DocQuote.TYPE[type_str]
				else:
					comp.quote_type = DocQuote.TYPE.BASE
				body_start = 1
			else:
				comp.quote_type = DocQuote.TYPE.BASE

			comp.body_text.label_text = "\n".join(quote_lines.slice(body_start))
			continue

		# ---------------- IMAGE ----------------
		var img_match := image_regex.search(stripped)
		if img_match:
			var alt_text := img_match.get_string(1)
			var img_path := img_match.get_string(2)

			if not img_path.begins_with("res://") and not img_path.begins_with("user://"):
				img_path = md_path.get_base_dir().path_join(img_path)

			var comp: DocImage = COMP_IMAGE.instantiate()
			page_content.add_child(comp)

			var tex := load(img_path) as Texture2D
			if tex:
				comp.image = tex

			if not alt_text.is_empty():
				comp.tooltip_text = alt_text

			i += 1
			continue

		# ---------------- DIVIDER ----------------
		if stripped in ["---", "***", "___"]:
			var comp = COMP_DIVIDER.instantiate()
			page_content.add_child(comp)
			i += 1
			continue

		# ---------------- BULLET / LIST ----------------
		var bullet_match := bullet_regex.search(line)
		if bullet_match:
			var raw_indent := bullet_match.get_string(1)
			var indent := 0
			for ch in raw_indent:
				indent += 4 if ch == "\t" else 1
			var marker := bullet_match.get_string(2)
			var content := bullet_match.get_string(3)

			var comp: DocBullet = COMP_BULLET.instantiate()
			page_content.add_child(comp)

			var indent_stack: Array = get_meta("indent_stack")
			if indent > indent_stack.back():
				indent_stack.append(indent)
			elif indent < indent_stack.back():
				while indent_stack.size() > 1 and indent_stack.back() > indent:
					indent_stack.pop_back()
			comp.level = indent_stack.size() - 1

			# NUMBERED LIST
			if marker.ends_with("."):
				comp.type = DocBullet.TYPE.NUMBER
				comp.bullet_number = marker.rstrip(".").to_int()
				comp.get_node("Text/Content").label_text = content

			# BULLET OR CHECKBOX
			else:
				var cb := checkbox_regex.search(content)

				if cb:
					comp.type = DocBullet.TYPE.CHECKBOX
					comp.set_checkbox(cb.get_string(1).to_lower() == "x")
					comp.get_node("Text/Content").label_text = cb.get_string(2)
				else:
					comp.type = DocBullet.TYPE.BULLET
					comp.get_node("Text/Content").label_text = content

			i += 1
			continue

		# ---------------- EMPTY LINE ----------------
		if stripped.is_empty():
			i += 1
			continue

		# ---------------- TEXT BLOCK ----------------
		var text_lines: Array[String] = []

		while i < lines.size():
			var l := lines[i]
			var s := l.strip_edges()

			if s.begins_with("```") \
			or s.begins_with(">") \
			or s in ["---", "***", "___"] \
			or image_regex.search(s) \
			or bullet_regex.search(l) \
			or s.is_empty():
				break

			text_lines.append(l)
			i += 1

		if text_lines.size() > 0:
			var comp: DocText = COMP_TEXT.instantiate()
			page_content.add_child(comp)
			comp.is_code_block = false
			comp.label_text = "\n".join(text_lines)


## Builds a dictionary mapping class names to their documentation URLs.
## User-defined classes point to [code]gddoc://ClassName[/code].
## Classes with a matching [code]@class[/code] docs page point to [code]classpage:path[/code].
func _build_class_registry() -> Dictionary:
	var registry: Dictionary = {}
	# Register all user-defined GDScript class_name declarations → open docs via goto_help
	for info in ProjectSettings.get_global_class_list():
		var cn := info.get("class", "") as String
		if not cn.is_empty():
			registry[cn] = "gddoc://" + cn
	# Overlay with any classes that have a docs page (non-empty path wins)
	var folder := ProjectSettings.get_setting("axeldocs/docs_folder", "res://docs") as String
	if not folder.is_empty() and DirAccess.dir_exists_absolute(folder):
		_collect_classes(folder, registry)
	return registry


## Recursively scans [param path] for Markdown files whose [code]@class[/code] annotation
## names a GDScript class, and registers them in [param registry].
func _collect_classes(path: String, registry: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if not dir:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full_path := path.path_join(entry)
			if DirAccess.dir_exists_absolute(full_path):
				_collect_classes(full_path, registry)
			elif entry.ends_with(".md"):
				var meta := _get_page_meta(full_path)
				var class_name_val := meta.get("class", "") as String
				if not class_name_val.is_empty():
					registry[class_name_val] = "classpage:" + full_path
		entry = dir.get_next()
	dir.list_dir_end()


## Selects [param page] in the tree and loads its content.
## Accepts an absolute [code]res://[/code] path or a path suffix for relative links.
## Emits a [code]push_error[/code] if the page is not found in the tree.
func navigate_to_page(page: String) -> void:
	var root := page_tree.get_root()
	if not root:
		return
	var item := _find_tree_item_by_path(root, page)
	if item:
		page_tree.set_selected(item, 0)
		page_tree.queue_redraw()
		last_selected_path = page
		_populate_content(page)
		await get_tree().process_frame
		page_content_scroll.scroll_vertical = 0
	else:
		push_error("axeldocs: page not found: '%s'" % page)


## Navigates to [param page] and scrolls to [param anchor] within it.
## Emits a [code]push_error[/code] if the page is not found in the tree.
func open_page_anchor(page: String, anchor: String) -> void:
	var root := page_tree.get_root()
	if not root:
		return
	var item := _find_tree_item_by_path(root, page)
	if item:
		page_tree.set_selected(item, 0)
		last_selected_path = page
		_populate_content(page)
		if not anchor.is_empty():
			await get_tree().process_frame
			for child in page_content.get_children():
				if child is DocText:
					await (child as DocText)._scroll_to_anchor(anchor)
					break
	else:
		push_error("axeldocs: page not found: '%s'" % page)


## Searches the subtree rooted at [param item] for a tree item whose metadata equals
## [param path] or ends with [code]/path[/code] (for relative link resolution).
## Returns [code]null[/code] when no match is found.
func _find_tree_item_by_path(item: TreeItem, path: String) -> TreeItem:
	var child := item.get_first_child()
	while child:
		var meta = child.get_metadata(0)
		if meta is String and (meta == path or meta.ends_with("/" + path)):
			return child
		var found := _find_tree_item_by_path(child, path)
		if found:
			return found
		child = child.get_next()
	return null


## Loads the page whose path is stored in the selected tree item's metadata.
func _on_tree_item_selected() -> void:
	var item := page_tree.get_selected()
	if not item:
		return

	var meta = item.get_metadata(0)
	if meta is String:
		last_selected_path = meta
		if (meta as String).ends_with(".md"):
			_populate_content(meta)

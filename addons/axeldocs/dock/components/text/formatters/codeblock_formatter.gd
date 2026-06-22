## Static utility that overlays [Panel] nodes on code spans inside a [RichTextLabel].
## [method full] covers the entire label for block code.
## [method inline] places one panel per [code][code][/code] span, splitting across lines as needed.
@tool
class_name CodeBlockFormatter


## Packed scene used as the background panel overlay for code spans.
const CODE_BLOCK: PackedScene = preload("res://addons/axeldocs/dock/components/text/code_block.tscn")
## Extra padding added around each code span background rect.
const code_block_offset: Vector2 = Vector2(6, 6)

## Compiled regex for extracting [code][code]...[/code][/code] spans from BBCode text.
static var _code_regex := RegEx.new()
## Compiled regex for stripping BBCode tags when measuring plain-text positions.
static var _tag_regex := RegEx.new()


## Compiles [member _code_regex] and [member _tag_regex] once at class load time.
static func _static_init() -> void:
	_code_regex.compile(r"\[code(?:=[^\]]+)?\]([\s\S]*?)\[/code\]")
	_tag_regex.compile(r"\[[^\]]*\]")


## Positions a single full-size background panel over [param label].
## Reuses an existing child panel if one is present; otherwise instantiates a new one.
static func full(label: DocText) -> void:
	var existing: Array[Node] = []
	for c in label.get_children():
		if c.get_scene_file_path() == CODE_BLOCK.resource_path:
			existing.append(c)

	var rect: Node
	if existing.size() > 0:
		rect = existing[0]
		for idx in range(1, existing.size()):
			existing[idx].queue_free()
	else:
		rect = CODE_BLOCK.instantiate()
		label.add_child(rect)
	
	var copy_button: Button = rect.get_child(0).get_child(0)
	copy_button.visible = true
	if len(copy_button.pressed.get_connections()) == 0:
		copy_button.pressed.connect(label._copy_to_clipboard)
	
	rect.z_index = -1
	rect.anchor_left   = 0.0
	rect.anchor_top    = 0.0
	rect.anchor_right  = 0.0
	rect.anchor_bottom = 0.0
	rect.set_deferred("position", -0.5 * code_block_offset)
	rect.set_deferred("size", label.size + code_block_offset)


## Positions per-line background panels over every inline [code][code][/code] span in [param label].
## Reuses, creates, or frees child panels to match the number of spans found.
static func inline(label: RichTextLabel):
	var matches := _code_regex.search_all(label.text)
	var parsed_text := label.get_parsed_text()

	# Collect all spans first
	var spans: Array[Vector3i] = []  # x=start, y=end, z=line (unused, we split below)
	var rects_needed: Array[Dictionary] = []  # {start_i, end_i, line}

	for match in matches:
		var raw_inner := match.get_string(1)
		raw_inner = raw_inner.replace("[lb]", char(1))
		var code := _tag_regex.sub(raw_inner, "", true)
		code = code.replace(char(1), "[")
		if code.is_empty():
			continue
		var raw_before := label.text.substr(0, match.get_start())
		var parsed_before := _tag_regex.sub(raw_before, "", true)
		var search_from := parsed_before.length()
		var start := parsed_text.find(code, search_from)
		if start == -1:
			continue
		var end := start + code.length()
		var line_start := start
		var current_line := label.get_character_line(start)
		for i in range(start, end):
			var line := label.get_character_line(i)
			if line == -1:
				continue
			if line != current_line:
				rects_needed.append({ "start_i": line_start, "end_i": i, "line": current_line })
				line_start = i
				current_line = line
		rects_needed.append({ "start_i": line_start, "end_i": end, "line": current_line })

	# Gather existing rect instances
	var existing: Array[Node] = []
	for c in label.get_children():
		existing.append(c)

	# Reuse, create, or free as needed
	for idx in range(rects_needed.size()):
		var data := rects_needed[idx]
		var rect: Node
		if idx < existing.size():
			rect = existing[idx]
		else:
			rect = CODE_BLOCK.instantiate()
			label.add_child(rect)
			
		rect.get_child(0).get_child(0).visible = false
		
		_apply_rect(rect, label, data["start_i"], data["end_i"], data["line"])

	# Free leftovers
	for idx in range(rects_needed.size(), existing.size()):
		existing[idx].queue_free()


## Measures glyph positions on [param line] using [TextServer] and sizes [param rect]
## to cover characters [param start_i] through [param end_i].
static func _apply_rect(rect: Node, label: RichTextLabel, start_i: int, end_i: int, line: int):
	if line < 0:
		return

	var text       := label.get_parsed_text()
	var raw        := label.text

	# Content margins live on the "normal" StyleBox, not as theme constants.
	# StyleBoxEmpty defaults to -1 (no override) so clamp to 0.
	var _normal_style := label.get_theme_stylebox("normal", "RichTextLabel")
	var margin_left  := int(maxf(0.0, _normal_style.get_margin(SIDE_LEFT)))   if _normal_style else 0
	var margin_top   := int(maxf(0.0, _normal_style.get_margin(SIDE_TOP)))    if _normal_style else 0
	var margin_right := int(maxf(0.0, _normal_style.get_margin(SIDE_RIGHT)))  if _normal_style else 0

	var normal_font := label.get_theme_font("normal_font")
	var bold_font   := label.get_theme_font("bold_font")
	var italic_font := label.get_theme_font("italics_font")
	var bi_font     := label.get_theme_font("bold_italics_font")
	var mono_font   := label.get_theme_font("mono_font")
	var normal_size := label.get_theme_font_size("normal_font_size")
	var bold_size   := label.get_theme_font_size("bold_font_size")
	var italic_size := label.get_theme_font_size("italics_font_size")
	var bi_size     := label.get_theme_font_size("bold_italics_font_size")
	var mono_size   := label.get_theme_font_size("mono_font_size")

	# Build font runs
	var runs: Array[Dictionary] = []
	var parsed_i        := 0
	var raw_i           := 0
	var bold            := false
	var italic          := false
	var mono            := false
	var font_size_stack : Array[int] = []
	var run_start       := 0
	var run_font : Font = normal_font
	var run_size : int  = normal_size

	while raw_i < raw.length():
		if raw.substr(raw_i, 4) == "[lb]":
			parsed_i += 1
			raw_i += 4
			continue
		if raw[raw_i] == "[":
			var close := raw.find("]", raw_i)
			if close == -1:
				break
			var tag := raw.substr(raw_i + 1, close - raw_i - 1).strip_edges().to_lower()
			if parsed_i > run_start:
				runs.append({ "font": run_font, "size": run_size, "from": run_start, "to": parsed_i })
			match tag:
				"b":          bold   = true
				"/b":         bold   = false
				"i":          italic = true
				"/i":         italic = false
				"code":       mono   = true
				"/code":      mono   = false
				"/font_size":
					if font_size_stack.size() > 0:
						font_size_stack.pop_back()
				_:
					if tag.begins_with("code="):
						mono = true
					elif tag.begins_with("font_size="):
						var new_size := tag.substr(10).to_int()
						if new_size > 0:
							font_size_stack.append(new_size)
			var current_size := font_size_stack.back() if font_size_stack.size() > 0 else 0
			if mono:
				run_font = mono_font
				run_size = current_size if current_size > 0 else mono_size
			elif bold and italic:
				run_font = bi_font
				run_size = current_size if current_size > 0 else bi_size
			elif bold:
				run_font = bold_font
				run_size = current_size if current_size > 0 else bold_size
			elif italic:
				run_font = italic_font
				run_size = current_size if current_size > 0 else italic_size
			else:
				run_font = normal_font
				run_size = current_size if current_size > 0 else normal_size
			run_start = parsed_i
			raw_i = close + 1
		else:
			parsed_i += 1
			raw_i    += 1
	if parsed_i > run_start:
		runs.append({ "font": run_font, "size": run_size, "from": run_start, "to": parsed_i })

	# Build a TextParagraph mirroring the label's content
	var paragraph := TextParagraph.new()
	paragraph.width = label.size.x - margin_left - margin_right
	for run in runs:
		paragraph.add_string(text.substr(run["from"], run["to"] - run["from"]), run["font"], run["size"])

	# Force shaping and guard against line mismatch
	var line_count := paragraph.get_line_count()
	if line >= line_count:
		return
	var line_rid := paragraph.get_line_rid(line)
	if not line_rid.is_valid():
		return

	# Use TextServer to walk glyphs on the target line
	var ts       := TextServerManager.get_primary_interface()
	var glyphs   := ts.shaped_text_get_glyphs(line_rid)

	# Accumulate y by summing line heights before this line
	var y := float(margin_top)
	for i in line:
		var rid := paragraph.get_line_rid(i)
		y += ts.shaped_text_get_ascent(rid) + ts.shaped_text_get_descent(rid)

	var line_ascent  := ts.shaped_text_get_ascent(line_rid)
	var line_descent := ts.shaped_text_get_descent(line_rid)
	var line_height  := line_ascent + line_descent

	# Walk glyphs to find x and width for [start_i, end_i)
	var x       := float(margin_left)
	var span_x  := -1.0
	var span_xe := 0.0
	var cur_x   := float(margin_left)

	for glyph in glyphs:
		var g_start : int   = glyph.get("start", -1)
		var g_end   : int   = glyph.get("end",   -1)
		var advance : float = glyph.get("advance", 0.0)

		if g_end <= start_i:
			cur_x += advance
		elif g_start >= end_i:
			break
		else:
			if span_x < 0.0:
				span_x = cur_x
			span_xe = cur_x + advance
			cur_x += advance

	if span_x < 0.0:
		span_x  = cur_x
		span_xe = cur_x

	var w := span_xe - span_x

	# Vertical centering
	var code_size := mono_size
	for run in runs:
		if run["from"] <= start_i and start_i < run["to"]:
			code_size = run["size"]
			break

	var ascent       := mono_font.get_ascent(code_size)
	var descent      := mono_font.get_descent(code_size)
	var glyph_height := ascent + descent
	var y_centered   := y + (line_height - glyph_height) / 2.0
	var rect_height  := glyph_height + code_block_offset.y * 0.5

	rect.z_index = -1
	rect.anchor_left   = 0.0
	rect.anchor_top    = 0.0
	rect.anchor_right  = 0.0
	rect.anchor_bottom = 0.0
	rect.set_deferred("position", Vector2(span_x - code_block_offset.x * 0.5, y_centered - rect_height / 2.0 + glyph_height / 2.0))
	rect.set_deferred("size", Vector2(w + code_block_offset.x, rect_height))

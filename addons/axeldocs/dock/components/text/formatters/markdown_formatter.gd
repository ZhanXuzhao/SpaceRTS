## Static Markdown-to-BBCode converter used by [DocText].
## Handles inline formatting, headers, code spans, images, links, and custom emoji.
## All transformations produce a new string; the source is never mutated.
class_name MarkdownFormatter


## Number of pixels added to the current font size when sizing inline emoji images.
const EMOJI_SIZE_OFFSET: int = 4


## Converts a Markdown string to BBCode ready for use in a [RichTextLabel].
## Protects code spans and link URLs from formatting passes, then restores them
## after all substitutions are complete.
static func highlight(source: String) -> String:
	var result := source

	# Protect linked inline code: [`code`](url) — must run before everything else
	var linked_codes: Array = []
	var linked_code_re := RegEx.new()
	linked_code_re.compile(r"\[`([^`]*)`\]\(([^)]+)\)")
	var lc_out := ""
	var lc_last := 0
	for m in linked_code_re.search_all(result):
		lc_out += result.substr(lc_last, m.get_start() - lc_last)
		linked_codes.append({"content": m.get_string(1), "url": m.get_string(2)})
		lc_out += "%%LCODE%d%%" % (linked_codes.size() - 1)
		lc_last = m.get_end()
	lc_out += result.substr(lc_last)
	result = lc_out

	# Preserve code blocks so emojis don't work inside them
	var code_blocks := []
	var code_re := RegEx.new()
	code_re.compile(r"\[code\].*?\[/code\]")

	var protected := ""
	var last := 0
	var i := 0

	for m in code_re.search_all(result):
		protected += result.substr(last, m.get_start() - last)

		var token := "%%CB%d%%" % i
		code_blocks.append(m.get_string())
		protected += token

		last = m.get_end()
		i += 1

	protected += result.substr(last)
	result = protected

	# Protect link URLs from bold/italic processing
	var link_urls: Array = []
	var link_url_re := RegEx.new()
	link_url_re.compile(r"(!?\[[^\]]*\])\(([^)]+)\)")
	var link_out := ""
	var link_last := 0
	for lm in link_url_re.search_all(result):
		link_out += result.substr(link_last, lm.get_start() - link_last)
		var ltoken := "%%LURL%d%%" % link_urls.size()
		link_urls.append(lm.get_string(2))
		link_out += lm.get_string(1) + "(" + ltoken + ")"
		link_last = lm.get_end()
	link_out += result.substr(link_last)
	result = link_out

	# Bold-italic
	result = _re_replace(result, r"\*\*\*(.*?)\*\*\*", "[b][i]$1[/i][/b]")
	result = _re_replace(result, r"___(.*?)___",        "[b][i]$1[/i][/b]")

	# Bold
	result = _re_replace(result, r"\*\*(.*?)\*\*", "[b]$1[/b]")
	result = _re_replace(result, r"__(.*?)__",     "[b]$1[/b]")

	# Italic
	result = _re_replace(result, r"\*(.*?)\*", "[i]$1[/i]")
	result = _re_replace(result, r"_(.*?)_",   "[i]$1[/i]")

	# Strikethrough
	result = _re_replace(result, r"~~(.*?)~~", "[s]$1[/s]")

	# Inline code — [^`]* stops at any backtick so adjacent spans split correctly
	result = _re_replace(result, r"`([^`]*)`", " [code]$1[/code] ")
	# Remove the added space when the tag falls at a line boundary
	result = _re_replace(result, r"(?m)^ \[code\]", "[code]")
	result = _re_replace(result, r"(?m)\[/code\] $", "[/code]")

	# Re-protect inline [code]...[/code] spans created from backticks above
	# so that emoji substitution cannot fire inside them
	var protected2 := ""
	var last2 := 0
	for m in code_re.search_all(result):
		protected2 += result.substr(last2, m.get_start() - last2)
		var token := "%%CB%d%%" % code_blocks.size()
		code_blocks.append(m.get_string())
		protected2 += token
		last2 = m.get_end()
	protected2 += result.substr(last2)
	result = protected2

	# Headers FIRST so emojis know the current font size
	result = _re_replace(result, r"(?m)^#{6}\s+(.*?)$", "[font_size=10][b]$1[/b][/font_size]")
	result = _re_replace(result, r"(?m)^#{5}\s+(.*?)$", "[font_size=14][b]$1[/b][/font_size]")
	result = _re_replace(result, r"(?m)^#{4}\s+(.*?)$", "[font_size=18][b]$1[/b][/font_size]")
	result = _re_replace(result, r"(?m)^#{3}\s+(.*?)$", "[font_size=22][b]$1[/b][/font_size]")
	result = _re_replace(result, r"(?m)^#{2}\s+(.*?)$", "[font_size=26][b]$1[/b][/font_size]")
	result = _re_replace(result, r"(?m)^#{1}\s+(.*?)$", "[font_size=30][b]$1[/b][/font_size]")

	# Emojis with dynamic font size
	var emoji_re := RegEx.new()
	emoji_re.compile(r":([a-zA-Z0-9_\-]+):")

	var out := ""
	last = 0

	for m in emoji_re.search_all(result):
		out += result.substr(last, m.get_start() - last)

		var before := result.substr(0, m.get_start())

		# Default RichTextLabel font size
		var font_size := 14 + EMOJI_SIZE_OFFSET

		# Find latest active font_size tag
		var size_re := RegEx.new()
		size_re.compile(r"\[font_size=(\d+)\]")

		for s in size_re.search_all(before):
			font_size = int(s.get_string(1)) + EMOJI_SIZE_OFFSET

		var emoji_name := m.get_string(1)

		# Find matching file with any extension
		var dir := DirAccess.open("res://addons/axeldocs/dock/components/text/custom_emoji")

		if dir:
			dir.list_dir_begin()

			var file := dir.get_next()
			var found_path := ""

			while file != "":
				if !dir.current_is_dir():
					if file.get_basename() == emoji_name:
						found_path = "res://addons/axeldocs/dock/components/text/custom_emoji/%s" % file
						break

				file = dir.get_next()

			dir.list_dir_end()

			if found_path != "":
				out += "[img=%dem]%s[/img]" % [
					font_size,
					found_path
				]
			else:
				out += m.get_string()

		else:
			out += m.get_string()

		last = m.get_end()

	out += result.substr(last)
	result = out

	# Restore link URLs
	for j in link_urls.size():
		result = result.replace("%%LURL%d%%" % j, link_urls[j])

	# Internal anchor link
	result = _re_replace(
		result,
		r"\[([^\]]+)\]\(#([^)]+)\)",
		"[url=anchor:$2]$1[/url]"
	)

	# Cross-page anchor link
	result = _re_replace(
		result,
		r"\[([^\]]+)\]\(([^)#]+\.md)#([^)]+)\)",
		"[url=pageanchor:$2#$3]$1[/url]"
	)

	# Cross-page link (no anchor)
	result = _re_replace(
		result,
		r"\[([^\]]+)\]\(([^)#]+\.md)\)",
		"[url=classpage:$2]$1[/url]"
	)

	# External link
	result = _re_replace(
		result,
		r"\[([^\]]+)\]\(([^)]+)\)",
		"[url=$2]$1[/url]"
	)
	
	# Restore code blocks
	for j in code_blocks.size():
		result = result.replace(
			"%%CB%d%%" % j,
			code_blocks[j]
		)

	# Restore linked inline code as special tags for GDScriptFormatter
	for j in linked_codes.size():
		var lc: Dictionary = linked_codes[j]
		result = result.replace(
			"%%LCODE%d%%" % j,
			" [code=EXPURL:%s]%s[/code] " % [lc["url"], lc["content"]]
		)

	result = result.replace(char(1), "[lb]")
	return result


## Converts a heading string into a lowercase, hyphen-separated URL anchor slug.
## Strips leading and trailing hyphens and collapses consecutive hyphens.
static func anchor_slugify(text: String) -> String:
	var s := text.to_lower()

	# replace everything not alphanumeric with hyphens
	var re := RegEx.new()
	re.compile("[^a-z0-9]+")

	s = re.sub(s, "-", true)

	# cleanup repeated / edge hyphens
	s = s.trim_prefix("-")
	s = s.trim_suffix("-")

	while s.find("--") != -1:
		s = s.replace("--", "-")

	return s


## Applies [param pattern] to [param text] and replaces each match with [param replacement].
## Supports [code]$1[/code] through [code]$N[/code] capture group references.
static func _re_replace(text: String, pattern: String, replacement: String) -> String:
	var re := RegEx.new()
	re.compile(pattern)

	var out  := ""
	var last := 0

	for m in re.search_all(text):
		out += text.substr(last, m.get_start() - last)

		var rep := replacement

		for g in range(1, m.get_group_count() + 1):
			rep = rep.replace("$%d" % g, m.get_string(g))

		out += rep
		last = m.get_end()

	out += text.substr(last)

	return out

## Static GDScript syntax highlighter used by [DocText].
## Wraps all [code][code][/code] spans in BBCode color tags and optionally emits
## [code][url][/code] links for known class names when [param with_links] is true.
class_name GDScriptFormatter

## Color for language keywords.
const COLOR_KEYWORD      := Color(0.912, 0.298, 0.338, 1.0)
## Color for built-in functions.
const COLOR_BUILTIN      := Color(0.912, 0.53,  0.853, 1.0)
## Color for string literals.
const COLOR_STRING       := Color(0.963, 0.816, 0.542, 1.0)
## Color for comments.
const COLOR_COMMENT      := Color(0.593, 0.592, 0.588, 1.0)
## Color for numeric literals.
const COLOR_NUMBER       := Color(0.802, 1.0,   0.743, 1.0)
## Color for function call identifiers.
const COLOR_FUNCTION     := Color(0.241, 0.59, 1.0, 1.0)
## Color for function definition names.
const COLOR_FUNCTION_DEF := Color(0.0, 0.842, 0.899, 1.0)
## Color for built-in type names.
const COLOR_BUILTIN_TYPE := Color(0.0,   0.908, 0.623, 1.0)
## Color for user-defined and engine class names.
const COLOR_CUSTOM_TYPE  := Color(0.425, 0.952, 0.803, 1.0)
## Color for annotations such as [code]@export[/code].
const COLOR_ANNOTATION   := Color(0.952, 0.559, 0.326, 1.0)
## Color for punctuation and operator symbols.
const COLOR_SYMBOL       := Color(0.657, 0.747, 0.911, 1.0)
## Color for unclassified identifiers.
const COLOR_DEFAULT      := Color(0.901, 0.901, 0.901, 1.0)

## Maps class names to their documentation URLs ([code]gddoc://[/code] or [code]classpage:[/code]).
## Populated by [method DocView._build_class_registry] at startup.
static var class_registry: Dictionary = {}

## GDScript language keywords that receive [constant COLOR_KEYWORD] highlighting.
const KEYWORDS := [
	"if", "elif", "else", "for", "while", "match", "when",
	"break", "continue", "pass", "return", "class", "class_name",
	"extends", "is", "in", "not", "and", "or", "as", "self",
	"signal", "func", "static", "const", "var", "enum", "await",
	"yield", "assert", "breakpoint", "preload", "load", "super",
	"true", "false", "null", "PI", "TAU", "INF", "NAN",
]

## Built-in global functions that receive [constant COLOR_BUILTIN] highlighting.
const BUILTINS := [
	"print", "printerr", "print_rich", "print_verbose", "push_error", "push_warning",
	"len", "range", "typeof", "str", "assert", "weakref", "load", "preload",
	"abs", "ceil", "floor", "round", "sqrt", "pow", "min", "max", "clamp",
	"lerp", "lerp_angle", "inverse_lerp", "smoothstep", "move_toward", "snapped",
	"sign", "ease", "pingpong", "wrap", "wrapi", "wrapf",
	"sin", "cos", "tan", "asin", "acos", "atan", "atan2",
	"deg_to_rad", "rad_to_deg", "log", "exp",
	"is_nan", "is_inf", "is_zero_approx", "is_equal_approx",
	"randomize", "randi", "randf", "randi_range", "randf_range", "seed",
	"var_to_str", "str_to_var", "var_to_bytes", "bytes_to_var", "type_convert",
	"inst_to_dict", "dict_to_inst",
]

## Built-in primitive and Variant types that receive [constant COLOR_BUILTIN_TYPE] highlighting.
const TYPES := [
	"void", "bool", "int", "float", "String", "StringName",
	"Array", "Dictionary", "Callable", "Signal", "NodePath", "RID",
	"Vector2", "Vector2i", "Vector3", "Vector3i", "Vector4", "Vector4i",
	"Rect2", "Rect2i", "Transform2D", "Transform3D", "Basis",
	"Quaternion", "Plane", "AABB", "Color",
	"PackedByteArray", "PackedInt32Array", "PackedInt64Array",
	"PackedFloat32Array", "PackedFloat64Array", "PackedStringArray",
	"PackedVector2Array", "PackedVector3Array", "PackedVector4Array",
	"PackedColorArray",
]

## Scans all [code][code][/code] blocks in [param source] and applies GDScript highlighting.
## Passes [param with_links] down to [method _parse] to control hyperlink generation.
static func highlight(source: String, with_links: bool = false) -> String:
	var block_regex := RegEx.new()
	block_regex.compile(r"\[code(?:=([^\]]+))?\]([\s\S]*?)\[/code\]")  # group1=attr, group2=content
	var tag_regex := RegEx.new()
	tag_regex.compile(r"\[[^\]]*\]")
	var result := source
	for match in block_regex.search_all(source):
		var attr  := match.get_string(1)
		var inner := match.get_string(2)
		# Shield GDScript [ ] from tag_regex (which would strip them as "BBCode tags")
		var code := inner.replace("[", char(1)).replace("]", char(2))
		code = tag_regex.sub(code, "", true)
		code = code.replace(char(1), "[").replace(char(2), "]")
		var highlighted := _parse(code, with_links)
		if with_links and attr.begins_with("EXPURL:"):
			var url := attr.substr(7)
			result = result.replace(match.get_string(0), "[url=%s][code]%s[/code][/url]" % [url, highlighted])
		else:
			result = result.replace(match.get_string(0), "[code]" + highlighted + "[/code]")
	return result


## Tokenizes and colorizes a plain GDScript string character by character.
## When [param with_links] is true, known class names become clickable [code][url][/code] tags.
static func _parse(source: String, with_links: bool = false) -> String:
	var result := ""
	var i := 0
	var length := source.length()
	var prev_was_colon  := false
	var prev_was_arrow  := false
	var prev_was_func   := false

	while i < length:
		var c := source[i]

		# Comment
		if c == "#":
			var end := source.find("\n", i)
			if end == -1:
				end = length
			result += _color(source.substr(i, end - i), COLOR_COMMENT)
			i = end
			prev_was_colon = false
			prev_was_arrow = false
			prev_was_func  = false
			continue

		# String
		if c == "\"" or c == "'":
			var quote := c
			var triple := false
			if source.substr(i, 3) == quote + quote + quote:
				triple = true
				quote = quote + quote + quote
			var start := i
			i += quote.length()
			while i < length:
				if triple:
					if source.substr(i, 3) == quote:
						i += 3
						break
				else:
					if source[i] == "\\":
						i += 2
						continue
					if source[i] == quote[0]:
						i += 1
						break
					if source[i] == "\n":
						break
				i += 1
			result += _color(source.substr(start, i - start), COLOR_STRING)
			prev_was_colon = false
			prev_was_arrow = false
			prev_was_func  = false
			continue

		# Number — only when not part of an identifier
		if c.is_valid_int():
			var prev_is_word := i > 0 and (source[i - 1] == "_" or source[i - 1].is_valid_identifier())
			if not prev_is_word:
				var start := i
				while i < length and (source[i].is_valid_int() or source[i] == "." or source[i] == "x" or source[i] == "_"):
					i += 1
				result += _color(source.substr(start, i - start), COLOR_NUMBER)
				prev_was_colon = false
				prev_was_arrow = false
				prev_was_func  = false
				continue

		# Annotation
		if c == "@":
			var start := i
			i += 1
			while i < length and (source[i] == "_" or source[i].is_valid_identifier()):
				i += 1
			result += _color(source.substr(start, i - start), COLOR_ANNOTATION)
			prev_was_colon = false
			prev_was_arrow = false
			prev_was_func  = false
			continue

		# Word
		if c == "_" or c.is_valid_identifier():
			var start := i
			while i < length and (source[i] == "_" or source[i].is_valid_identifier() or source[i].is_valid_int()):
				i += 1
			var word := source.substr(start, i - start)

			# peek ahead past spaces for "("
			var j := i
			while j < length and source[j] == " ":
				j += 1
			var is_followed_by_paren := j < length and source[j] == "("

			if word in class_registry:
				var _page := class_registry[word] as String
				if with_links:
					result += "[url=%s][color=#%s]%s[/color][/url]" % [_page, COLOR_CUSTOM_TYPE.to_html(false), word]
				else:
					result += _color(word, COLOR_CUSTOM_TYPE)
			elif prev_was_colon or prev_was_arrow:
				if ClassDB.class_exists(word):
					if with_links:
						result += "[url=gddoc://%s][color=#%s]%s[/color][/url]" % [word, COLOR_CUSTOM_TYPE.to_html(false), word]
					else:
						result += _color(word, COLOR_CUSTOM_TYPE)
				elif word in TYPES:
					if with_links:
						result += "[url=gddoc://%s][color=#%s]%s[/color][/url]" % [word, COLOR_BUILTIN_TYPE.to_html(false), word]
					else:
						result += _color(word, COLOR_BUILTIN_TYPE)
				else:
					result += _color(word, COLOR_BUILTIN_TYPE)
			elif prev_was_func:
				result += _color(word, COLOR_FUNCTION_DEF)
			elif word in KEYWORDS:
				result += _color(word, COLOR_KEYWORD)
			elif word in TYPES:
				if with_links:
					result += "[url=gddoc://%s][color=#%s]%s[/color][/url]" % [word, COLOR_BUILTIN_TYPE.to_html(false), word]
				else:
					result += _color(word, COLOR_BUILTIN_TYPE)
			elif ClassDB.class_exists(word):
				if with_links:
					result += "[url=gddoc://%s][color=#%s]%s[/color][/url]" % [word, COLOR_CUSTOM_TYPE.to_html(false), word]
				else:
					result += _color(word, COLOR_CUSTOM_TYPE)
			elif word in BUILTINS:
				result += _color(word, COLOR_BUILTIN)
			elif is_followed_by_paren:
				result += _color(word, COLOR_FUNCTION)
			else:
				result += _color(word, COLOR_DEFAULT)

			prev_was_func  = (word == "func")
			prev_was_colon = false
			prev_was_arrow = false
			continue

		# Arrow "->" for return type hint
		if c == "-" and i + 1 < length and source[i + 1] == ">":
			result += _color("->", COLOR_SYMBOL)
			i += 2
			prev_was_arrow = true
			prev_was_colon = false
			prev_was_func  = false
			continue

		# Colon — type hint, but not "::"
		if c == ":":
			result += _color(c, COLOR_SYMBOL)
			i += 1
			if i < length and source[i] == ":":
				result += _color(":", COLOR_SYMBOL)
				i += 1
				prev_was_colon = false
			else:
				prev_was_colon = true
			prev_was_arrow = false
			prev_was_func  = false
			continue

		# Newline
		if c == "\n":
			result += "\n"
			i += 1
			prev_was_colon = false
			prev_was_arrow = false
			prev_was_func  = false
			continue

		if c == "\t":
			result += "    "
			i += 1
			continue

		# Space — preserve but skip flag resets so "func foo" works across spaces
		if c == " ":
			result += " "
			i += 1
			continue

		# Other symbols
		if c in "()[]{}.,;=+*/%&|^~<>!?":
			result += _color(c, COLOR_SYMBOL)
			i += 1
			prev_was_colon = false
			prev_was_arrow = false
			prev_was_func  = false
			continue

		result += c
		i += 1

	return result

## Wraps [param text] in a BBCode color tag using [param color].
## Escapes any literal [code][][/code] characters to avoid breaking BBCode parsing.
static func _color(text: String, color: Color) -> String:
	var escaped := text.replace("[", "[lb]")
	return "[color=#%s]%s[/color]" % [color.to_html(false), escaped]

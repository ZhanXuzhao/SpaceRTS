## A blockquote component supporting GitHub-flavored alert types.
## The [member quote_type] controls the border color, background tint, and title badge.
@tool
class_name DocQuote
extends PanelContainer


## Alert type variants for a blockquote.
enum TYPE {
	## Plain blockquote with no title badge.
	BASE,
	## Informational note.
	NOTE,
	## Helpful tip.
	TIP,
	## Important notice.
	IMPORTANT,
	## Non-critical warning.
	WARNING,
	## Critical caution.
	CAUTION
}

## Color palette for each [enum TYPE] variant, indexed by the enum value.
const type_colors: Array[Color] = [
	Color.WEB_GRAY,
	Color.ROYAL_BLUE,
	Color.LIME_GREEN,
	Color.PURPLE,
	Color.DARK_GOLDENROD,
	Color.MEDIUM_VIOLET_RED
]

## Lowercase name of the current type, e.g. [code]"warning"[/code].
var quote_type_name: String:
	get():
		return TYPE.keys()[quote_type].to_lower()
## HTML hex color string for the current type (with alpha).
var quote_html_color: String:
	get():
		return type_colors[quote_type].to_html(true)

## The alert type; setting this triggers a full refresh.
@export var quote_type: TYPE:
	set(value):
		quote_type = value
		refresh()

## DocText component that renders the alert title badge.
@export var title_text: DocText
## DocText component that renders the alert body.
@export var body_text: DocText


## Updates the title label, background style box color, and body text to match [member quote_type].
func refresh():
	if not title_text: return
	
	# Handle title node
	title_text.visible = quote_type != TYPE.BASE
	title_text.label_text = str("##### :", quote_type_name, ":  ", "[color=", quote_html_color, "]**", quote_type_name.capitalize(), "**[/color]")
	
	# Handle themes
	var theme_path = str("res://addons/axeldocs/dock/components/quotes/themes/quote_", quote_type_name, ".tres")
	var theme_color = type_colors[quote_type]
	var theme_stylebox: StyleBoxFlat = load(theme_path)
	
	theme_stylebox.border_color = theme_color
	theme_stylebox.bg_color = theme_color
	theme_stylebox.bg_color.a = .25 * int(title_text.visible)
	
	add_theme_stylebox_override("panel", theme_stylebox)
	
	# Final refresh
	title_text.refresh()
	body_text.refresh()

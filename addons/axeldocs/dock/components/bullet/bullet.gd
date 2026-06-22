## A single list item component.
## Supports bullet, numbered, and checkbox variants with arbitrary nesting depth.
@tool
class_name DocBullet
extends HBoxContainer


## Visual style variants for a list item.
enum TYPE {
	## A toggle checkbox item.
	CHECKBOX,
	## A numbered item.
	NUMBER,
	## An unordered bullet item.
	BULLET
}
## Nesting depth. Adds left margin proportional to the value.
@export var level: int:
	set(value):
		level = maxi(0, value)
		refresh()
		
## Visual style of the list item.
@export var type: TYPE:
	set(value):
		type = value
		refresh()

## Display number shown for [constant TYPE.NUMBER] items.
@export var bullet_number: int:
	set(value):
		bullet_number = maxi(0, value)
		refresh()


@export var bullet_margin: PanelContainer
@export var checkbox: CheckBox
@export var bullet: RichTextLabel
@export var number: RichTextLabel

@export var text_content: DocText


## Updates visibility of marker nodes and applies the nesting margin, then refreshes the text.
func refresh():
	if not is_node_ready():
		await ready

	bullet_margin.custom_minimum_size.x = 20 * level
	
	bullet.visible = type == TYPE.BULLET
	checkbox.visible = type == TYPE.CHECKBOX
	number.visible = type == TYPE.NUMBER
	
	number.text = str(bullet_number, ".")
	
	await Engine.get_main_loop().process_frame
	
	text_content.refresh()


## Sets the pressed state of the checkbox marker to [param state].
func set_checkbox(state: bool):
	get_node("Bullet/CheckBox").button_pressed = state

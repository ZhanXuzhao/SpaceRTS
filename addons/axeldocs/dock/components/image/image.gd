## An image component that scales to fill the content width.
## Height is clamped between [constant MIN_HEIGHT] and [constant MAX_HEIGHT]
## using the [constant ASPECT_RATIO].
@tool
class_name DocImage
extends PanelContainer


## Width-to-height ratio used when computing the scaled image height.
const ASPECT_RATIO: Vector2 = Vector2(2, 1)
## Maximum pixel height for the image component.
const MAX_HEIGHT: float = 230
## Minimum pixel height for the image component.
const MIN_HEIGHT: float = 30

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

## The texture to display; assigning it also updates the child TextureRect.
@export var image: Texture2D:
	set(value):
		image = value
		get_child(0).texture = image


## Initializes the component size and connects resize signals.
func _ready() -> void:
	refresh()
	_connect_signals()


## Recalculates and applies the image height based on the current content width.
func refresh():
	if not doc_view: return
	
	var content_width = doc_view.page_content.size.x
	
	var image_height = content_width * (ASPECT_RATIO.x/ASPECT_RATIO.y)
	image_height = clampf(image_height, MIN_HEIGHT, MAX_HEIGHT)
	
	custom_minimum_size.y = image_height


## Connects [signal page_content.item_rect_changed] to [method refresh] for live resizing.
func _connect_signals():
	if not doc_view: return
	
	# Refresh on content box change
	if not doc_view.page_content.item_rect_changed.is_connected(refresh):
		doc_view.page_content.item_rect_changed.connect(refresh)

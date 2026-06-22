## Axeldocs editor plugin entry point.
## Registers the documentation dock and the [code]axeldocs/docs_folder[/code]
## project setting, then cleans up when the plugin is disabled.
@tool
extends EditorPlugin

## Packed scene for the documentation dock.
const DOCK = preload("res://addons/axeldocs/dock/doc_view.tscn")
var _dock: Control

## Registers the project setting, instantiates the dock, and connects refresh signals.
func _enter_tree() -> void:
	# Project Settings (shows up in Project → Project Settings)
	if not ProjectSettings.has_setting("axeldocs/docs_folder"):
		ProjectSettings.set_setting("axeldocs/docs_folder", "res://docs")
	
	ProjectSettings.set_initial_value("axeldocs/docs_folder", "res://docs")
	ProjectSettings.add_property_info({
		"name": "axeldocs/docs_folder",
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_DIR,
	})
	ProjectSettings.set_as_basic("axeldocs/docs_folder", true)  # show outside Advanced mode

	_dock = DOCK.instantiate()
	_dock.name = "Documentation"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	_dock.visibility_changed.connect(_dock.refresh)
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_dock.refresh)


## Disconnects refresh signals, removes the dock from the editor, and frees it.
func _exit_tree() -> void:
	if _dock:
		EditorInterface.get_resource_filesystem().filesystem_changed.disconnect(_dock.refresh)
		remove_control_from_docks(_dock)
		_dock.queue_free()

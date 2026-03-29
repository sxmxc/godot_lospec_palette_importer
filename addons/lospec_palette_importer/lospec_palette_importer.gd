@tool
@icon("res://addons/lospec_palette_importer/assets/icon.svg")
extends EditorPlugin

var dock: EditorDock

func _enter_tree() -> void:
	var dock_scene: Control = preload("res://addons/lospec_palette_importer/lospec_importer_dock.tscn").instantiate()
	if dock_scene.has_method("setup"):
		dock_scene.call("setup", self)

	dock = EditorDock.new()
	dock.title = "Palette Importer"
	dock.layout_key = "lospec_palette_importer"
	dock.default_slot = EditorDock.DOCK_SLOT_LEFT_UR
	dock.available_layouts = EditorDock.DOCK_LAYOUT_ALL
	dock.add_child(dock_scene)
	add_dock(dock)


func _exit_tree() -> void:
	if dock == null:
		return

	remove_dock(dock)
	dock.queue_free()
	dock = null

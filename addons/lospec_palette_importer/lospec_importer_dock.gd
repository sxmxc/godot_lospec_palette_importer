@tool
extends MarginContainer

const PaletteImportParser = preload("res://addons/lospec_palette_importer/palette_import_parser.gd")
const LOSPEC_API_URL := "https://lospec.com/palette-list/%s.json"
const LOSPEC_REQUEST_TIMEOUT := 15.0
const LOSPEC_RESPONSE_BODY_LIMIT := 262144
const LOSPEC_MAX_REDIRECTS := 2
const MAX_PREVIEW_COLUMNS := 12
const PREVIEW_SWATCH_SIZE := Vector2(28, 28)
const PREVIEW_SWATCH_SPACING := 4.0

var _editor_plugin: EditorPlugin
var _http_request: HTTPRequest
var _open_dialog: EditorFileDialog
var _save_dialog: EditorFileDialog
var _error_dialog: AcceptDialog
var _format_options := PackedStringArray()
var _parse_result: Dictionary = {}
var _suggested_save_basename := "palette"

@onready var _source_path_edit: LineEdit = %SourcePathEdit
@onready var _browse_button: Button = %BrowseButton
@onready var _lospec_slug_edit: LineEdit = %LospecSlugEdit
@onready var _load_lospec_button: Button = %LoadLospecButton
@onready var _format_option: OptionButton = %FormatOption
@onready var _format_value_label: Label = %FormatValueLabel
@onready var _color_count_value_label: Label = %ColorCountValueLabel
@onready var _status_label: Label = %StatusLabel
@onready var _preview_hint_label: Label = %PreviewHintLabel
@onready var _preview_scroll: ScrollContainer = %PreviewScroll
@onready var _preview_grid: GridContainer = %PreviewGrid
@onready var _import_button: Button = %ImportButton


func setup(editor_plugin: EditorPlugin) -> void:
	_editor_plugin = editor_plugin


func _ready() -> void:
	_populate_format_options()
	_create_dialogs()
	_connect_signals()
	_preview_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_preview_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_preview_grid.custom_minimum_size = Vector2.ZERO
	_reset_preview()
	_status_label.text = "Choose a palette file to preview and import."
	_update_preview_columns()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_preview_columns()


func _populate_format_options() -> void:
	_format_options = PaletteImportParser.get_format_options()
	_format_option.clear()

	for format_name in _format_options:
		_format_option.add_item(format_name)

	_format_option.select(0)


func _create_dialogs() -> void:
	_open_dialog = EditorFileDialog.new()
	_open_dialog.title = "Select Palette File"
	_open_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	_open_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.dialog_hide_on_ok = true
	_open_dialog.filters = PackedStringArray([
		"*.hex ; Lospec HEX Palette",
		"*.gpl ; GIMP Palette",
		"*.ase ; Photoshop ASE Palette",
		"*.pal ; JASC Palette",
		"*.txt ; Paint.NET Palette / Hex Text",
		"*.* ; All Files",
	])
	add_child(_open_dialog)

	_save_dialog = EditorFileDialog.new()
	_save_dialog.title = "Save ColorPalette Resource"
	_save_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_save_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.dialog_hide_on_ok = true
	_save_dialog.filters = PackedStringArray([
		"*.tres ; Godot ColorPalette Resource",
	])
	add_child(_save_dialog)

	_http_request = HTTPRequest.new()
	_http_request.use_threads = true
	_http_request.timeout = LOSPEC_REQUEST_TIMEOUT
	_http_request.max_redirects = LOSPEC_MAX_REDIRECTS
	_http_request.body_size_limit = LOSPEC_RESPONSE_BODY_LIMIT
	add_child(_http_request)

	_error_dialog = AcceptDialog.new()
	_error_dialog.title = "Palette Importer"
	add_child(_error_dialog)


func _connect_signals() -> void:
	_browse_button.pressed.connect(_on_browse_pressed)
	_load_lospec_button.pressed.connect(_on_load_lospec_pressed)
	_lospec_slug_edit.text_submitted.connect(_on_lospec_slug_submitted)
	_format_option.item_selected.connect(_on_format_selected)
	_import_button.pressed.connect(_on_import_pressed)
	_open_dialog.file_selected.connect(_on_source_file_selected)
	_save_dialog.file_selected.connect(_on_save_file_selected)
	_http_request.request_completed.connect(_on_lospec_request_completed)


func _on_browse_pressed() -> void:
	if not _source_path_edit.text.is_empty():
		_open_dialog.current_path = _source_path_edit.text

	_open_dialog.popup_centered_ratio(0.75)


func _on_format_selected(_index: int) -> void:
	if not _source_path_edit.text.is_empty():
		_parse_selected_source()


func _on_source_file_selected(path: String) -> void:
	_source_path_edit.text = path
	_lospec_slug_edit.text = ""
	_parse_selected_source()


func _parse_selected_source() -> void:
	var requested_format := _get_selected_format()
	_parse_result = PaletteImportParser.parse_file(_source_path_edit.text, requested_format)
	if _parse_result.get("ok", false):
		_suggested_save_basename = _sanitize_save_basename(_source_path_edit.text.get_file().get_basename())
	_apply_parse_result(_parse_result)


func _on_lospec_slug_submitted(_text: String) -> void:
	_on_load_lospec_pressed()


func _on_load_lospec_pressed() -> void:
	var slug := _normalize_lospec_slug(_lospec_slug_edit.text)
	if slug.is_empty():
		_show_error("Enter a Lospec palette slug first.")
		return

	_lospec_slug_edit.text = slug
	_load_lospec_button.disabled = true
	_status_label.text = "Fetching palette from Lospec..."

	var request_error := _http_request.request(LOSPEC_API_URL % slug, PackedStringArray([
		"Accept: application/json",
	]))
	if request_error != OK:
		_load_lospec_button.disabled = false
		_show_error("Could not start the Lospec request:\n%s" % error_string(request_error))


func _on_lospec_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_load_lospec_button.disabled = false

	var slug := _lospec_slug_edit.text.strip_edges()
	if result != HTTPRequest.RESULT_SUCCESS and body.is_empty():
		_show_error("Failed to fetch the Lospec palette for \"%s\".\nRequest result: %d\nHTTP status: %d" % [slug, result, response_code])
		return

	var parse_result := PaletteImportParser.parse_lospec_json(body.get_string_from_utf8(), slug)
	if not parse_result.get("ok", false):
		_status_label.text = parse_result.get("message", "The Lospec palette could not be loaded.")
		_show_error(parse_result.get("message", "The Lospec palette could not be loaded."))
		return

	_source_path_edit.text = ""
	_parse_result = parse_result
	_suggested_save_basename = _sanitize_save_basename(parse_result.get("slug", slug))
	_apply_parse_result(_parse_result)


func _apply_parse_result(result: Dictionary) -> void:
	var ok := result.get("ok", false)
	if not ok:
		_format_value_label.text = "Unavailable"
		_color_count_value_label.text = "0"
		_status_label.text = result.get("message", "The selected file could not be parsed.")
		_import_button.disabled = true
		_reset_preview()
		return

	var colors: PackedColorArray = result.get("colors", PackedColorArray())
	_format_value_label.text = result.get("format", _get_selected_format())
	_color_count_value_label.text = str(colors.size())
	_status_label.text = result.get("message", "Palette ready to import.")
	_import_button.disabled = colors.is_empty()
	_rebuild_preview(colors)


func _on_import_pressed() -> void:
	if not _parse_result.get("ok", false):
		_show_error("Choose a valid palette file before importing.")
		return

	var default_directory := _get_default_save_directory()
	var default_file := "%s.tres" % _suggested_save_basename
	_save_dialog.current_dir = default_directory
	_save_dialog.current_file = default_file
	_save_dialog.current_path = default_directory.path_join(default_file)
	_save_dialog.popup_centered_ratio(0.75)


func _on_save_file_selected(path: String) -> void:
	var save_path := path
	if save_path.get_extension().is_empty():
		save_path += ".tres"

	var colors: PackedColorArray = _parse_result.get("colors", PackedColorArray())
	if colors.is_empty():
		_show_error("There are no colors to save.")
		return

	var palette := ColorPalette.new()
	palette.colors = colors

	var save_error := ResourceSaver.save(palette, save_path)
	if save_error != OK:
		_show_error("Failed to save ColorPalette resource:\n%s" % error_string(save_error))
		return

	_status_label.text = "Saved %d colors to %s." % [colors.size(), save_path]
	_refresh_editor_resource(save_path)


func _refresh_editor_resource(path: String) -> void:
	if _editor_plugin == null:
		return

	var editor_interface := _editor_plugin.get_editor_interface()
	if editor_interface == null:
		return

	var resource_filesystem = editor_interface.get_resource_filesystem()
	if resource_filesystem != null:
		if resource_filesystem.has_method("update_file"):
			resource_filesystem.call("update_file", path)
		elif resource_filesystem.has_method("scan"):
			resource_filesystem.call("scan")

	var saved_resource := ResourceLoader.load(path)
	if saved_resource != null:
		editor_interface.inspect_object(saved_resource, "", true)


func _rebuild_preview(colors: PackedColorArray) -> void:
	_clear_preview()
	_preview_hint_label.visible = colors.is_empty()
	_preview_grid.visible = not colors.is_empty()

	for color in colors:
		_preview_grid.add_child(_create_swatch(color))

	_update_preview_columns()


func _reset_preview() -> void:
	_clear_preview()
	_preview_hint_label.visible = true
	_preview_grid.visible = false


func _clear_preview() -> void:
	for child in _preview_grid.get_children():
		child.free()


func _create_swatch(color: Color) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = PREVIEW_SWATCH_SIZE + Vector2(4, 4)
	panel.tooltip_text = _format_color_tooltip(color)
	panel.focus_mode = Control.FOCUS_NONE

	var swatch := ColorRect.new()
	swatch.color = color
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(swatch)
	swatch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	swatch.offset_left = 2
	swatch.offset_top = 2
	swatch.offset_right = -2
	swatch.offset_bottom = -2

	return panel


func _update_preview_columns() -> void:
	if _preview_grid == null or _preview_scroll == null:
		return

	var available_width := max(_preview_scroll.size.x - 16.0, PREVIEW_SWATCH_SIZE.x)
	var columns := max(1, int(floor((available_width + PREVIEW_SWATCH_SPACING) / (PREVIEW_SWATCH_SIZE.x + PREVIEW_SWATCH_SPACING))))
	_preview_grid.columns = min(columns, MAX_PREVIEW_COLUMNS)


func _get_selected_format() -> String:
	var selected_id := _format_option.get_selected_id()
	if selected_id < 0 or selected_id >= _format_options.size():
		return PaletteImportParser.FORMAT_AUTO

	return _format_options[selected_id]


func _get_default_save_directory() -> String:
	if _editor_plugin == null:
		return "res://"

	var editor_interface := _editor_plugin.get_editor_interface()
	if editor_interface == null:
		return "res://"

	var selected_paths := editor_interface.get_selected_paths()
	if selected_paths.is_empty():
		return "res://"

	var selected_path := selected_paths[0]
	if ResourceLoader.exists(selected_path):
		return selected_path.get_base_dir()

	return selected_path


func _format_color_tooltip(color: Color) -> String:
	var red := clampi(int(round(color.r * 255.0)), 0, 255)
	var green := clampi(int(round(color.g * 255.0)), 0, 255)
	var blue := clampi(int(round(color.b * 255.0)), 0, 255)
	var alpha := clampi(int(round(color.a * 255.0)), 0, 255)

	if alpha == 255:
		return "#%02X%02X%02X" % [red, green, blue]

	return "#%02X%02X%02X%02X" % [red, green, blue, alpha]


func _normalize_lospec_slug(text: String) -> String:
	var normalized := text.strip_edges().to_lower().replace("_", "-").replace(" ", "-")
	var slug := ""

	for character in normalized:
		var code := character.unicode_at(0)
		var is_lower := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57
		if is_lower or is_digit or character == "-":
			slug += character

	while slug.contains("--"):
		slug = slug.replace("--", "-")
	while slug.begins_with("-"):
		slug = slug.substr(1)
	while slug.ends_with("-"):
		slug = slug.left(-1)

	return slug


func _sanitize_save_basename(text: String) -> String:
	var sanitized := ""
	for character in text.strip_edges():
		var code := character.unicode_at(0)
		var is_upper := code >= 65 and code <= 90
		var is_lower := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57

		if is_upper or is_lower or is_digit or character == "-" or character == "_":
			sanitized += character.to_lower()
		elif character == " " or character == ".":
			sanitized += "-"

	while sanitized.contains("--"):
		sanitized = sanitized.replace("--", "-")

	sanitized = sanitized.strip_edges().trim_prefix("-").trim_suffix("-")
	if sanitized.is_empty():
		return "palette"

	return sanitized


func _show_error(message: String) -> void:
	_error_dialog.dialog_text = message
	_error_dialog.popup_centered()

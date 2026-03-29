extends SceneTree

const PaletteImportParser = preload("res://addons/lospec_palette_importer/palette_import_parser.gd")

var _failures: PackedStringArray = PackedStringArray()


func _init() -> void:
	_run()

	if _failures.is_empty():
		print("All parser smoke tests passed.")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
		print("FAIL: %s" % failure)

	quit(1)


func _run() -> void:
	_test_hex_palette()
	_test_gpl_palette()
	_test_jasc_palette()
	_test_paint_net_palette()
	_test_ase_palette()
	_test_lospec_json()
	_test_color_palette_resource_round_trip()


func _test_hex_palette() -> void:
	var result := PaletteImportParser.parse_file("res://tests/external_palettes/desolate-guest.hex")
	_assert_true(result.get("ok", false), "HEX palette should parse successfully.")
	_assert_equal(result.get("format", ""), PaletteImportParser.FORMAT_HEX, "HEX auto-detect should prefer the .hex extension.")
	_assert_equal(result.get("colors", PackedColorArray()).size(), 128, "HEX palette should parse the expected number of colors.")


func _test_gpl_palette() -> void:
	var result := PaletteImportParser.parse_file("res://tests/external_palettes/sample.gpl")
	_assert_true(result.get("ok", false), "GPL palette should parse successfully.")
	_assert_equal(result.get("format", ""), PaletteImportParser.FORMAT_GPL, "GPL palette should auto-detect correctly.")
	_assert_equal(result.get("colors", PackedColorArray()).size(), 3, "GPL palette should parse three colors.")


func _test_jasc_palette() -> void:
	var result := PaletteImportParser.parse_file("res://tests/external_palettes/sample.pal")
	_assert_true(result.get("ok", false), "JASC PAL palette should parse successfully.")
	_assert_equal(result.get("format", ""), PaletteImportParser.FORMAT_JASC, "JASC PAL palette should auto-detect correctly.")
	_assert_equal(result.get("colors", PackedColorArray()).size(), 3, "JASC PAL palette should parse three colors.")


func _test_paint_net_palette() -> void:
	var result := PaletteImportParser.parse_file("res://tests/external_palettes/sample.txt")
	_assert_true(result.get("ok", false), "Paint.NET palette should parse successfully.")
	_assert_equal(result.get("format", ""), PaletteImportParser.FORMAT_PAINT_NET, "Paint.NET palette should auto-detect correctly.")
	_assert_equal(result.get("colors", PackedColorArray()).size(), 3, "Paint.NET palette should parse three colors.")


func _test_ase_palette() -> void:
	var ase_path := "user://sample_palette.ase"
	var file := FileAccess.open(ase_path, FileAccess.WRITE)
	if file == null:
		_fail("ASE fixture file could not be created in user://.")
		return

	file.store_buffer(_build_sample_ase_bytes())
	file.close()

	var result := PaletteImportParser.parse_file(ase_path)
	_assert_true(result.get("ok", false), "ASE palette should parse successfully.")
	_assert_equal(result.get("format", ""), PaletteImportParser.FORMAT_ASE, "ASE palette should auto-detect correctly.")
	_assert_equal(result.get("colors", PackedColorArray()).size(), 1, "ASE palette should parse one color.")


func _test_lospec_json() -> void:
	var result := PaletteImportParser.parse_lospec_json("""{
		"name": "Greyt-bit",
		"author": "Sam Keddy",
		"colors": ["574368", "8488d3", "cfd3c1"]
	}""", "greyt-bit")
	_assert_true(result.get("ok", false), "Lospec JSON should parse successfully.")
	_assert_equal(result.get("format", ""), PaletteImportParser.FORMAT_LOSPEC, "Lospec JSON should report the Lospec API format.")
	_assert_equal(result.get("colors", PackedColorArray()).size(), 3, "Lospec JSON should parse three colors.")

	var missing_result := PaletteImportParser.parse_lospec_json("""{"error":"file not found"}""", "missing-palette")
	_assert_true(not missing_result.get("ok", true), "Missing Lospec slug should return an error result.")


func _test_color_palette_resource_round_trip() -> void:
	var parse_result := PaletteImportParser.parse_file("res://tests/external_palettes/invaders-birthright.hex")
	_assert_true(parse_result.get("ok", false), "Round-trip fixture palette should parse successfully.")
	if not parse_result.get("ok", false):
		return

	var save_path := "user://round_trip_palette.tres"
	var palette := ColorPalette.new()
	palette.colors = parse_result.get("colors", PackedColorArray())

	var save_error := ResourceSaver.save(palette, save_path)
	_assert_equal(save_error, OK, "ColorPalette resource should save successfully.")
	if save_error != OK:
		return

	var loaded_palette := ResourceLoader.load(save_path)
	_assert_true(loaded_palette is ColorPalette, "Saved resource should load back as a ColorPalette.")
	if loaded_palette is ColorPalette:
		_assert_equal(loaded_palette.colors.size(), palette.colors.size(), "Saved ColorPalette should preserve color count.")


func _build_sample_ase_bytes() -> PackedByteArray:
	var block := StreamPeerBuffer.new()
	block.big_endian = true
	block.put_u16(1)
	block.put_u16(0)
	block.put_data("RGB ".to_ascii_buffer())
	block.put_float(1.0)
	block.put_float(0.5)
	block.put_float(0.0)

	var bytes := StreamPeerBuffer.new()
	bytes.big_endian = true
	bytes.put_data("ASEF".to_ascii_buffer())
	bytes.put_u16(1)
	bytes.put_u16(0)
	bytes.put_u32(1)
	bytes.put_u16(0x0001)
	bytes.put_u32(block.data_array.size())
	bytes.put_data(block.data_array)
	return bytes.data_array


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _assert_equal(actual, expected, message: String) -> void:
	if actual != expected:
		_fail("%s Expected %s, got %s." % [message, str(expected), str(actual)])


func _fail(message: String) -> void:
	_failures.append(message)

@tool
extends RefCounted

const FORMAT_AUTO := "Auto Detect"
const FORMAT_HEX := "Lospec HEX"
const FORMAT_GPL := "GIMP GPL"
const FORMAT_ASE := "Photoshop ASE"
const FORMAT_JASC := "JASC PAL"
const FORMAT_PAINT_NET := "Paint.NET TXT"
const FORMAT_LOSPEC := "Lospec API"


static func get_format_options() -> PackedStringArray:
	return PackedStringArray([
		FORMAT_AUTO,
		FORMAT_HEX,
		FORMAT_GPL,
		FORMAT_ASE,
		FORMAT_JASC,
		FORMAT_PAINT_NET,
	])


static func parse_file(path: String, requested_format: String = FORMAT_AUTO) -> Dictionary:
	if path.is_empty():
		return _error("Choose a palette file first.")

	if not FileAccess.file_exists(path):
		return _error("The selected file does not exist:\n%s" % path)

	var bytes := FileAccess.get_file_as_bytes(path)
	var selected_format := requested_format
	if selected_format == FORMAT_AUTO:
		selected_format = _detect_format(path, bytes)

	if selected_format.is_empty():
		return _error("Could not detect the palette format for:\n%s" % path)

	match selected_format:
		FORMAT_HEX:
			return _finalize_result(selected_format, _parse_hex_text(_decode_text(bytes)))
		FORMAT_GPL:
			return _finalize_result(selected_format, _parse_gpl_text(_decode_text(bytes)))
		FORMAT_ASE:
			return _finalize_result(selected_format, _parse_ase_bytes(bytes))
		FORMAT_JASC:
			return _finalize_result(selected_format, _parse_jasc_text(_decode_text(bytes)))
		FORMAT_PAINT_NET:
			return _finalize_result(selected_format, _parse_paint_net_text(_decode_text(bytes)))
		_:
			return _error("Unsupported palette format: %s" % selected_format)


static func parse_lospec_json(json_text: String, slug: String = "") -> Dictionary:
	var response_text := json_text.strip_edges()
	if response_text.is_empty():
		return _error("Lospec returned an empty response.")
	if response_text.to_lower().contains("file not found"):
		return _error("Lospec could not find a palette for slug \"%s\": file not found" % slug)

	var parsed := JSON.parse_string(response_text)
	if not (parsed is Dictionary):
		return _error("Lospec returned invalid JSON.")

	return _parse_lospec_dictionary(parsed, slug)


static func _finalize_result(format_name: String, result: Dictionary) -> Dictionary:
	if not result.get("ok", false):
		return result

	var colors: PackedColorArray = result.get("colors", PackedColorArray())
	result["format"] = format_name
	result["message"] = "Parsed %d colors from %s." % [colors.size(), format_name]
	return result


static func _detect_format(path: String, bytes: PackedByteArray) -> String:
	var extension_format := _get_format_from_extension(path.get_extension().to_lower())
	if _looks_like_ase(bytes):
		return FORMAT_ASE

	var text := _decode_text(bytes)
	var normalized := _normalize_text(text)
	var compact_lines := _get_data_lines(normalized)

	if normalized.begins_with("GIMP Palette"):
		return FORMAT_GPL
	if normalized.begins_with("JASC-PAL"):
		return FORMAT_JASC
	if normalized.to_lower().contains("paint.net palette file"):
		return FORMAT_PAINT_NET

	if not extension_format.is_empty():
		return extension_format

	if _looks_like_paint_net(compact_lines):
		return FORMAT_PAINT_NET
	if _looks_like_hex_list(compact_lines):
		return FORMAT_HEX

	return ""


static func _get_format_from_extension(extension: String) -> String:
	match extension:
		"ase":
			return FORMAT_ASE
		"gpl":
			return FORMAT_GPL
		"pal":
			return FORMAT_JASC
		"txt":
			return FORMAT_PAINT_NET
		"hex":
			return FORMAT_HEX
		_:
			return ""


static func _decode_text(bytes: PackedByteArray) -> String:
	return _normalize_text(bytes.get_string_from_utf8())


static func _normalize_text(text: String) -> String:
	var normalized := text.replace("\r\n", "\n").replace("\r", "\n")
	if not normalized.is_empty() and normalized.unicode_at(0) == 0xfeff:
		normalized = normalized.substr(1)
	return normalized


static func _get_data_lines(text: String) -> PackedStringArray:
	var lines := PackedStringArray()
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty():
			continue
		lines.append(line)
	return lines


static func _parse_hex_text(text: String) -> Dictionary:
	var colors := PackedColorArray()
	var line_number := 0

	for raw_line in text.split("\n"):
		line_number += 1
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with("#") or line.begins_with(";"):
			continue

		var token := _sanitize_hex_token(line)
		if not _is_hex_string(token) or (token.length() != 6 and token.length() != 8):
			return _error("Invalid hex color on line %d:\n%s" % [line_number, raw_line])

		if token.length() == 6:
			colors.push_back(_color_from_rgb_hex(token))
		else:
			colors.push_back(_color_from_rgba_hex(token))

	if colors.is_empty():
		return _error("No colors were found in the hex palette.")

	return {
		"ok": true,
		"colors": colors,
	}


static func _parse_gpl_text(text: String) -> Dictionary:
	if not text.begins_with("GIMP Palette"):
		return _error("This file does not start with the GIMP Palette header.")

	var colors := PackedColorArray()
	var line_number := 0

	for raw_line in text.split("\n"):
		line_number += 1
		var line := raw_line.strip_edges()
		if line_number == 1 or line.is_empty() or line.begins_with("#"):
			continue
		if line.begins_with("Name:") or line.begins_with("Columns:"):
			continue

		var tokens := _split_tokens(line)
		if tokens.size() < 3:
			return _error("Invalid GPL color line %d:\n%s" % [line_number, raw_line])
		if not tokens[0].is_valid_int() or not tokens[1].is_valid_int() or not tokens[2].is_valid_int():
			return _error("Invalid GPL RGB values on line %d:\n%s" % [line_number, raw_line])

		colors.push_back(Color.from_rgba8(
			clampi(tokens[0].to_int(), 0, 255),
			clampi(tokens[1].to_int(), 0, 255),
			clampi(tokens[2].to_int(), 0, 255)
		))

	if colors.is_empty():
		return _error("No colors were found in the GPL palette.")

	return {
		"ok": true,
		"colors": colors,
	}


static func _parse_jasc_text(text: String) -> Dictionary:
	var lines := _get_data_lines(text)
	if lines.size() < 4 or lines[0] != "JASC-PAL":
		return _error("This file does not start with the JASC-PAL header.")

	if not lines[2].is_valid_int():
		return _error("The JASC palette color count is invalid.")

	var expected_count := lines[2].to_int()
	var colors := PackedColorArray()

	for index in range(3, lines.size()):
		var tokens := _split_tokens(lines[index])
		if tokens.size() < 3:
			return _error("Invalid JASC PAL color line %d:\n%s" % [index + 1, lines[index]])
		if not tokens[0].is_valid_int() or not tokens[1].is_valid_int() or not tokens[2].is_valid_int():
			return _error("Invalid JASC PAL RGB values on line %d:\n%s" % [index + 1, lines[index]])

		colors.push_back(Color.from_rgba8(
			clampi(tokens[0].to_int(), 0, 255),
			clampi(tokens[1].to_int(), 0, 255),
			clampi(tokens[2].to_int(), 0, 255)
		))

	if colors.size() != expected_count:
		return _error("The JASC PAL file declares %d colors, but %d were parsed." % [expected_count, colors.size()])

	return {
		"ok": true,
		"colors": colors,
	}


static func _parse_paint_net_text(text: String) -> Dictionary:
	var colors := PackedColorArray()
	var line_number := 0

	for raw_line in text.split("\n"):
		line_number += 1
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with(";"):
			continue

		var token := _sanitize_hex_token(line)
		if not _is_hex_string(token) or (token.length() != 8 and token.length() != 6):
			return _error("Invalid Paint.NET palette color on line %d:\n%s" % [line_number, raw_line])

		if token.length() == 8:
			colors.push_back(_color_from_argb_hex(token))
		else:
			colors.push_back(_color_from_rgb_hex(token))

	if colors.is_empty():
		return _error("No colors were found in the Paint.NET palette.")

	return {
		"ok": true,
		"colors": colors,
	}


static func _parse_lospec_dictionary(data: Dictionary, slug: String) -> Dictionary:
	if data.has("error"):
		var error_text := str(data.get("error", "file not found")).strip_edges()
		if error_text.is_empty():
			error_text = "file not found"
		return _error("Lospec could not find a palette for slug \"%s\": %s" % [slug, error_text])

	if not data.has("colors") or not (data["colors"] is Array):
		return _error("Lospec JSON is missing the colors array.")

	var palette_name := str(data.get("name", slug)).strip_edges()
	var author_name := str(data.get("author", "")).strip_edges()
	var colors := PackedColorArray()

	for color_value in data["colors"]:
		var token := _sanitize_hex_token(str(color_value))
		if not _is_hex_string(token) or (token.length() != 6 and token.length() != 8):
			return _error("Lospec returned an invalid color value: %s" % str(color_value))

		if token.length() == 6:
			colors.push_back(_color_from_rgb_hex(token))
		else:
			colors.push_back(_color_from_rgba_hex(token))

	if colors.is_empty():
		return _error("Lospec returned a palette with no colors.")

	var message := "Loaded %d colors from Lospec" % colors.size()
	if not palette_name.is_empty():
		message += ": %s" % palette_name
	if not author_name.is_empty():
		message += " by %s" % author_name
	message += "."

	return {
		"ok": true,
		"format": FORMAT_LOSPEC,
		"name": palette_name,
		"author": author_name,
		"slug": slug,
		"colors": colors,
		"message": message,
	}


static func _parse_ase_bytes(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 12:
		return _error("The ASE file is too small to be valid.")
	if not _looks_like_ase(bytes):
		return _error("This file does not start with the ASE header.")

	var cursor := 4
	var version_major := _read_be_u16(bytes, cursor)
	cursor += 2
	var version_minor := _read_be_u16(bytes, cursor)
	cursor += 2
	var block_count := _read_be_u32(bytes, cursor)
	cursor += 4

	if version_major <= 0:
		return _error("Unsupported ASE version %d.%d." % [version_major, version_minor])

	var colors := PackedColorArray()
	for _block_index in block_count:
		if cursor + 6 > bytes.size():
			return _error("Unexpected end of ASE file while reading blocks.")

		var block_type := _read_be_u16(bytes, cursor)
		cursor += 2
		var block_length := _read_be_u32(bytes, cursor)
		cursor += 4
		var block_end := cursor + block_length
		if block_end > bytes.size():
			return _error("ASE block length exceeds the file size.")

		if block_type == 0x0001:
			var parsed := _parse_ase_color_block(bytes, cursor, block_end)
			if not parsed.get("ok", false):
				return parsed
			if parsed.has("color"):
				colors.push_back(parsed["color"])

		cursor = block_end

	if colors.is_empty():
		return _error("No color entries were found in the ASE file.")

	return {
		"ok": true,
		"colors": colors,
	}


static func _parse_ase_color_block(bytes: PackedByteArray, cursor: int, block_end: int) -> Dictionary:
	if cursor + 2 > block_end:
		return _error("ASE color block is truncated before the name length.")

	var name_length := _read_be_u16(bytes, cursor)
	cursor += 2
	var name_bytes := name_length * 2
	if cursor + name_bytes > block_end:
		return _error("ASE color block name exceeds the block size.")
	cursor += name_bytes

	if cursor + 4 > block_end:
		return _error("ASE color block is truncated before the color model.")

	var model := bytes.slice(cursor, cursor + 4).get_string_from_ascii()
	cursor += 4

	match model:
		"RGB ":
			if cursor + 12 > block_end:
				return _error("ASE RGB color block is truncated.")
			return {
				"ok": true,
				"color": Color(
					clampf(_read_be_float(bytes, cursor), 0.0, 1.0),
					clampf(_read_be_float(bytes, cursor + 4), 0.0, 1.0),
					clampf(_read_be_float(bytes, cursor + 8), 0.0, 1.0),
					1.0
				),
			}
		"CMYK":
			if cursor + 16 > block_end:
				return _error("ASE CMYK color block is truncated.")
			return {
				"ok": true,
				"color": _cmyk_to_rgb(
					_read_be_float(bytes, cursor),
					_read_be_float(bytes, cursor + 4),
					_read_be_float(bytes, cursor + 8),
					_read_be_float(bytes, cursor + 12)
				),
			}
		"Gray":
			if cursor + 4 > block_end:
				return _error("ASE Gray color block is truncated.")
			var gray := clampf(_read_be_float(bytes, cursor), 0.0, 1.0)
			return {
				"ok": true,
				"color": Color(gray, gray, gray, 1.0),
			}
		"LAB ":
			if cursor + 12 > block_end:
				return _error("ASE LAB color block is truncated.")
			return {
				"ok": true,
				"color": _lab_to_rgb(
					_read_be_float(bytes, cursor),
					_read_be_float(bytes, cursor + 4),
					_read_be_float(bytes, cursor + 8)
				),
			}
		_:
			return _error("Unsupported ASE color model: %s" % model.strip_edges())


static func _looks_like_ase(bytes: PackedByteArray) -> bool:
	return bytes.size() >= 4 and bytes.slice(0, 4).get_string_from_ascii() == "ASEF"


static func _looks_like_hex_list(lines: PackedStringArray) -> bool:
	if lines.is_empty():
		return false

	var saw_color := false
	for line in lines:
		if line.begins_with("#") or line.begins_with(";"):
			continue

		var token := _sanitize_hex_token(line)
		if not _is_hex_string(token):
			return false
		if token.length() != 6 and token.length() != 8:
			return false
		saw_color = true

	return saw_color


static func _looks_like_paint_net(lines: PackedStringArray) -> bool:
	if lines.is_empty():
		return false

	var saw_color := false
	for line in lines:
		if line.begins_with(";"):
			saw_color = saw_color or line.to_lower().contains("paint.net palette file")
			continue

		var token := _sanitize_hex_token(line)
		if not _is_hex_string(token):
			return false
		if token.length() != 8 and token.length() != 6:
			return false
		saw_color = true

	return saw_color


static func _sanitize_hex_token(token: String) -> String:
	var sanitized := token.strip_edges()
	if sanitized.begins_with("#"):
		sanitized = sanitized.substr(1)
	if sanitized.to_lower().begins_with("0x"):
		sanitized = sanitized.substr(2)
	return sanitized


static func _is_hex_string(token: String) -> bool:
	if token.is_empty():
		return false

	for character in token.to_lower():
		var code := character.unicode_at(0)
		var is_digit := code >= 48 and code <= 57
		var is_hex_letter := code >= 97 and code <= 102
		if not is_digit and not is_hex_letter:
			return false

	return true


static func _split_tokens(line: String) -> PackedStringArray:
	return line.replace("\t", " ").split(" ", false)


static func _color_from_rgb_hex(hex_text: String) -> Color:
	var value := hex_text.hex_to_int()
	return Color.from_rgba8(
		(value >> 16) & 0xff,
		(value >> 8) & 0xff,
		value & 0xff,
		255
	)


static func _color_from_rgba_hex(hex_text: String) -> Color:
	var value := hex_text.hex_to_int()
	return Color.from_rgba8(
		(value >> 24) & 0xff,
		(value >> 16) & 0xff,
		(value >> 8) & 0xff,
		value & 0xff
	)


static func _color_from_argb_hex(hex_text: String) -> Color:
	var value := hex_text.hex_to_int()
	return Color.from_rgba8(
		(value >> 16) & 0xff,
		(value >> 8) & 0xff,
		value & 0xff,
		(value >> 24) & 0xff
	)


static func _read_be_u16(bytes: PackedByteArray, offset: int) -> int:
	return (bytes[offset] << 8) | bytes[offset + 1]


static func _read_be_u32(bytes: PackedByteArray, offset: int) -> int:
	return (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3]


static func _read_be_float(bytes: PackedByteArray, offset: int) -> float:
	var raw := _read_be_u32(bytes, offset)
	var sign := -1.0 if ((raw >> 31) & 1) == 1 else 1.0
	var exponent := (raw >> 23) & 0xff
	var mantissa := raw & 0x7fffff

	if exponent == 0:
		if mantissa == 0:
			return 0.0
		return sign * pow(2.0, -126.0) * (float(mantissa) / float(1 << 23))
	if exponent == 0xff:
		return 0.0

	return sign * pow(2.0, float(exponent - 127)) * (1.0 + float(mantissa) / float(1 << 23))


static func _cmyk_to_rgb(c: float, m: float, y: float, k: float) -> Color:
	return Color(
		clampf((1.0 - clampf(c, 0.0, 1.0)) * (1.0 - clampf(k, 0.0, 1.0)), 0.0, 1.0),
		clampf((1.0 - clampf(m, 0.0, 1.0)) * (1.0 - clampf(k, 0.0, 1.0)), 0.0, 1.0),
		clampf((1.0 - clampf(y, 0.0, 1.0)) * (1.0 - clampf(k, 0.0, 1.0)), 0.0, 1.0),
		1.0
	)


static func _lab_to_rgb(lightness: float, a: float, b: float) -> Color:
	var fy := (lightness + 16.0) / 116.0
	var fx := fy + (a / 500.0)
	var fz := fy - (b / 200.0)

	var xr := _lab_pivot_inverse(fx)
	var yr := _lab_pivot_inverse(fy)
	var zr := _lab_pivot_inverse(fz)

	var x := xr * 95.047 / 100.0
	var y_component := yr * 100.0 / 100.0
	var z := zr * 108.883 / 100.0

	var linear_r := (3.2406 * x) + (-1.5372 * y_component) + (-0.4986 * z)
	var linear_g := (-0.9689 * x) + (1.8758 * y_component) + (0.0415 * z)
	var linear_b := (0.0557 * x) + (-0.2040 * y_component) + (1.0570 * z)

	return Color(
		clampf(_linear_to_srgb(linear_r), 0.0, 1.0),
		clampf(_linear_to_srgb(linear_g), 0.0, 1.0),
		clampf(_linear_to_srgb(linear_b), 0.0, 1.0),
		1.0
	)


static func _lab_pivot_inverse(value: float) -> float:
	var cube := value * value * value
	if cube > 0.008856:
		return cube
	return (value - (16.0 / 116.0)) / 7.787


static func _linear_to_srgb(value: float) -> float:
	if value <= 0.0031308:
		return 12.92 * value
	return (1.055 * pow(value, 1.0 / 2.4)) - 0.055


static func _error(message: String) -> Dictionary:
	return {
		"ok": false,
		"message": message,
	}

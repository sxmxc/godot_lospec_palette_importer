# Lospec Palette Importer

[![CI](https://github.com/sxmxc/godot_lospec_palette_importer/actions/workflows/ci.yml/badge.svg)](https://github.com/sxmxc/godot_lospec_palette_importer/actions/workflows/ci.yml)
[![Godot](https://img.shields.io/badge/Godot-4.6%2B-478cbf)](https://godotengine.org)
[![Release Automation](https://img.shields.io/badge/release-tags-blue)](https://github.com/sxmxc/godot_lospec_palette_importer/actions/workflows/release.yml)
[![License](https://img.shields.io/github/license/sxmxc/godot_lospec_palette_importer)](LICENSE)

Lospec Palette Importer is a Godot 4.6 editor plugin that adds a dock tab for importing external palette files into built-in `ColorPalette` resources.

## Features

- Imports Lospec newline-separated `.hex` palettes.
- Imports GIMP `.gpl`, Photoshop `.ase`, JASC `.pal`, and Paint.NET `.txt` palettes.
- Fetches palettes directly from `lospec.com` by slug.
- Previews parsed swatches in an editor dock before saving.
- Saves native `ColorPalette` `.tres` resources to any chosen `res://` location.

## Requirements

- Godot 4.6 or newer.

## Installation

### Asset Library

Install the addon from the Godot Asset Library, then enable **Project > Project Settings > Plugins > Lospec Palette Importer**.

### Git checkout

Copy `addons/lospec_palette_importer` into your project's `addons/` folder, then enable the plugin in **Project Settings > Plugins**.

## Usage

1. Open the **Palette Importer** dock tab in the editor.
2. Choose a local palette file with **Browse...**, or enter a Lospec slug and use **Load from Lospec**.
3. Review the detected format, color count, and preview.
4. Press **Import Palette...** and save the generated `ColorPalette` resource into `res://`.

## Security Notes

- Network access is only used when **Load from Lospec** is pressed.
- Lospec requests are restricted to `https://lospec.com/palette-list/{slug}.json`.
- The slug is normalized to lowercase letters, digits, and hyphens before any request is made.
- The response body is size-limited before JSON parsing.
- Local files are only read from paths explicitly chosen by the user.

## Publishing Notes

- The repository is set up so Asset Library ZIP downloads only include `addons/`.
- A copy of the readme and license is included inside the addon folder, as recommended by the Godot docs.
- Suggested submission assets live in `assets/images/`.

## License

This repository is licensed under the MIT License. See `LICENSE`.

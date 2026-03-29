# Lospec Palette Importer

Godot editor plugin for importing external palette files and Lospec palettes into built-in `ColorPalette` resources.

## Supported Sources

- Lospec `.hex`
- GIMP `.gpl`
- Photoshop `.ase`
- JASC `.pal`
- Paint.NET `.txt`
- `https://lospec.com/palette-list/{slug}.json`

## Use

1. Enable **Lospec Palette Importer** in **Project Settings > Plugins**.
2. Open the **Palette Importer** dock tab.
3. Load a local file or fetch a Lospec palette by slug.
4. Press **Import Palette...** to save a `ColorPalette` resource.

## Notes

- Tested with Godot 4.6.
- Network access is only used when fetching a Lospec palette manually from the dock UI.

## License

MIT. See `LICENSE.md`.

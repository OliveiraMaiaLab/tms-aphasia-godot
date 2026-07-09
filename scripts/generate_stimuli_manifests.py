#!/usr/bin/env python3
"""
generate_stimuli_manifests.py

Walks a Godot project's stimuli folder and writes a manifest.json (a flat
JSON array of image paths, relative to that folder) into every "objects" or
"actions" folder found underneath it.

Why this exists: Godot's DirAccess can't reliably list imported image files
inside an exported build - only the compiled/imported resource is packed,
not necessarily something a folder listing will surface. The game reads
these manifests at runtime instead of scanning folders, then loads each
image with ResourceLoader.load(), which does resolve correctly in exports.
Plain .json files aren't run through Godot's import pipeline, so they ship
in exports as-is and are always readable via FileAccess.

Run this locally whenever the stimuli image set changes, before exporting
the Godot project.

Usage:
    python generate_stimuli_manifests.py /path/to/godot_project/imagens/stimuli
"""
import argparse
import json
import sys
from pathlib import Path

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png"}
MANIFEST_NAME = "manifest.json"
BLOCK_FOLDER_NAMES = {"objects", "actions"}


def collect_relative_image_paths(folder: Path) -> list:
    """Recursively collect image file paths under `folder`, relative to it,
    as forward-slash strings (Godot res:// paths always use '/')."""
    paths = []
    for entry in sorted(folder.rglob("*")):
        if entry.is_file() and entry.suffix.lower() in IMAGE_EXTENSIONS:
            paths.append(entry.relative_to(folder).as_posix())
    return paths


def write_manifest(folder: Path) -> int:
    image_paths = collect_relative_image_paths(folder)
    manifest_path = folder / MANIFEST_NAME
    manifest_path.write_text(json.dumps(image_paths, indent=2), encoding="utf-8")
    print(f"  {manifest_path}: {len(image_paths)} image(s)")
    return len(image_paths)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "stimuli_root",
        type=Path,
        help="Path to the stimuli root folder (e.g. .../imagens/stimuli)",
    )
    args = parser.parse_args()

    root = args.stimuli_root
    if not root.is_dir():
        sys.exit(f"Error: '{root}' is not a directory.")

    total_manifests = 0
    total_images = 0
    for folder in sorted(p for p in root.rglob("*") if p.is_dir()):
        if folder.name in BLOCK_FOLDER_NAMES:
            total_images += write_manifest(folder)
            total_manifests += 1

    if total_manifests == 0:
        print(f"No 'objects' or 'actions' folders found under {root}.")
    else:
        print(f"\nWrote {total_manifests} manifest(s), {total_images} image(s) total.")


if __name__ == "__main__":
    main()
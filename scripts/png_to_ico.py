#!/usr/bin/env python3
"""png_to_ico.py

Small utility to convert a PNG image to a Windows / browser favicon (.ico).

Usage:
    python png_to_ico.py input.png [output.ico] [--sizes 16 32 48 64]

If `output.ico` is omitted it will use the same stem name as the input file.
The --sizes option lets you specify one or more square sizes (pixels). Defaults
are 16, 32, 48, 64.

Examples:
    python png_to_ico.py logo.png            # => logo.ico with 16/32/48/64 px
    python png_to_ico.py logo.png site.ico   # => site.ico with default sizes
    python png_to_ico.py logo.png --sizes 16 32 256  # 16,32,256 px inside ICO

Interactive mode
----------------
If you simply execute the script without any CLI arguments, it will enter an
interactive prompt asking for:

1. PNG file path (required)
2. Desired icon sizes (optional, comma-separated, default 16,32,48,64)

This makes it convenient for non-technical users who just want a quick
conversion without remembering the command-line syntax.

"""

import argparse
import sys
from pathlib import Path
from typing import List

try:
    from PIL import Image
except ImportError as exc:
    sys.exit("[ERROR] Pillow library not found. Install with: pip install pillow")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Convert a PNG to a favicon ICO file")
    parser.add_argument("input", type=Path, help="Source PNG image path")
    parser.add_argument("output", type=Path, nargs="?", help="Target ICO file path (default: <input>.ico)")
    parser.add_argument(
        "--sizes",
        type=int,
        nargs="+",
        metavar="N",
        default=[16, 32, 48, 64],
        help="Icon square sizes to include (pixels). Defaults: 16 32 48 64",
    )
    return parser.parse_args()


def ensure_png(path: Path) -> None:
    if not path.exists():
        sys.exit(f"[ERROR] input file '{path}' does not exist")
    if path.suffix.lower() != ".png":
        sys.exit("[ERROR] input file must be a .png image")


def load_image(path: Path) -> Image.Image:
    try:
        return Image.open(path).convert("RGBA")
    except Exception as exc:
        sys.exit(f"[ERROR] failed to load image: {exc}")


def create_icons(img: Image.Image, sizes: List[int]) -> List[Image.Image]:
    icons = []
    for sz in sizes:
        if img.width != img.height:
            # Resize based on longest side, then crop/pad to square
            side = max(img.width, img.height)
            square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
            square.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
            resized = square.resize((sz, sz), Image.LANCZOS)
        else:
            resized = img.resize((sz, sz), Image.LANCZOS)
        icons.append(resized)
    return icons


def save_ico(icons: List[Image.Image], dst: Path) -> None:
    try:
        # Pillow supports saving multiple sizes if you pass a list to save
        icons[0].save(dst, format="ICO", sizes=[icon.size for icon in icons])
    except Exception as exc:
        sys.exit(f"[ERROR] failed to save ICO: {exc}")


def main() -> None:
    # If no command-line arguments were given, fall back to an interactive prompt
    if len(sys.argv) == 1:
        print("PNG → ICO converter (interactive mode)\n")
        print("No arguments provided. Please follow the prompts below, or press Ctrl+C to abort.\n")

        png_path = input("PNG file path: ").strip().strip('"')
        if not png_path:
            sys.exit("[ABORT] No file specified")

        size_str = input("Icon sizes (comma-separated, default 16,32,48,64): ").strip()
        if size_str:
            sizes_list = [int(s) for s in size_str.split(',') if s.strip().isdigit()]
            # Re-inject into sys.argv so argparse can handle defaults / validation uniformly
            sys.argv.extend([png_path, "--sizes", *map(str, sizes_list)])
        else:
            sys.argv.append(png_path)

    args = parse_args()

    input_path = args.input
    ensure_png(input_path)

    output_path = args.output or input_path.with_suffix(".ico")
    sizes = sorted({abs(s) for s in args.sizes if s > 0})
    if not sizes:
        sys.exit("[ERROR] at least one positive size required")

    img = load_image(input_path)
    icons = create_icons(img, sizes)
    save_ico(icons, output_path)
    print(f"[OK] favicon saved to: {output_path} (sizes: {', '.join(map(str, sizes))} px)")


if __name__ == "__main__":
    main() 
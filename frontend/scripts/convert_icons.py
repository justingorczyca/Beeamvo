"""Generate app icons from the rounded source image and the macOS tray icon.

Usage:
    python scripts/convert_icons.py [source_image]

If no source image is given, defaults to assets/app_icon_rounded.png.
Requires Pillow: pip install Pillow
"""

import os
import sys
from PIL import Image, ImageDraw

script_dir = os.path.dirname(os.path.abspath(__file__))
frontend_dir = os.path.dirname(script_dir)
assets_dir = os.path.join(frontend_dir, "assets")

source_img = sys.argv[1] if len(sys.argv) > 1 else os.path.join(assets_dir, "app_icon_rounded.png")

app_icon_png = os.path.join(assets_dir, "app_icon.png")
app_icon_ico = os.path.join(assets_dir, "app_icon.ico")
tray_icon_macos = os.path.join(assets_dir, "tray_icon_macos.png")


def _scaled(value: float, scale: float) -> int:
    return int(round(value * scale))


def _generate_macos_tray_icon(output_path: str, size: int = 22) -> None:
    """Draw a bold monochrome microphone suitable for macOS template rendering.

    macOS menu bar icons are typically 16x16 points, rendered at 2x on Retina.
    Using 22x22 pixels with thick, bold shapes ensures visibility at all sizes.
    """

    # Draw at 4x resolution and downsample to keep the edges crisp in the menu bar.
    render_size = size * 4
    img = Image.new("RGBA", (render_size, render_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    ink = (0, 0, 0, 255)

    # Bold microphone design - all coordinates are in the 22x22 space
    # Center the design in the 22x22 canvas

    # Microphone capsule (main body) - wider and more prominent
    # Positioned at top center, 18px wide, 12px tall
    capsule_left = 2
    capsule_top = 1
    capsule_right = 20
    capsule_bottom = 13
    draw.rounded_rectangle(
        (capsule_left * 4, capsule_top * 4, capsule_right * 4, capsule_bottom * 4),
        radius=6 * 4,
        fill=ink,
    )

    # Neck - thicker connector between capsule and base
    neck_width = 6  # Thicker neck for visibility
    neck_left = (22 - neck_width) // 2  # Centered: 8
    neck_top = 12
    neck_bottom = 16
    draw.rounded_rectangle(
        (neck_left * 4, neck_top * 4, (neck_left + neck_width) * 4, neck_bottom * 4),
        radius=2 * 4,
        fill=ink,
    )

    # Base/stand - a solid curved bar, not three separate pieces
    # This is cleaner and more visible
    base_left = 6
    base_top = 15
    base_right = 16
    base_bottom = 19
    draw.rounded_rectangle(
        (base_left * 4, base_top * 4, base_right * 4, base_bottom * 4),
        radius=3 * 4,
        fill=ink,
    )

    macos_img = img.resize((size, size), Image.Resampling.LANCZOS)
    macos_img.save(output_path, format="PNG")
    print(f"Saved {output_path}")


try:
    img = Image.open(source_img)

    img.save(app_icon_png, format="PNG")
    print(f"Saved {app_icon_png}")

    ico_sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    img.save(app_icon_ico, format="ICO", sizes=ico_sizes)
    print(f"Saved {app_icon_ico}")

    _generate_macos_tray_icon(tray_icon_macos)

except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)

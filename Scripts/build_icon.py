import argparse
import struct
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw


ICON_SIZES = (16, 20, 24, 32, 40, 48, 64, 96, 128, 256)
MASK_SCALE = 4


def apply_circular_mask(image: Image.Image) -> Image.Image:
    width, height = image.size
    mask_size = (width * MASK_SCALE, height * MASK_SCALE)
    mask = Image.new("L", mask_size, 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse(
        (0, 0, mask_size[0] - 1, mask_size[1] - 1),
        fill=255,
    )
    mask = mask.resize((width, height), Image.Resampling.LANCZOS)

    rounded = image.copy()
    rounded.putalpha(ImageChops.multiply(image.getchannel("A"), mask))
    return rounded


def encode_windows_dib(image: Image.Image) -> bytes:
    image = image.convert("RGBA")
    width, height = image.size
    pixels = image.load()

    color_data = bytearray()
    for y in range(height - 1, -1, -1):
        for x in range(width):
            red, green, blue, alpha = pixels[x, y]
            color_data.extend((blue, green, red, alpha))

    mask_stride = ((width + 31) // 32) * 4
    mask_data = bytearray()
    for y in range(height - 1, -1, -1):
        row = bytearray(mask_stride)
        for x in range(width):
            if pixels[x, y][3] == 0:
                row[x // 8] |= 0x80 >> (x % 8)
        mask_data.extend(row)

    header = struct.pack(
        "<IiiHHIIiiII",
        40,
        width,
        height * 2,
        1,
        32,
        0,
        len(color_data),
        0,
        0,
        0,
        0,
    )
    return header + color_data + mask_data


def build_icon(source_path: Path, output_path: Path) -> None:
    with Image.open(source_path) as source:
        source = source.convert("RGBA")
        frames: list[tuple[int, bytes]] = []
        for size in ICON_SIZES:
            frame = source.resize((size, size), Image.Resampling.NEAREST)
            frame = apply_circular_mask(frame)
            frames.append((size, encode_windows_dib(frame)))

    header_size = 6 + 16 * len(frames)
    offset = header_size
    directory_entries = []
    payloads = []
    for size, payload in frames:
        encoded_size = 0 if size == 256 else size
        directory_entries.append(
            struct.pack(
                "<BBBBHHII",
                encoded_size,
                encoded_size,
                0,
                0,
                1,
                32,
                len(payload),
                offset,
            )
        )
        payloads.append(payload)
        offset += len(payload)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("wb") as output:
        output.write(struct.pack("<HHH", 0, 1, len(frames)))
        for entry in directory_entries:
            output.write(entry)
        for payload in payloads:
            output.write(payload)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build a pixel-sharp multi-size Windows .ico file."
    )
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    build_icon(args.source, args.output)


if __name__ == "__main__":
    main()

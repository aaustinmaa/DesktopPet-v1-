import argparse
import io
import struct
from pathlib import Path

from PIL import Image


ICON_SIZES = (16, 20, 24, 32, 40, 48, 64, 96, 128, 256)


def build_icon(source_path: Path, output_path: Path) -> None:
    with Image.open(source_path) as source:
        source = source.convert("RGBA")
        frames: list[tuple[int, bytes]] = []
        for size in ICON_SIZES:
            frame = source.resize((size, size), Image.Resampling.NEAREST)
            buffer = io.BytesIO()
            frame.save(buffer, format="PNG", optimize=False, compress_level=9)
            frames.append((size, buffer.getvalue()))

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

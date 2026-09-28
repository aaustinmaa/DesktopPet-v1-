#!/usr/bin/env python3
"""Portable source/asset checks. Swift type checking still requires a Mac SDK."""
import argparse
import ast
from pathlib import Path
import plistlib
import re
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--swift-syntax", action="store_true", help="Requires tree-sitter and tree-sitter-swift")
    args = parser.parse_args()
    files = sorted((ROOT / "Sources").rglob("*.swift")) + sorted((ROOT / "Tests").rglob("*.swift")) + [ROOT / "Package.swift"]
    for path in (ROOT / "scripts").glob("*.py"):
        ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    info = plistlib.loads((ROOT / "Support/Info.plist").read_bytes())
    assert info["LSMinimumSystemVersion"] == "14.0"
    assert info["CFBundleExecutable"] == "SuWuDu"
    sources = "\n".join(path.read_text(encoding="utf-8") for path in files)
    required = set(re.findall(r'"([\w-]+\.png)"', sources))
    for prefix, count, shen, shen_count in re.findall(r'frames\("([\w-]+)", (\d+), "([\w-]+)", (\d+)\)', sources):
        required.update(f"{prefix}-{i:02d}.png" for i in range(1, int(count) + 1))
        required.update(f"shenqing-{shen}-{i:02d}.png" for i in range(1, int(shen_count) + 1))
    for prefix, count in re.findall(r'sequence\("([\w-]+)", (\d+)\)', sources):
        required.update(f"{prefix}-{i:02d}.png" for i in range(1, int(count) + 1))
    missing = [name for name in required if not (ROOT.parent / "Assets/Sprites" / name).is_file()]
    assert not missing, f"Missing assets: {missing}"
    for name in ["Bell", "Done", "Piano", "Rock"]:
        assert (ROOT.parent / "Assets/Sounds" / f"{name}.wav").is_file(), name
    print(f"Verified {len(required)} referenced sprite frames, 4 WAV assets, Info.plist and Python syntax")
    if args.swift_syntax:
        sys.path.insert(0, str(ROOT / ".build/validation"))
        import tree_sitter
        import tree_sitter_swift
        swift = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
        failures = []
        for path in files:
            tree = swift.parse(path.read_bytes())
            stack = [tree.root_node]
            while stack:
                node = stack.pop()
                if node.type == "ERROR" or node.is_missing:
                    failures.append(f"{path.relative_to(ROOT)}:{node.start_point.row + 1}:{node.start_point.column + 1}: {node.type}")
                stack.extend(reversed(node.children))
        if failures:
            print("\n".join(failures), file=sys.stderr)
            return 1
        print(f"Parsed {len(files)} Swift files without syntax errors (not SDK type checking)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

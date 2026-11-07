#!/usr/bin/env python3
"""Seed an atlas with GB2312 level-one Hanzi and common CJK punctuation."""
import argparse
import json
import unicodedata
from pathlib import Path


def common_characters():
    chars = set("–—‘’“”·…•‰→←↑↓《》〈〉「」『』【】（）〔〕，。？！；：、　")
    for lead in [*range(0xA1, 0xAA), *range(0xB0, 0xD8)]:
        for trail in range(0xA1, 0xFF):
            try:
                chars.update(bytes([lead, trail]).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    return chars


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("include_files", nargs="*", type=Path)
    args = parser.parse_args()
    chars = common_characters()
    for file in args.include_files:
        contents = file.read_text(encoding="utf-8")
        if file.suffix.lower() == ".json":
            contents = json.dumps(json.loads(contents), ensure_ascii=False)
        chars.update(
            c for c in contents if ord(c) >= 128 and unicodedata.category(c)[0] != "C"
        )
    points = sorted({ord(c) for c in chars if ord(c) >= 128})
    args.output.write_text("\n".join(map(str, points)) + "\n", encoding="utf-8")
    print(f"Selected {len(points)} Unicode code points")


if __name__ == "__main__":
    main()

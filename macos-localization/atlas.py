#!/usr/bin/env python3
"""Compile a GGG Atlas export into PoB's read-only graph and Chinese dictionary."""
import argparse
import hashlib
import json
import math
import re
from collections import defaultdict
from pathlib import Path


def norm(value):
    return " ".join(re.sub(r"\[([^|\]]+)\|([^\]]+)\]", r"\2", value).split())


def load(path):
    return json.loads(path.read_text())


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=None, separators=(",", ":")) + "\n")


def angles(count):
    if count == 16:
        return sorted(set(range(0, 360, 30)) | set(range(0, 360, 45)))
    if count == 40:
        return sorted(set(range(0, 360, 10)) | set(range(0, 360, 45)))
    return [i * 360 / count for i in range(count)]


def geometry(tree):
    nodes, all_nodes = {}, tree["nodes"]
    start = set(all_nodes["root"]["out"])
    for key, item in all_nodes.items():
        if key == "root":
            continue
        group, orbit = tree["groups"][str(item["group"])], item["orbit"]
        radius = tree["constants"]["orbitRadii"][orbit]
        angle = math.radians(angles(tree["constants"]["skillsPerOrbit"][orbit])[item["orbitIndex"]])
        kind = next((k for k in ("mastery", "wormhole", "keystone", "notable") if item.get("is" + k.title())), "normal")
        if key in start:
            kind = "start"
        icon = {"start": "AtlasPassiveSkillScreenStart", "wormhole": "Wormhole"}.get(kind, item["icon"])
        nodes[key] = {
            "id": int(key), "name": norm(item["name"]) or "Atlas Start", "kind": kind,
            "x": round(group["x"] + math.sin(angle) * radius, 1),
            "y": round(group["y"] - math.cos(angle) * radius, 1),
            "icon": icon,
            "stats": [norm(s) for s in item["stats"] if norm(s)],
            "reminders": [norm(s) for s in item.get("reminderText", []) if norm(s)],
            "options": [[norm(s) for s in entry["stats"] if norm(s)] for entry in item.get("variantEffects", [])],
            "optionIds": [entry["effect"] for entry in item.get("variantEffects", [])],
        }
    edges, special = set(), {}
    for key, raw in all_nodes.items():
        if key not in nodes:
            continue
        for conn in raw.get("connections", []):
            if conn["to"] in nodes:
                special[tuple(sorted((key, conn["to"])))] = conn
        for other in raw.get("out", []) + raw.get("in", []) + [c["to"] for c in raw.get("connections", [])]:
            if other in nodes and other != key and nodes[other]["kind"] != "mastery" and nodes[key]["kind"] != "mastery":
                edges.add(tuple(sorted((key, other))))
    segments, ends = [], []
    for a, b in sorted(edges):
        raw, raw_b = all_nodes[a], all_nodes[b]
        u, v = nodes[a], nodes[b]
        points = [u["x"], u["y"]]
        center = None
        if (conn := special.get((a, b))) and "orbitX" in conn:
            center = (conn["orbitX"], conn["orbitY"])
        elif raw["orbit"] and raw["orbit"] == raw_b["orbit"] and raw["group"] == raw_b["group"]:
            group = tree["groups"][str(raw["group"])]
            center = (group["x"], group["y"])
        if center:
            x, y = center
            start = math.atan2(u["y"] - y, u["x"] - x)
            end = math.atan2(v["y"] - y, v["x"] - x)
            arc = (end - start + math.pi) % (2 * math.pi) - math.pi
            radius = (math.hypot(u["x"] - x, u["y"] - y) + math.hypot(v["x"] - x, v["y"] - y)) / 2
            steps = math.ceil(abs(arc) / (math.pi / 12))
            for step in range(1, steps):
                angle = start + arc * step / steps
                points += [round(x + radius * math.cos(angle), 1), round(y + radius * math.sin(angle), 1)]
        points += [v["x"], v["y"]]
        segments.append(points)
        ends.append([int(a), int(b)])
    return sorted(nodes.values(), key=lambda n: n["id"]), segments, ends


def sprites(art):
    slots = {
        "normalActive": "skills", "notableActive": "skills", "keystoneActive": "skills",
        "wormholeActive": "skills", "mastery": "mastery", "startNode": "groups", "frame": "frame",
    }
    frames = {
        "PSSkillFrame": "frameNormal", "NotableFrameUnallocated": "frameNotable",
        "KeystoneFrameUnallocated": "frameKeystone", "WormholeFrameUnallocated": "frameWormhole",
    }
    icons, sheets = {}, {}
    for kind, key in slots.items():
        meta = art["sprites"][kind]["0.2972"]
        sheets[key] = {"file": key + ".png", "width": meta["w"], "height": meta["h"]}
        for name, c in meta["coords"].items():
            if kind != "frame" or name in frames:
                icons[frames.get(name, name)] = [key, c["x"], c["y"], c["w"], c["h"]]
    return sheets, icons


def rows(tree):
    for node in tree["nodes"].values():
        if not node.get("name"):
            continue
        yield norm(node["name"])
        for key in ("stats", "reminderText"):
            yield from map(norm, node.get(key, []))
        for option in node.get("variantEffects", []):
            yield from map(norm, option["stats"])


def parallel_rows(en, cn):
    for key, left in en["nodes"].items():
        right = cn["nodes"].get(key)
        if not left.get("name") or not right or left["icon"] != right["icon"]:
            continue
        yield norm(left["name"]), norm(right["name"])
        for field in ("stats", "reminderText"):
            a, b = left.get(field, []), right.get(field, [])
            if len(a) == len(b):
                yield from zip(map(norm, a), map(norm, b), strict=True)
        right_effects = {e["effect"]: e["stats"] for e in right.get("variantEffects", [])}
        for effect in left.get("variantEffects", []):
            a, b = effect["stats"], right_effects.get(effect["effect"], [])
            if len(a) == len(b):
                yield from zip(map(norm, a), map(norm, b), strict=True)


number = re.compile(r"(?<![A-Za-z])\d+(?:\.\d+)?")


def chinese(atlas, en, cn, extra):
    texts = set(filter(None, rows(atlas)))
    lookup, drafts, ambiguous, patterns = {}, {}, set(), defaultdict(set)
    # Same version, node ID and icon on both official sites. Check the numeric literals too.
    for a, b in parallel_rows(en, cn):
        if not a or a == b or sorted(number.findall(a)) != sorted(number.findall(b)):
            continue
        if a in lookup and lookup[a] != b:
            ambiguous.add(a)
        lookup[a] = b
        if len(number.findall(a)) == 1:
            patterns[number.sub("#", a)].add(number.sub("#", b))
    for a in ambiguous:
        lookup.pop(a)
    for a in sorted(texts - lookup.keys()):
        nums = number.findall(a)
        options = patterns.get(number.sub("#", a))
        if len(nums) == 1 and options and len(options) == 1:
            drafts[a] = next(iter(options)).replace("#", nums[0])
    drafts.update({k: v for k, v in extra.items() if k in texts})
    return {k: drafts.get(k, lookup.get(k)) for k in sorted(texts) if k in lookup or k in drafts}, sorted(drafts)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--atlas", type=Path, required=True)
    p.add_argument("--official-en", type=Path, required=True)
    p.add_argument("--official-cn", type=Path, required=True)
    p.add_argument("--extra", type=Path, required=True, help="Draft translation map or a previously generated Atlas locale")
    p.add_argument("--root", type=Path, default=Path("src"))
    p.add_argument("--missing", type=Path)
    args = p.parse_args()
    atlas, en, cn = map(load, (args.atlas, args.official_en, args.official_cn))
    assert atlas["tree"] == en["tree"] == cn["tree"] == "Atlas"
    assert len(atlas["nodes"]) == 1117 and len(en["nodes"]) == len(cn["nodes"]) == 1030
    nodes, edges, ends = geometry(atlas)
    sheets, icons = sprites(en)
    graph = {
        "version": "3.30", "sourceSha256": hashlib.sha256(args.atlas.read_bytes()).hexdigest(),
        "bounds": [min(n["x"] for n in nodes), min(n["y"] for n in nodes),
                   max(n["x"] for n in nodes), max(n["y"] for n in nodes)],
        "nodes": nodes, "edges": edges, "edgeEnds": ends, "sheets": sheets, "icons": icons,
        "totalPoints": atlas["points"]["totalPoints"],
    }
    extra = load(args.extra)
    if "entries" in extra:
        extra = {k: extra["entries"][k] for k in extra.get("drafts", [])}
    entries, drafts = chinese(atlas, en, cn, extra)
    missed = sorted(set(filter(None, rows(atlas))) - entries.keys())
    if args.missing:
        args.missing.write_text("\n".join(missed) + "\n")
    write(args.root / "Data/Atlas/3_30/tree.json", graph)
    write(args.root / "Locales/Atlas/3_30.json", {"entries": entries, "drafts": drafts})
    print(f"{len(nodes)} nodes; {len(edges)} edges; {len(entries)} Chinese strings ({len(drafts)} local); {len(missed)} missing")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Register or unregister Swift source files in CuesLive.xcodeproj.

The project uses an explicit file list (not a synchronized folder), so every
new source file must be added to the project before Xcode will compile it.

Usage:
    Scripts/pbxproj-sources.py add CuesLive/Views/Foo/Bar.swift [...]
    Scripts/pbxproj-sources.py remove CuesLive/Views/Foo/Bar.swift [...]

Files under CuesLive/ are added to both app targets (CuesLive, CuesLiveAppStore).
Files under CuesLiveTests/ are added to the CuesLiveTests target.
The file's PBXGroup is located by finding an existing sibling in the same directory,
so a brand-new directory needs its first file added in Xcode by hand.
"""

import hashlib
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PBXPROJ = os.path.join(ROOT, "CuesLive.xcodeproj", "project.pbxproj")

APP_TARGET_PHASES = ["AA0000070000000000000001", "E87AB31F98AC96B094CA1C27"]
TEST_TARGET_PHASES = ["AA0000070000000000000002"]


def stable_id(key: str) -> str:
    return hashlib.md5(key.encode()).hexdigest()[:24].upper()


def quoted(name: str) -> str:
    """pbxproj only allows bare strings made of [A-Za-z0-9_./]; anything else must be quoted."""
    return name if re.fullmatch(r"[A-Za-z0-9_./]+", name) else f'"{name}"'


def read() -> str:
    with open(PBXPROJ, encoding="utf-8") as handle:
        return handle.read()


def write(text: str) -> None:
    with open(PBXPROJ, "w", encoding="utf-8") as handle:
        handle.write(text)


def phases_for(rel_path: str) -> list[str]:
    if rel_path.startswith("CuesLiveTests/"):
        return TEST_TARGET_PHASES
    if rel_path.startswith("CuesLive/"):
        return APP_TARGET_PHASES
    sys.exit(f"{rel_path}: must live under CuesLive/ or CuesLiveTests/")


def find_group_for(text: str, rel_path: str) -> str:
    """Return the object ID of the PBXGroup that holds the file's directory."""
    directory = os.path.dirname(rel_path)
    siblings = [
        name for name in os.listdir(os.path.join(ROOT, directory))
        if name.endswith(".swift") and name != os.path.basename(rel_path)
    ]
    for sibling in siblings:
        match = re.search(
            r"^\t\t(\w{24}) /\* " + re.escape(sibling) + r" \*/ = \{isa = PBXFileReference;",
            text,
            re.M,
        )
        if not match:
            continue
        file_ref = match.group(1)
        group = re.search(
            r"^\t\t(\w{24}) /\* [^*]+ \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \((?:(?!\);).)*?"
            + file_ref,
            text,
            re.M | re.S,
        )
        if group:
            return group.group(1)
    sys.exit(f"{rel_path}: could not find a PBXGroup via a registered sibling file")


def add(text: str, rel_path: str) -> str:
    name = os.path.basename(rel_path)
    if re.search(r"/\* " + re.escape(name) + r" \*/ = \{isa = PBXFileReference;", text):
        print(f"skip (already registered): {rel_path}")
        return text
    if not os.path.exists(os.path.join(ROOT, rel_path)):
        sys.exit(f"{rel_path}: file does not exist")

    file_ref = stable_id("ref:" + rel_path)
    group_id = find_group_for(text, rel_path)

    file_ref_line = (
        f"\t\t{file_ref} /* {name} */ = {{isa = PBXFileReference; "
        f"lastKnownFileType = sourcecode.swift; path = {quoted(name)}; sourceTree = \"<group>\"; }};\n"
    )
    text = text.replace("/* End PBXFileReference section */", file_ref_line + "/* End PBXFileReference section */", 1)

    build_lines = ""
    for phase in phases_for(rel_path):
        build_id = stable_id(f"build:{phase}:{rel_path}")
        build_lines += (
            f"\t\t{build_id} /* {name} in Sources */ = {{isa = PBXBuildFile; "
            f"fileRef = {file_ref} /* {name} */; }};\n"
        )
        phase_pattern = re.compile(
            r"(^\t\t" + phase + r" /\* Sources \*/ = \{\n\t\t\tisa = PBXSourcesBuildPhase;\n"
            r"\t\t\tbuildActionMask = \d+;\n\t\t\tfiles = \(\n)",
            re.M,
        )
        text, count = phase_pattern.subn(
            lambda m: m.group(1) + f"\t\t\t\t{build_id} /* {name} in Sources */,\n", text, 1
        )
        if count != 1:
            sys.exit(f"could not find sources phase {phase}")
    text = text.replace("/* End PBXBuildFile section */", build_lines + "/* End PBXBuildFile section */", 1)

    group_pattern = re.compile(
        r"(^\t\t" + group_id + r" /\* [^*]+ \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n)",
        re.M,
    )
    text, count = group_pattern.subn(
        lambda m: m.group(1) + f"\t\t\t\t{file_ref} /* {name} */,\n", text, 1
    )
    if count != 1:
        sys.exit(f"could not insert into group {group_id}")
    print(f"added: {rel_path}")
    return text


def remove(text: str, rel_path: str) -> str:
    name = os.path.basename(rel_path)
    match = re.search(
        r"^\t\t(\w{24}) /\* " + re.escape(name) + r" \*/ = \{isa = PBXFileReference;", text, re.M
    )
    if not match:
        print(f"skip (not registered): {rel_path}")
        return text
    file_ref = match.group(1)
    build_ids = re.findall(
        r"^\t\t(\w{24}) /\* " + re.escape(name) + r" in Sources \*/ = \{isa = PBXBuildFile; fileRef = "
        + file_ref,
        text,
        re.M,
    )
    ids = [file_ref] + build_ids
    lines = [line for line in text.split("\n") if not any(obj_id in line for obj_id in ids)]
    print(f"removed: {rel_path}")
    return "\n".join(lines)


def main() -> None:
    if len(sys.argv) < 3 or sys.argv[1] not in {"add", "remove"}:
        sys.exit(__doc__)
    text = read()
    for raw in sys.argv[2:]:
        rel_path = os.path.relpath(os.path.abspath(raw), ROOT)
        text = add(text, rel_path) if sys.argv[1] == "add" else remove(text, rel_path)
    write(text)


if __name__ == "__main__":
    main()

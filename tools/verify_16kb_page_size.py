#!/usr/bin/env python3
"""Verify every JNI .so in a Play App Bundle is 16 KB ELF-aligned.

Play rejects Android 15+ artifacts whose native libraries have LOAD
p_align < 16384. This checks the AAB (or an extracted lib/ tree) without
uploading it.

Usage:
  python tools/verify_16kb_page_size.py
  python tools/verify_16kb_page_size.py --aab path/to/app-release.aab
  python tools/verify_16kb_page_size.py --build
"""

from __future__ import annotations

import argparse
import struct
import subprocess
import sys
import zipfile
from pathlib import Path

PAGE = 16384
ELF_MAGIC = b"\x7fELF"
PT_LOAD = 1

REPO = Path(__file__).resolve().parents[1]
DEFAULT_AAB = REPO / "build" / "app" / "outputs" / "bundle" / "release" / "app-release.aab"


def elf_load_alignments(data: bytes) -> list[int]:
    if len(data) < 64 or data[:4] != ELF_MAGIC:
        raise ValueError("not an ELF file")
    ei_class = data[4]  # 1=32, 2=64
    ei_data = data[5]  # 1=LE, 2=BE
    endian = "<" if ei_data == 1 else ">"
    if ei_class == 2:
        e_phoff = struct.unpack_from(endian + "Q", data, 32)[0]
        e_phentsize, e_phnum = struct.unpack_from(endian + "HH", data, 54)
        align_off = 48
        phdr_fmt_end = "Q"
    elif ei_class == 1:
        e_phoff = struct.unpack_from(endian + "I", data, 28)[0]
        e_phentsize, e_phnum = struct.unpack_from(endian + "HH", data, 42)
        align_off = 28
        phdr_fmt_end = "I"
    else:
        raise ValueError(f"unknown ELF class {ei_class}")

    aligns: list[int] = []
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type = struct.unpack_from(endian + "I", data, off)[0]
        if p_type != PT_LOAD:
            continue
        (p_align,) = struct.unpack_from(endian + phdr_fmt_end, data, off + align_off)
        aligns.append(int(p_align))
    return aligns


def check_so(name: str, data: bytes) -> list[str]:
    problems: list[str] = []
    try:
        aligns = elf_load_alignments(data)
    except ValueError as e:
        return [f"{name}: {e}"]
    if not aligns:
        problems.append(f"{name}: no PT_LOAD segments")
        return problems
    for i, align in enumerate(aligns):
        if align < PAGE:
            problems.append(
                f"{name}: PT_LOAD[{i}] p_align={align} (< {PAGE})"
            )
    return problems


def iter_aab_sos(aab: Path):
    with zipfile.ZipFile(aab) as zf:
        for info in zf.infolist():
            name = info.filename.replace("\\", "/")
            if not name.endswith(".so"):
                continue
            if "/lib/" not in name and not name.startswith("lib/"):
                # Skip unrelated .so names if any; AAB stores them under
                # base/lib/<abi>/ or a split like 'base/lib/arm64-v8a/'.
                if "/jni/" not in name:
                    continue
            yield name, zf.read(info)


def build_aab() -> Path:
    cmd = ["flutter", "build", "appbundle", "--release"]
    print("Running:", " ".join(cmd), flush=True)
    subprocess.check_call(cmd, cwd=REPO)
    if not DEFAULT_AAB.is_file():
        raise SystemExit(f"Build finished but {DEFAULT_AAB} was not produced")
    return DEFAULT_AAB


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--aab", type=Path, help="Path to app-release.aab")
    parser.add_argument(
        "--build",
        action="store_true",
        help="Run `flutter build appbundle --release` first",
    )
    args = parser.parse_args()

    aab = args.aab
    if args.build:
        aab = build_aab()
    elif aab is None:
        aab = DEFAULT_AAB

    if not aab.is_file():
        print(
            f"No AAB at {aab}. Pass --build or --aab PATH.",
            file=sys.stderr,
        )
        return 2

    print(f"Checking {aab} for 16 KB ELF alignment…")
    problems: list[str] = []
    checked = 0
    for name, data in iter_aab_sos(aab):
        checked += 1
        problems.extend(check_so(name, data))
        if not any(name in p for p in problems[-4:]):
            print(f"  ok  {name}")

    if checked == 0:
        print("No .so files found in the bundle.", file=sys.stderr)
        return 2

    if problems:
        print("\nFAILED — Play will reject this bundle on Android 15+:")
        for p in problems:
            print(f"  {p}")
        return 1

    print(f"\nPassed: {checked} native libraries are 16 KB-aligned.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

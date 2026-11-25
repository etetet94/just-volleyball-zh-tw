"""Build the single-resource guide pack using only checked-in localized JSON.

Requires Python 3.9+. No original game files, decryption keys, or network needed.
The pack is deterministic: identical source bytes produce identical PCK bytes.
"""

import argparse
import hashlib
import json
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESOURCE = "res://game/ui/how_to_text.json"
DEFAULT_SOURCE = ROOT / "jv_zh_tw" / "guide_zhTW.json"
DEFAULT_OUTPUT = ROOT / "jv_zh_tw" / "guide_zhTW.pck"


def build_pack(payload: bytes) -> bytes:
    """Create a Godot PCK v2 with relative file offsets and one JSON resource."""
    document = json.loads(payload.decode("utf-8"))
    if not isinstance(document, dict) or not isinstance(document.get("categories"), list):
        raise ValueError("The guide must be a JSON object with a categories array")

    path_bytes = RESOURCE.encode("utf-8")
    path_bytes += bytes(-len(path_bytes) % 4)
    entry = struct.pack("<I", len(path_bytes)) + path_bytes
    entry += struct.pack("<QQ", 0, len(payload))
    entry += hashlib.md5(payload).digest() + struct.pack("<I", 0)
    file_base = (100 + len(entry) + 15) // 16 * 16

    # GDPC, pack v2, compatible with Godot 4.0+, relative-file-base flag.
    header = struct.pack("<6IQ", 0x43504447, 2, 4, 0, 0, 2, file_base)
    header += bytes(64) + struct.pack("<I", 1)
    pack = header + entry
    pack += bytes(file_base - len(pack))
    pack += payload + bytes(-len(payload) % 16)
    return pack


def write_pack(source: Path = DEFAULT_SOURCE, output: Path = DEFAULT_OUTPUT) -> bytes:
    pack = build_pack(source.read_bytes())
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(pack)
    return pack


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    pack = write_pack(args.source, args.output)
    print(f"Wrote {args.output} ({len(pack)} bytes)")
    print(f"SHA256: {hashlib.sha256(pack).hexdigest()}")


if __name__ == "__main__":
    main()

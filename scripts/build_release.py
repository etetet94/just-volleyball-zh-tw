"""Build a deterministic, allowlisted Windows install ZIP and SHA256 manifest.

Requires Python 3.9+ and its standard library only. Run from any directory.
"""

import argparse
import hashlib
import json
import re
import zipfile
from pathlib import Path

from build_guide_pack import write_pack


ROOT = Path(__file__).resolve().parents[1]
FILES = (
    "Install.cmd",
    "Uninstall.cmd",
    "Setup.ps1",
    "使用說明.txt",
    "README.md",
    "CHANGELOG.md",
    "docs/VALIDATION-v1.2.1.md",
    "LICENSE",
    "NOTICE.md",
    "jv_zh_tw/localize.gd",
    "jv_zh_tw/settings_panel.gd",
    "jv_zh_tw/match_extras.gd",
    "jv_zh_tw/impact_glyph.gd",
    "jv_zh_tw/effect_preview.gd",
    "jv_zh_tw/topple_stats.gd",
    "jv_zh_tw/ball_trails.gd",
    "jv_zh_tw/translations.json",
    "jv_zh_tw/guide_zhTW.pck",
    "jv_zh_tw/package-id.txt",
)
FORMAT = re.compile(r"%[-+0 #]*[0-9]*(?:\.[0-9]+)?[sdf]")


def validate() -> None:
    messages = json.loads((ROOT / "jv_zh_tw/translations.json").read_text(encoding="utf-8"))
    if not isinstance(messages, dict) or not messages:
        raise ValueError("translations.json must contain a nonempty object")
    for source, target in messages.items():
        if not isinstance(source, str) or not isinstance(target, str):
            raise ValueError("All translation keys and values must be strings")
        if FORMAT.findall(source) != FORMAT.findall(target):
            raise ValueError(f"Changed format placeholders: {source!r}")
    if not (ROOT / "Setup.ps1").read_bytes().startswith(b"\xef\xbb\xbf"):
        raise ValueError("Setup.ps1 must retain its UTF-8 BOM for PowerShell 5.1")
    for name in FILES:
        if not (ROOT / name).is_file():
            raise FileNotFoundError(name)


def build_release(version: str, output_dir: Path) -> Path:
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", version):
        raise ValueError("Version must contain letters, digits, dots, dashes, or underscores")
    write_pack()
    validate()
    output_dir.mkdir(parents=True, exist_ok=True)
    target = output_dir / f"JustVolleyball-zhTW-{version}.zip"
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name in sorted(FILES):
            entry = zipfile.ZipInfo(f"JustVolleyball-zhTW/{name}", date_time=(1980, 1, 1, 0, 0, 0))
            entry.create_system = 3
            entry.external_attr = 0o100644 << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, (ROOT / name).read_bytes(), compresslevel=9)
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    (output_dir / "SHA256SUMS.txt").write_text(f"{digest}  {target.name}\n", encoding="utf-8")
    return target


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default="v1.2.1")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "dist")
    args = parser.parse_args()
    target = build_release(args.version, args.output_dir)
    print(f"Wrote {target} ({target.stat().st_size} bytes)")
    print((args.output_dir / "SHA256SUMS.txt").read_text(encoding="utf-8").strip())


if __name__ == "__main__":
    main()

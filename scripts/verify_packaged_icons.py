"""Check desktop icon declarations and compiled assets in the device IPA.

Usage: python scripts/verify_packaged_icons.py <IPA> --project project.yml
On macOS, pass an assetutil --info JSON dump with --asset-info to verify the CAR entries.
"""
import argparse
import json
from pathlib import Path
import plistlib
import re
import zipfile

APP_ROOT = "Payload/SourceReadSwift.app/"


def expected_alternates(project: str) -> set[str]:
    """Read the configured XcodeGen alternate icon names."""
    entries = re.findall(r"^\s+ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES:\s*(AppIcon[a-zA-Z ]+)\s*$",
                         project, re.MULTILINE)
    if len(entries) != 1:
        raise ValueError("Expected one alternate icon setting in project.yml")
    return set(entries[0].split())


def verify_icon_manifest(plist: dict, project: str) -> list[str]:
    """Require all configured icons in both device manifests."""
    expected = expected_alternates(project)
    for key in ("CFBundleIcons", "CFBundleIcons~ipad"):
        icons = plist.get(key, {})
        if icons.get("CFBundlePrimaryIcon", {}).get("CFBundleIconName") != "AppIcon":
            raise ValueError(f"Missing AppIcon primary icon in {key}")
        alternates = icons.get("CFBundleAlternateIcons", {})
        if set(alternates) != expected:
            raise ValueError(f"Unexpected alternate icons in {key}: missing {sorted(expected - set(alternates))}, "
                             f"extra {sorted(set(alternates) - expected)}")
        for name, declaration in alternates.items():
            if declaration.get("CFBundleIconName") != name:
                raise ValueError(f"Incorrect asset name for {name} in {key}")
    return sorted(expected)


def verify_catalog_rows(rows: list, alternates: list[str]) -> None:
    """Require actual catalog records, not just Info.plist entries."""
    expected = {"AppIcon", *alternates}
    names = {row.get("Name") for row in rows if isinstance(row, dict)}
    missing = expected - names
    if missing:
        raise ValueError(f"Missing compiled Assets.car records: {sorted(missing)}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--project", required=True, type=Path)
    parser.add_argument("--asset-info", type=Path)
    args = parser.parse_args()
    with zipfile.ZipFile(args.ipa) as package:
        package.getinfo(APP_ROOT + "Assets.car")
        plist = plistlib.loads(package.read(APP_ROOT + "Info.plist"))
    alternates = verify_icon_manifest(plist, args.project.read_text(encoding="utf-8"))
    if args.asset_info is not None:
        verify_catalog_rows(json.loads(args.asset_info.read_text(encoding="utf-8")), alternates)
    print(json.dumps({"alternate_icons": alternates, "device_declarations": ["iPhone", "iPad"],
                      "verified_car_entries": args.asset_info is not None}, indent=2))


if __name__ == "__main__":
    main()

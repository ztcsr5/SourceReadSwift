"""Validate a downloaded unsigned IPA against its committed build configuration.

Used by deliver_reader_quality.py; requires the existing local lief package.
Checks package metadata, icons, fonts, arm64 and the matching dSYM UUID.
"""
import hashlib
import io
import plistlib
import re
import uuid
import zipfile
from pathlib import Path

import lief


def read_arm64_uuid(path: Path) -> str:
    """Return the UUID only for a single arm64 Mach-O binary."""
    parsed = lief.MachO.parse(str(path), lief.MachO.ParserConfig.quick)
    if parsed is None or len(parsed) != 1:
        raise ValueError("Expected a single-architecture device Mach-O")
    binary = parsed.at(0)
    if binary.header.cpu_type != lief.MachO.Header.CPU_TYPE.ARM64 or not binary.has_uuid:
        raise ValueError("Expected an arm64 device binary with a UUID")
    return str(uuid.UUID(bytes=bytes(binary.uuid.uuid)))


def version_from_project(project: str) -> dict:
    """Read the version from the verified commit rather than the mutable checkout."""
    version = re.findall(r'^\s+MARKETING_VERSION:\s*"([0-9.]+)"\s*$', project, re.M)
    build = re.findall(r'^\s+CURRENT_PROJECT_VERSION:\s*"([0-9]+)"\s*$', project, re.M)
    if len(version) != 1 or len(build) != 1:
        raise ValueError("Expected one unambiguous app version and build in committed project.yml")
    return {"CFBundleShortVersionString": version[0], "CFBundleVersion": build[0]}


def verify_device_ipa(ipa: bytes, symbols: bytes, project: str, folder: Path) -> dict:
    """Verify package contents and matching symbols before desktop publication."""
    expected = version_from_project(project) | {
        "CFBundleIdentifier": "com.edc21.SourceReadSwift", "MinimumOSVersion": "16.0",
        "DTPlatformName": "iphoneos", "CFBundleSupportedPlatforms": ["iPhoneOS"],
        "CADisableMinimumFrameDurationOnPhone": True}
    root = "Payload/SourceReadSwift.app/"
    with zipfile.ZipFile(io.BytesIO(ipa)) as package:
        if package.testzip() is not None:
            raise ValueError("Device IPA contains corrupt ZIP entries")
        names = package.namelist()
        if any(n.startswith(root + "_CodeSignature/") or n == root + "embedded.mobileprovision" for n in names):
            raise ValueError("Expected the explicitly unsigned package")
        plist = plistlib.loads(package.read(root + "Info.plist"))
        for key, value in expected.items():
            if plist.get(key) != value:
                raise ValueError(f"Device IPA metadata differs from committed project: {key}")
        if root + "Assets.car" not in names or not plist.get("CFBundleIcons"):
            raise ValueError("Device IPA is missing its compiled icon catalog")
        fonts = ("MaShanZheng-Regular.ttf", "ZhiMangXing-Regular.ttf", "ReadingDeskSong-Regular.ttf")
        for font in fonts:
            if font not in plist.get("UIAppFonts", []) or root + font not in names:
                raise ValueError("Device IPA is missing a declared bundled font")
        if hashlib.sha256(package.read(root + "ReadingDeskSong-Regular.ttf")).hexdigest() != "c99d12e49f7604017c83b0dd569b7966657fda9bab6660dda49fa1abca533264":
            raise ValueError("Bundled reading font differs from the verified asset")
        if root + "ReadingDeskSong-Regular-OFL.txt" not in names:
            raise ValueError("Device IPA is missing the bundled font license")
        executable = plist.get("CFBundleExecutable")
        if executable != "SourceReadSwift":
            raise ValueError("Unexpected device executable name")
        binary = folder / "SourceReadSwift-device"
        binary.write_bytes(package.read(root + executable))
    with zipfile.ZipFile(io.BytesIO(symbols)) as package:
        if package.testzip() is not None:
            raise ValueError("Device symbols contain corrupt ZIP entries")
        names = [n for n in package.namelist() if n.endswith("/Contents/Resources/DWARF/SourceReadSwift")]
        if len(names) != 1:
            raise ValueError("Expected exactly one matching app dSYM")
        dwarf = folder / "SourceReadSwift-device.dwarf"
        dwarf.write_bytes(package.read(names[0]))
    identity = read_arm64_uuid(binary)
    if identity != read_arm64_uuid(dwarf):
        raise ValueError("Device app and dSYM UUIDs do not match")
    return expected | {"uuid": identity, "architecture": "arm64", "icons_present": True}

"""Verify a packaged native build before signing or distributing it."""
import argparse
import hashlib
import plistlib
import subprocess
from pathlib import Path


def verify(bundle, configuration, revision, architecture, version, swift_bin_path, rust_bin_path):
    contents = Path(bundle) / "Contents"
    with (contents / "Info.plist").open("rb") as handle:
        metadata = plistlib.load(handle)
    expected = {"OpenRecorderBuildConfiguration": configuration,
                "OpenRecorderSourceRevision": revision,
                "CFBundleShortVersionString": version, "CFBundleVersion": version}
    for key, value in expected.items():
        if metadata.get(key) != value:
            raise ValueError(f"{key}: expected {value}, got {metadata.get(key)}")
    resources = contents / "Resources" / "OpenRecorderMac_OpenRecorderMac.bundle"
    if not resources.is_dir() or not any(resources.rglob("*.jpg")):
        raise ValueError("Missing packaged Swift wallpaper resources")
    def digest(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()
    for path in [Path(swift_bin_path), Path(rust_bin_path)]:
        if path.resolve().name != configuration:
            raise ValueError(f"Artifact directory is not {configuration}: {path}")
    source_resources = Path(swift_bin_path) / resources.name
    for path in source_resources.rglob("*"):
        if path.is_file() and digest(path) != digest(resources / path.relative_to(source_resources)):
            raise ValueError(f"Resource differs from selected build: {path}")
    if not source_resources.is_dir():
        raise ValueError("Missing resources in selected build directory")
    for executable, source_dir in [("OpenRecorderMac", swift_bin_path), ("open-recorder-service", rust_bin_path)]:
        binary = contents / "MacOS" / executable
        source = Path(source_dir) / executable
        # Packaging may add an rpath or replace a signature; the Mach-O UUID stays stable.
        def uuids(path):
            return [line.split()[1:3] for line in subprocess.check_output(
                ["dwarfdump", "--uuid", str(path)], text=True).splitlines()]
        if not uuids(source) or uuids(source) != uuids(binary):
            raise ValueError(f"{executable}: does not match selected build")
        architectures = subprocess.check_output(["lipo", "-archs", str(binary)], text=True).split()
        if set(architectures) != set(architecture.split(",")):
            raise ValueError(f"{executable}: unexpected architectures {architectures}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle")
    for name in ["configuration", "revision", "architecture", "version", "swift-bin-path", "rust-bin-path"]:
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args()
    verify(**vars(args))
    print(f"Verified {args.configuration} bundle at {args.revision}")

#!/usr/bin/env python3
"""Build a deterministic opkg feed from packages added to a Buildroot config.

The feed is intentionally derived from the same Buildroot output tree as the
system image.  A base show-info snapshot and base file list describe what the
sealed image already provides; only newly enabled target packages are emitted.
Dependencies that are already part of the base image are therefore omitted from
opkg metadata, while new target dependencies are emitted as separate ipks.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ARCH = "rx1950_armv4t_musl_v1"
ABI = {
    "epoch": 1,
    "architecture": ARCH,
    "cpu": "ARM920T",
    "isa": "ARMv4T",
    "abi": "EABI soft-float",
    "libc": "musl",
    "buildroot": "2025.02.2",
}


def die(message: str) -> None:
    raise SystemExit(f"error: {message}")


def load_info(path: Path) -> dict[str, dict]:
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if isinstance(data, list):
        result: dict[str, dict] = {}
        for item in data:
            if not isinstance(item, dict) or not item.get("name"):
                continue
            name = item["name"]
            if item.get("type") == "host" and not str(name).startswith("host-"):
                name = f"host-{name}"
            result[name] = item
        return result
    if not isinstance(data, dict):
        die(f"unexpected show-info JSON in {path}")
    return data


def read_base_files(path: Path) -> set[str]:
    result: set[str] = set()
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            value = line.strip()
            if value:
                result.add(normalize_path(value))
    return result


def normalize_path(value: str) -> str:
    value = value.strip()
    if value.startswith("./"):
        value = value[2:]
    value = value.lstrip("/")
    if not value or value == "." or ".." in Path(value).parts:
        die(f"unsafe package path: {value!r}")
    return value


def collect_file_owners(build_dir: Path) -> dict[str, set[str]]:
    owners: dict[str, set[str]] = {}
    for listing in sorted(build_dir.glob("*/.files-list.txt")):
        try:
            lines = listing.read_text(encoding="utf-8").splitlines()
        except UnicodeDecodeError:
            die(f"non-UTF-8 Buildroot file list: {listing}")
        for line in lines:
            if "," not in line:
                continue
            package, raw_path = line.split(",", 1)
            package = package.strip()
            if not package:
                continue
            owners.setdefault(package, set()).add(normalize_path(raw_path))
    return owners


def actual_target_packages(info: dict[str, dict]) -> set[str]:
    result: set[str] = set()
    for key, item in info.items():
        if not isinstance(item, dict):
            continue
        if item.get("type") != "target":
            continue
        if item.get("virtual"):
            continue
        if item.get("install_target") is False:
            continue
        result.add(key)
    return result


def provider_map(info: dict[str, dict]) -> dict[str, str]:
    providers: dict[str, str] = {}
    for key, item in info.items():
        if not isinstance(item, dict) or item.get("type") != "target":
            continue
        for provided in item.get("provides", []) or []:
            providers.setdefault(str(provided), key)
    return providers


def resolve_dependency(
    dep: str,
    info: dict[str, dict],
    providers: dict[str, str],
) -> str | None:
    item = info.get(dep)
    if item and item.get("type") == "host":
        return None
    if item and item.get("virtual"):
        return providers.get(dep)
    if dep in providers and (item is None or item.get("virtual")):
        return providers[dep]
    return dep


def safe_filename_component(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9.+~_-]+", "_", value)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def md5(path: Path) -> str:
    digest = hashlib.md5(usedforsecurity=False)
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run(command: list[str]) -> None:
    subprocess.run(command, check=True)


def make_tar(source: Path, output: Path, files: list[str], epoch: int) -> None:
    with tempfile.NamedTemporaryFile(prefix="rx1950-files-", delete=False) as handle:
        list_path = Path(handle.name)
        for item in files:
            handle.write(item.encode("utf-8") + b"\0")
    try:
        command = [
            "tar",
            "--directory",
            str(source),
            "--null",
            "--files-from",
            str(list_path),
            "--sort=name",
            f"--mtime=@{epoch}",
            "--owner=0",
            "--group=0",
            "--numeric-owner",
            "--format=gnu",
            "-cf",
            "-",
        ]
        with output.open("wb") as raw:
            tar_proc = subprocess.Popen(command, stdout=subprocess.PIPE)
            assert tar_proc.stdout is not None
            with gzip.GzipFile(filename="", mode="wb", fileobj=raw, compresslevel=9, mtime=0) as gz:
                shutil.copyfileobj(tar_proc.stdout, gz)
            tar_proc.stdout.close()
            if tar_proc.wait() != 0:
                die(f"tar failed while creating {output}")
    finally:
        list_path.unlink(missing_ok=True)


def package_size(target: Path, files: list[str]) -> int:
    total = 0
    for item in files:
        source = target / item
        try:
            if source.is_symlink():
                total += len(os.readlink(source))
            else:
                total += source.stat().st_size
        except FileNotFoundError:
            die(f"Buildroot claims {item} but it is missing from target/")
    return (total + 1023) // 1024


def build_ipk(
    package: str,
    item: dict,
    files: list[str],
    dependencies: list[str],
    target: Path,
    output_dir: Path,
    epoch: int,
) -> dict[str, object]:
    version = str(item.get("version") or "0")
    filename = (
        f"{safe_filename_component(package)}_"
        f"{safe_filename_component(version)}_{ARCH}.ipk"
    )
    output = output_dir / filename
    license_text = str(item.get("licenses") or "unknown").replace("\n", " ")
    description = f"Buildroot {package} package for rx1950-linux"

    with tempfile.TemporaryDirectory(prefix=f"rx1950-ipk-{package}-") as tmp_name:
        tmp = Path(tmp_name)
        control_dir = tmp / "control"
        control_dir.mkdir()
        control_lines = [
            f"Package: {package}",
            f"Version: {version}",
            f"Architecture: {ARCH}",
            f"Installed-Size: {package_size(target, files)}",
            "Maintainer: BlackF1re <55582873+BlackF1re@users.noreply.github.com>",
            f"License: {license_text}",
            f"Description: {description}",
        ]
        if dependencies:
            control_lines.insert(3, f"Depends: {', '.join(dependencies)}")
        control = control_dir / "control"
        control.write_text("\n".join(control_lines) + "\n", encoding="utf-8")
        control.chmod(0o644)

        (tmp / "debian-binary").write_text("2.0\n", encoding="ascii")
        (tmp / "debian-binary").chmod(0o644)
        make_tar(control_dir, tmp / "control.tar.gz", ["control"], epoch)
        make_tar(target, tmp / "data.tar.gz", files, epoch)
        run(
            [
                "ar",
                "crD",
                str(output),
                str(tmp / "debian-binary"),
                str(tmp / "control.tar.gz"),
                str(tmp / "data.tar.gz"),
            ]
        )

    return {
        "Package": package,
        "Version": version,
        "Architecture": ARCH,
        "Depends": ", ".join(dependencies),
        "Filename": filename,
        "Size": output.stat().st_size,
        "SHA256sum": sha256(output),
        "MD5Sum": md5(output),
        "Description": description,
        "License": license_text,
        "Files": files,
    }


def write_packages_index(records: list[dict[str, object]], output_dir: Path) -> None:
    fields = [
        "Package",
        "Version",
        "Architecture",
        "Depends",
        "Filename",
        "Size",
        "SHA256sum",
        "MD5Sum",
        "License",
        "Description",
    ]
    chunks: list[str] = []
    for record in sorted(records, key=lambda value: str(value["Package"])):
        lines = []
        for field in fields:
            value = record.get(field)
            if field == "Depends" and not value:
                continue
            lines.append(f"{field}: {value}")
        chunks.append("\n".join(lines) + "\n")
    content = "\n".join(chunks).encode("utf-8")
    packages = output_dir / "Packages"
    packages.write_bytes(content)
    with (output_dir / "Packages.gz").open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, compresslevel=9, mtime=0) as gz:
            gz.write(content)


def write_checksums(output_dir: Path) -> None:
    files = sorted(
        path
        for path in output_dir.iterdir()
        if path.is_file() and path.name != "PACKAGES-SHA256SUMS"
    )
    lines = [f"{sha256(path)}  {path.name}" for path in files]
    (output_dir / "PACKAGES-SHA256SUMS").write_text(
        "\n".join(lines) + "\n", encoding="utf-8"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-info", type=Path, required=True)
    parser.add_argument("--feed-info", type=Path, required=True)
    parser.add_argument("--base-files", type=Path, required=True)
    parser.add_argument("--build-dir", type=Path, required=True)
    parser.add_argument("--target", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    for command in ("ar", "tar"):
        if shutil.which(command) is None:
            die(f"required host tool is missing: {command}")

    base_info = load_info(args.base_info)
    feed_info = load_info(args.feed_info)
    base_files = read_base_files(args.base_files)
    file_owners = collect_file_owners(args.build_dir)
    providers = provider_map(feed_info)

    base_packages = set(base_info)
    candidates = actual_target_packages(feed_info) - base_packages
    packages_with_files = {
        package
        for package in candidates
        if file_owners.get(package)
    }
    if not packages_with_files:
        die("package fragment did not add any target files")

    path_owner: dict[str, str] = {}
    for package in sorted(packages_with_files):
        for path in sorted(file_owners[package]):
            if path in base_files:
                die(f"feed package {package} would overwrite base-image file /{path}")
            previous = path_owner.setdefault(path, package)
            if previous != package:
                die(f"feed packages {previous} and {package} both own /{path}")

    args.output.mkdir(parents=True, exist_ok=True)
    for old in args.output.iterdir():
        if old.is_file() or old.is_symlink():
            old.unlink()
        elif old.is_dir():
            shutil.rmtree(old)

    source_date_epoch = int(os.environ.get("SOURCE_DATE_EPOCH", "0") or "0")
    records: list[dict[str, object]] = []
    for package in sorted(packages_with_files):
        item = feed_info.get(package, {})
        dependencies: set[str] = set()
        for raw_dep in item.get("dependencies", []) or []:
            dep = resolve_dependency(str(raw_dep), feed_info, providers)
            if dep is None or dep in base_packages or dep == package:
                continue
            if dep in packages_with_files:
                dependencies.add(dep)
        files = sorted(file_owners[package])
        records.append(
            build_ipk(
                package,
                item,
                files,
                sorted(dependencies),
                args.target,
                args.output,
                source_date_epoch,
            )
        )

    write_packages_index(records, args.output)
    manifest = {
        "abi": ABI,
        "packages": [
            {
                key: value
                for key, value in record.items()
                if key in {"Package", "Version", "Filename", "SHA256sum", "Depends"}
            }
            for record in sorted(records, key=lambda value: str(value["Package"]))
        ],
    }
    (args.output / "feed.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    write_checksums(args.output)
    print(f"Built {len(records)} rx1950 opkg packages in {args.output}")


if __name__ == "__main__":
    main()

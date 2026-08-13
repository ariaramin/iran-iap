#!/usr/bin/env python3
"""Fail when an APK/AAB contains known billing traces for the wrong store.

This is a conservative release guard, not a formal proof of binary absence. It scans
all ZIP entries after decompression so signatures embedded in DEX, binary manifests,
resources, and metadata are visible to the byte-pattern matcher.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import sys
import zipfile

FORBIDDEN: dict[str, tuple[bytes, ...]] = {
    "bazaar": (
        b"ir.mservices.market",
        b"ir/mservices/market",
        b"ir.myket.billingclient",
        b"ir/myket/billingclient",
        b"dev.iraniap.myket",
        b"dev/iraniap/myket",
        b"myket-billing-client",
    ),
    # Myket Billing Client 1.19 itself contains Bazaar service identifiers.
    # Poolakey package/artifact markers are the reliable cross-SDK boundary.
    "myket": (
        b"ir.cafebazaar.poolakey",
        b"ir/cafebazaar/poolakey",
        b"dev.iraniap.bazaar",
        b"dev/iraniap/bazaar",
        b"PAY_THROUGH_BAZAAR",
    ),
}


def verify(store: str, artifact: Path) -> list[tuple[str, str]]:
    patterns = FORBIDDEN[store]
    findings: list[tuple[str, str]] = []

    if not artifact.is_file():
        raise FileNotFoundError(artifact)
    if not zipfile.is_zipfile(artifact):
        raise ValueError(f"Not an APK/AAB ZIP artifact: {artifact}")

    with zipfile.ZipFile(artifact) as archive:
        for info in archive.infolist():
            if info.is_dir():
                continue
            try:
                data = archive.read(info)
            except (RuntimeError, zipfile.BadZipFile) as error:
                raise ValueError(f"Could not read {info.filename}: {error}") from error
            lowered = data.lower()
            for pattern in patterns:
                if pattern.lower() in lowered:
                    findings.append((info.filename, pattern.decode("ascii")))
    return findings


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--store", required=True, choices=sorted(FORBIDDEN))
    parser.add_argument("artifact", type=Path)
    args = parser.parse_args()

    try:
        findings = verify(args.store, args.artifact)
    except (FileNotFoundError, ValueError, zipfile.BadZipFile) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2

    if findings:
        print(f"FAIL: {args.artifact} contains traces forbidden for {args.store}:")
        for entry, pattern in findings:
            print(f"  {entry}: {pattern}")
        return 1

    print(f"PASS: no known cross-store billing traces found for {args.store}: {args.artifact}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

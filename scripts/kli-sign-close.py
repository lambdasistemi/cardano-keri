#!/usr/bin/env python3
"""Sign a ckeri CloseMessage package inside a controller KLI environment."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import sys

from keri.app.cli.common import existing


SCHEMA = "cardano-keri/close-signing-package/v1"
PREIMAGE_FILE = "close-message.cbor"


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description=(
            "Sign ckeri's binary CloseMessage with the current KERI keys. "
            "Run this where the named KLI keystore lives."
        )
    )
    result.add_argument("--name", required=True, help="KLI keystore name")
    result.add_argument("--alias", required=True, help="KLI identifier alias")
    result.add_argument(
        "--base", default="", help="Optional KLI keystore base directory"
    )
    result.add_argument(
        "--package", required=True, type=Path, help="ckeri signing-package directory"
    )
    result.add_argument(
        "--out", required=True, type=Path, help="Output CESR signature file"
    )
    result.add_argument(
        "--validator-test-non-controller",
        action="store_true",
        help="ACCEPTANCE ONLY: permit a KLI AID different from the package AID",
    )
    return result


def fail(message: str) -> None:
    raise SystemExit(f"kli-sign-close: {message}")


def load_package(directory: Path) -> tuple[dict, bytes]:
    try:
        metadata = json.loads((directory / "package.json").read_text("utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        fail(f"cannot read package.json: {error}")
    if metadata.get("schema") != SCHEMA:
        fail("package schema is not cardano-keri/close-signing-package/v1")
    if metadata.get("preimageFile") != PREIMAGE_FILE:
        fail("package preimageFile is not close-message.cbor")
    try:
        preimage = (directory / PREIMAGE_FILE).read_bytes()
    except OSError as error:
        fail(f"cannot read binary preimage: {error}")
    digest = hashlib.sha256(preimage).hexdigest()
    if metadata.get("preimageSha256") != digest:
        fail("binary preimage SHA-256 does not match package.json")
    return metadata, preimage


def main() -> None:
    args = parser().parse_args()
    metadata, preimage = load_package(args.package)
    passcode = os.environ.get("KERI_PASSCODE")
    with existing.existingHab(
        name=args.name,
        alias=args.alias,
        base=args.base,
        bran=passcode,
    ) as (_, habitat):
        if habitat is None:
            fail(f"KLI alias {args.alias!r} does not exist")
        if habitat.pre != metadata.get("aid"):
            if not args.validator_test_non_controller:
                fail("KLI identifier does not match the signing package AID")
            print(
                "warning: ACCEPTANCE-ONLY signing CloseMessage with "
                f"non-controller AID {habitat.pre}",
                file=sys.stderr,
            )
        signatures = habitat.sign(
            ser=preimage,
            verfers=habitat.kever.verfers,
            indexed=True,
        )
    if not signatures:
        fail("KLI returned no current-key signatures")
    encoded = "".join(f"{signature.qb64}\n" for signature in signatures).encode(
        "ascii"
    )
    args.out.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.out.with_name(f".{args.out.name}.tmp")
    temporary.write_bytes(encoded)
    temporary.replace(args.out)
    print(f"controller signatures: {args.out}")
    print(f"signature count: {len(signatures)}")
    print(f"preimage sha256: {metadata['preimageSha256']}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)

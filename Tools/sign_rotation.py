#!/usr/bin/env python3
"""Sign the shared rotation file.

The rotation file is the one thing the server tells the app that changes what a
student sees, so the app refuses any copy that does not verify. This script
produces the signed envelope the app downloads.

    # once, and keep the private key somewhere safe and offline
    ./Tools/sign_rotation.py --generate-key

    # every time the rotation changes
    ./Tools/sign_rotation.py rotation.json --key rotation-key.pem --key-id 2026-rotation \
        --out signed-rotation.json

Then upload signed-rotation.json to the `public-rotation` storage bucket as
rotation.json, and put the printed public key in Config/Local.xcconfig as
ROTATION_PUBLIC_KEY.

Requires: pip install cryptography
"""

from __future__ import annotations

import argparse
import base64
import json
import sys
from pathlib import Path


def generate_key(path: Path) -> None:
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import ed25519

    if path.exists():
        sys.exit(f"{path} already exists. Refusing to overwrite a signing key.")

    private_key = ed25519.Ed25519PrivateKey.generate()
    path.write_bytes(
        private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        )
    )
    path.chmod(0o600)

    public_raw = private_key.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    print(f"Private key written to {path}. Keep it off this repository.")
    print()
    print("ROTATION_PUBLIC_KEY =", base64.b64encode(public_raw).decode())


def sign(payload_path: Path, key_path: Path, key_id: str, out_path: Path) -> None:
    from cryptography.hazmat.primitives import serialization

    # Parse to fail early on malformed JSON, but sign the bytes exactly as they
    # sit on disk: the app verifies the bytes it downloaded, not a re-encoding.
    raw = payload_path.read_bytes()
    document = json.loads(raw)
    for required in ("version", "schoolYear", "publishedAt", "days"):
        if required not in document:
            sys.exit(f"{payload_path} is missing the required field {required!r}.")

    private_key = serialization.load_pem_private_key(key_path.read_bytes(), password=None)
    signature = private_key.sign(raw)

    envelope = {
        "payload": base64.b64encode(raw).decode(),
        "signature": base64.b64encode(signature).decode(),
        "keyID": key_id,
    }
    out_path.write_text(json.dumps(envelope, indent=2) + "\n")
    print(f"Signed version {document['version']} into {out_path}.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("payload", nargs="?", type=Path, help="The unsigned rotation JSON.")
    parser.add_argument("--generate-key", action="store_true", help="Create a new signing key and print its public half.")
    parser.add_argument("--key", type=Path, default=Path("rotation-key.pem"))
    parser.add_argument("--key-id", default="rotation-1")
    parser.add_argument("--out", type=Path, default=Path("signed-rotation.json"))
    args = parser.parse_args()

    if args.generate_key:
        generate_key(args.key)
        return

    if args.payload is None:
        parser.error("Give the rotation JSON to sign, or pass --generate-key.")
    sign(args.payload, args.key, args.key_id, args.out)


if __name__ == "__main__":
    main()

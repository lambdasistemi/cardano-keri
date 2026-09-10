"""Keep the MkDocs reference derived from the offered-interface sources."""
from pathlib import Path
import shutil
import subprocess


def on_pre_build(config):
    root = Path(__file__).resolve().parent.parent
    command = ["node", str(root / "scripts/generate-offered-reference.mjs")]
    if not shutil.which("node"):
        command = [
            "nix", "shell",
            "github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#nodejs",
            "--command",
        ] + command
    subprocess.run(command, cwd=root, check=True)

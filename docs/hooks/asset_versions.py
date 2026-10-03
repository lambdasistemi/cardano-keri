"""Version the theme scripts and stylesheets by content, so a changed file evicts cached copies."""
import hashlib
from pathlib import Path


def on_config(config):
    docs = Path(config["docs_dir"])
    versions = {}
    for key in ("extra_css", "extra_javascript"):
        entries = []
        for entry in config[key]:
            path = docs / str(entry)
            if path.is_file() and "?" not in str(entry):
                digest = hashlib.sha256(path.read_bytes()).hexdigest()[:16]
                versions[str(entry)] = digest
                entry = f"{entry}?v={digest}"
            entries.append(entry)
        config[key] = entries
    palette = docs / "javascripts" / "palette.js"
    versions["javascripts/palette.js"] = hashlib.sha256(palette.read_bytes()).hexdigest()[:16]
    config["extra"]["asset_versions"] = versions
    return config

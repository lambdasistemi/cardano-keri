#!/usr/bin/env python3
"""Generate narration audio from the speech companions of the published pages.

The companions are the output of ``mkdocs-speech`` (dev-assets), never edited by
hand: they hold the sentences of each page as the reader sees them. The voice says
exactly those sentences. Each segment becomes one clip, grouped under the heading
that owns it. Nothing is summarised, paraphrased or curated; a pronunciation rule
may change how a written term sounds, never which words are spoken.

Reads docs/audio/narration-config.json and docs/audio/pronunciation.json, and
records every clip in docs/audio/manifest.json. A clip is regenerated only when
its segment, the pronunciation rules or the configuration changed. A companion
whose page changed after it was written is refused as stale. Generation needs
DEEPINFRA_API_KEY.

  python3 tools/narrate.py --list      # clips, characters, estimated cost
  python3 tools/narrate.py --generate  # generate what is missing or stale
  python3 tools/narrate.py --check     # exit 1 on a missing, stale or altered clip
"""

import argparse
import base64
import concurrent.futures
import hashlib
import json
import os
import re
import sys
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIO = os.path.join(ROOT, "docs", "audio")
PRICE_PER_CHARACTER = 0.62 / 1_000_000
PAUSE_MS = 400
WORKERS = 8


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def sha(data):
    return hashlib.sha256(
        data if isinstance(data, bytes) else data.encode()
    ).hexdigest()


def canonical(obj):
    return json.dumps(obj, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def companions():
    """Every page that has a speech companion, as docs-relative page paths."""
    found = []
    for base, _, files in os.walk(os.path.join(ROOT, "docs")):
        for name in files:
            if name.endswith(".speech.json"):
                found.append(os.path.relpath(os.path.join(base, name), ROOT)[: -len(".speech.json")] + ".md")
    return sorted(found)


def paragraphs(page):
    path = os.path.join(ROOT, page[:-3] + ".speech.json")
    speech = load(path)
    source = speech.get("_source", {})
    if source.get("sha256") != sha(open(os.path.join(ROOT, page), "rb").read()):
        sys.exit(f"stale companion (page changed after mkdocs-speech ran): {page}")
    for section, items in speech.items():
        if section.startswith("_"):
            continue
        for index, item in enumerate(items):
            yield section, index, item["text"], item.get("pause", PAUSE_MS)


def _override(phonemes):
    def replace(match):
        return f"[{match.group(0)}](/{phonemes}/)"

    return replace


def apply_rules(text, rules):
    for rule in sorted(rules, key=lambda r: -len(r["term"])):
        flags = re.IGNORECASE if rule.get("ignore_case") else 0
        pattern = r"(?<![A-Za-z0-9_])" + re.escape(rule["term"]) + r"(?![A-Za-z0-9_])"
        if "phonemes" in rule:
            replacement = _override(rule["phonemes"])
        else:
            replacement = rule["spoken"].replace("\\", "\\\\")
        text = re.sub(pattern, replacement, text, flags=flags)
    return text


def clip_name(page, section, index):
    return f"{page[:-3].replace('/', '-')}/{section}-{index:02d}"


def plan(config, rules):
    manifest_path = os.path.join(AUDIO, "manifest.json")
    manifest = load(manifest_path) if os.path.exists(manifest_path) else {"clips": {}}
    config_digest, rules_digest = sha(canonical(config)), sha(canonical(rules))
    items = []
    for page in companions():
        for section, index, text, pause in paragraphs(page):
            name = clip_name(page, section, index)
            key = sha(canonical([text, rules_digest, config_digest]))
            path = os.path.join(AUDIO, "clips", name + ".mp3")
            old = manifest["clips"].get(name)
            state = "missing"
            if old is not None and os.path.exists(path):
                if old["key"] != key:
                    state = "stale"
                elif sha(open(path, "rb").read()) != old["audio_sha256"]:
                    state = "altered"
                else:
                    state = "fresh"
            items.append(
                dict(
                    name=name,
                    page=page,
                    section=section,
                    index=index,
                    text=text,
                    sent=apply_rules(text, rules["rules"]),
                    pause=pause,
                    key=key,
                    state=state,
                )
            )
    names = {i["name"] for i in items}
    orphans = sorted(set(manifest["clips"]) - names)
    return manifest, items, orphans, config_digest, rules_digest


def request(config, text, api_key):
    body = {
        "text": text,
        "preset_voice": config["voice"]["preset_voice"],
        "output_format": config["output_format"],
        "speed": config["speed"],
        "service_tier": config["service_tier"],
        "return_timestamps": config["return_timestamps"],
    }
    req = urllib.request.Request(
        config["endpoint"],
        json.dumps(body).encode(),
        {"Authorization": "Bearer " + api_key, "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.load(r)


def build_index(manifest):
    """What the page player needs: per page and section, each clip's name, pause and text."""
    index = {}
    for name, clip in sorted(manifest["clips"].items()):
        section = index.setdefault(clip["page"], {}).setdefault(clip["section"], [])
        section.append(
            {
                "index": clip["index"],
                "name": name,
                "pause_ms": clip["pause_ms"],
                "v": clip["audio_sha256"][:12],
                "text": clip["text"],
            }
        )
    for sections in index.values():
        for clips in sections.values():
            clips.sort(key=lambda c: c["index"])
    return index


def index_text(manifest):
    return (
        json.dumps(build_index(manifest), ensure_ascii=False, indent=1, sort_keys=True)
        + "\n"
    )


def write_manifest(manifest, rules_digest, config_digest):
    manifest["pronunciation_sha256"], manifest["configuration_sha256"] = (
        rules_digest,
        config_digest,
    )
    with open(os.path.join(AUDIO, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1, sort_keys=True)
        f.write("\n")
    with open(os.path.join(AUDIO, "index.json"), "w", encoding="utf-8") as f:
        f.write(index_text(manifest))


def main():
    ap = argparse.ArgumentParser()
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--list", action="store_true")
    mode.add_argument("--generate", action="store_true")
    mode.add_argument("--check", action="store_true")
    ap.add_argument("--only", help="restrict to clips whose name contains this text")
    args = ap.parse_args()

    config = load(os.path.join(AUDIO, "narration-config.json"))
    rules = load(os.path.join(AUDIO, "pronunciation.json"))
    manifest, items, orphans, config_digest, rules_digest = plan(config, rules)
    if args.only:
        items = [i for i in items if args.only in i["name"]]
    todo = [i for i in items if i["state"] != "fresh"]
    chars = sum(len(i["sent"]) for i in todo)

    if args.list:
        for i in items:
            print(f"{i['state']:8} {len(i['sent']):6d}  {i['name']}")
        print(
            f"{len(todo)} of {len(items)} clips to generate, {chars} characters, "
            f"estimated ${chars * PRICE_PER_CHARACTER:.4f}; {len(orphans)} clips no longer on any page"
        )
        return 0
    if args.check:
        for i in todo:
            print(f"{i['state']}: {i['name']}")
        for name in orphans:
            print("orphan (no longer on any page):", name)
        index_path = os.path.join(AUDIO, "index.json")
        index_ok = os.path.exists(index_path) and open(
            index_path, encoding="utf-8"
        ).read() == index_text(manifest)
        if not index_ok:
            print("index.json does not match manifest.json")
        return 1 if todo or orphans or not index_ok else 0

    api_key = os.environ.get("DEEPINFRA_API_KEY")
    if not api_key:
        sys.exit("DEEPINFRA_API_KEY is not set")
    for name in orphans:
        manifest["clips"].pop(name)
        os.remove(os.path.join(AUDIO, "clips", name + ".mp3"))
    spent = 0.0
    failure = None
    with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        pending = {pool.submit(request, config, i["sent"], api_key): i for i in todo}
        # Save each clip as soon as its request returns, so a slow request never holds back the rest.
        for n, future in enumerate(concurrent.futures.as_completed(pending), 1):
            i = pending[future]
            if failure:
                future.cancel()
                continue
            try:
                r = future.result()
                if r["inference_status"]["status"] != "succeeded":
                    raise RuntimeError(f"inference status {r['inference_status']}")
            except (urllib.error.URLError, TimeoutError, RuntimeError) as e:
                failure = f"stopped at {i['name']}: {e}; a billable request is not retried automatically"
                continue
            audio = base64.b64decode(r["audio"].split(",", 1)[-1])
            path = os.path.join(AUDIO, "clips", i["name"] + ".mp3")
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(audio)
            words = [
                {
                    "text": w["text"],
                    "start": round(w["start"], 3),
                    "end": round(w["end"], 3),
                }
                for w in r.get("words") or []
            ]
            cost = r["inference_status"]["cost"]
            spent += cost
            manifest["clips"][i["name"]] = {
                "page": i["page"],
                "section": i["section"],
                "index": i["index"],
                "key": i["key"],
                "text": i["text"],
                "sent_text": i["sent"],
                "pause_ms": i["pause"],
                "audio_sha256": sha(audio),
                "characters": r["input_character_length"],
                "cost": cost,
                "duration": words[-1]["end"] if words else None,
                "words": words,
            }
            if n % 20 == 0:
                write_manifest(manifest, rules_digest, config_digest)
            print(
                f"[{n}/{len(todo)}] {i['name']}  {r['input_character_length']} chars  ${cost:.6f}",
                flush=True,
            )
    if failure:
        write_manifest(manifest, rules_digest, config_digest)
        sys.exit(failure)
    write_manifest(manifest, rules_digest, config_digest)
    print(f"generated {len(todo)} clips, ${spent:.4f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""
WHAT: Publish an on-device voice pack (Kokoro's front end and a Core ML acoustic half) to Rao
      Studios' Hugging Face org, so Adverb's onboarding fetches bytes Rao checked, from a repository
      Rao controls, at one commit.
IN:   --pack <folder> (the pack as Adverb loads it), --target rao-studios/<name>, --kind paradee|kokoro,
      --work <empty folder>.
OUT:  The folder copied with a README card (lineage, license, the voices, a SHA-256 per file) and the
      Apache License 2.0 text; then, unless --dry-run, the repository created (public) and uploaded.
      The commit is printed: AdverbCore's ModelCatalog pins it.
PIN:  THE PASS READS, IT NEVER RUNS. Only Core ML compiled models (*.mlmodelc trees), JSON and the
      license are allowed; any pickle (.pt, .pth, .pkl, .ckpt), native code (.so, .dylib) or script
      refuses the whole pack. A pack must load: the front end (vocab_index.json, us_gold.json) and one
      acoustic half (ParadeeText + ParadeeAcoustic, or kokoro_24_*.mlmodelc with voices/*.json).

  python3 -I Scripts/release/mirror-voice-pack.py --dry-run --kind paradee \\
      --pack ~/packs/kokoro-paradee-8m-coreml --target rao-studios/kokoro-paradee-8m-coreml --work /tmp/pack-paradee
"""
import argparse, datetime, hashlib, json, pathlib, shutil, sys

from huggingface_hub import HfApi

REFUSED = (".pt", ".pth", ".pkl", ".pickle", ".ckpt", ".so", ".dylib", ".py", ".sh", ".exe", ".h5", ".msgpack")

CARDS = {
    "paradee": {
        "title": "Heart (Kokoro, distilled to 8M parameters)",
        "base": "MithrilMan/teacher-in-the-loop",
        "lineage": [
            "[hexgrad/Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) v1.0, by hexgrad (Apache-2.0): the teacher, and its "
            "`af_heart` voice.",
            "[MithrilMan/teacher-in-the-loop](https://huggingface.co/MithrilMan/teacher-in-the-loop) at "
            "`115a6c0469632a84fbcc6c8ed0ad7b1e06154b92`: an 8M-parameter Paradee-family student of Kokoro's `af_heart`, "
            "distilled teacher-in-the-loop (Apache-2.0, `LICENSE-teacher-in-the-loop`).",
            "Converted to Core ML (float32 ML programs, `ParadeeText` and `ParadeeAcoustic`, run on the CPU) by Rao Studios' "
            "Ambient on 2026-10-31, over FluidInference's mobius Paradee v1.0 graph with its phase-lock filter removed, "
            "and checked against the PyTorch model for parity before shipping.",
            "The front end (`vocab_index.json`, the misaki-style `us_`/`gb_` gold and silver lexicons, the 178k-word G2P "
            "cache and the `G2PEncoder`/`G2PDecoder` BART model) from "
            "[FluidInference/kokoro-82m-coreml](https://huggingface.co/FluidInference/kokoro-82m-coreml) (Apache-2.0).",
        ],
        "what": "One English voice, `af_heart`, at 24 kHz. Any line length (no fixed windows); the model reports how many "
                "25 ms frames each phoneme takes, so every word's time is exact; and it can speak faster on request.",
    },
    "kokoro": {
        "title": "Kokoro 82M, eight English voices",
        "base": "hexgrad/Kokoro-82M",
        "lineage": [
            "[hexgrad/Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) v1.0, by hexgrad (Apache-2.0), and eight of its "
            "voices' style vectors (`voices/*.json`: 256 floats per phoneme count, and their mean).",
            "Core ML windows `kokoro_24_10s` and `kokoro_24_15s` (24 kHz; 242 and 363 phoneme tokens) from "
            "[FluidInference/kokoro-82m-coreml](https://huggingface.co/FluidInference/kokoro-82m-coreml) (Apache-2.0), "
            "compiled, as Rao Studios' Mary ships them.",
            "The same front end as the distilled voice: `vocab_index.json`, the misaki-style lexicons, the G2P cache and "
            "the `G2PEncoder`/`G2PDecoder` BART model, from FluidInference/kokoro-82m-coreml (Apache-2.0).",
        ],
        "what": "Eight voices: American (`af_heart`, `af_alloy`, `af_nova`, `af_river`, `am_adam`, `am_echo`), British "
                "(`bf_alice`) and Hindi-accented English (`hm_omega`), at 24 kHz. Each window reports the frames each "
                "phoneme takes, so every word's time is exact. Built to take more languages: another language's lexicon "
                "and voices are added beside these.",
    },
}


class Refused(Exception):
    pass


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def check(pack: pathlib.Path, kind: str) -> dict:
    files = {}
    for path in sorted(p for p in pack.rglob("*") if p.is_file()):
        rel = path.relative_to(pack).as_posix()
        if path.name in (".DS_Store",) or path.name.startswith("._"):
            continue
        if path.suffix.lower() in REFUSED:
            raise Refused(f"{rel}: a pickle, native code or a script — never published")
        inside_model = any(part.endswith(".mlmodelc") for part in path.relative_to(pack).parts[:-1])
        if not (inside_model or path.suffix == ".json" or path.name.startswith("LICENSE")):
            raise Refused(f"{rel}: not a file a voice pack needs")
        if path.suffix == ".json":
            json.loads(path.read_text())
        files[rel] = {"sha256": sha256(path), "size": path.stat().st_size}
    for required in ("vocab_index.json", "us_gold.json", "G2PEncoder.mlmodelc/coremldata.bin"):
        if required not in files:
            raise Refused(f"missing {required}: the front end will not load")
    if kind == "paradee":
        for required in ("ParadeeText.mlmodelc/coremldata.bin", "ParadeeAcoustic.mlmodelc/coremldata.bin", "paradee.json"):
            if required not in files:
                raise Refused(f"missing {required}")
        voices = json.loads((pack / "paradee.json").read_text()).get("voices", [])
    else:
        if not any(n.startswith("kokoro_24_") for n in files):
            raise Refused("no kokoro_24_*.mlmodelc window")
        voices = sorted(n[len("voices/"):-5] for n in files if n.startswith("voices/") and n.endswith(".json"))
        if not voices:
            raise Refused("no voices/*.json")
    return {"files": files, "voices": voices}


def card(target: str, kind: str, report: dict) -> str:
    c = CARDS[kind]
    rows = "\n".join(f"| `{n}` | {f['size']:,} | `{f['sha256']}` |" for n, f in sorted(report["files"].items()))
    lineage = "\n".join(f"- {line}" for line in c["lineage"])
    voices = ", ".join(f"`{v}`" for v in report["voices"])
    total = sum(f["size"] for f in report["files"].values()) / 1_000_000
    return f"""---
license: apache-2.0
base_model: {c['base']}
pipeline_tag: text-to-speech
library_name: coreml
language:
- en
tags:
- kokoro
- coreml
- text-to-speech
- on-device
---

# {target}

{c['title']}: an on-device voice pack for [Adverb](https://rao.nyc), Rao Studios' Mac app for a month of
motion assets. Adverb speaks every voice-over on the Mac with it; nothing is sent anywhere.

{c['what']}

Voices: {voices}. {total:.0f} MB.

## Lineage

{lineage}

Nothing was re-trained or edited for this pack; the files are those projects' (compiled for Core ML where
named). This card and `LICENSE` (the Apache License 2.0) were added.

## How Adverb runs it

Adverb's `AdverbVoice` target (Ambient's Kokoro engine, lifted): text normalized and phonemized in Swift
(the lexicons, then the G2P model for unknown words; no espeak), phoneme ids through the Core ML model,
pieces joined at their natural pauses, one gain for the voice. Each word's start and end come from the
model's own per-phoneme durations, and the on-screen text of a narrated video arrives on its first word.

## Contents

Published by Adverb's `Scripts/release/mirror-voice-pack.py` on {datetime.date.today().isoformat()}: only Core ML
compiled models, JSON and the license; no pickle, native code or script; every JSON file parsed.

| File | Bytes | SHA-256 |
|---|---:|---|
{rows}
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--pack", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--kind", required=True, choices=sorted(CARDS))
    parser.add_argument("--license", required=True, help="the Apache License 2.0 text to ship as LICENSE")
    parser.add_argument("--work", required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if not args.target.startswith("rao-studios/"):
        print("error: --target must be in rao-studios", file=sys.stderr)
        return 2
    pack = pathlib.Path(args.pack).expanduser().resolve()
    try:
        report = check(pack, args.kind)
    except Refused as refusal:
        print(f"REFUSED: {refusal}", file=sys.stderr)
        return 1
    out = pathlib.Path(args.work) / "pack"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    for name in report["files"]:
        destination = out / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(pack / name, destination)
    license_text = pathlib.Path(args.license).read_text()
    if "Apache License" not in license_text or "Version 2.0" not in license_text:
        print("REFUSED: --license is not the Apache License 2.0", file=sys.stderr)
        return 1
    (out / "LICENSE").write_text(license_text)
    report["files"]["LICENSE"] = {"sha256": sha256(out / "LICENSE"), "size": (out / "LICENSE").stat().st_size}
    (out / "README.md").write_text(card(args.target, args.kind, report))
    print(f"▸ passed: {len(report['files'])} files, voices {', '.join(report['voices'])}, "
          f"{sum(f['size'] for f in report['files'].values()):,} bytes")
    if args.dry_run:
        print(f"Dry run: {out} is ready; nothing uploaded.")
        return 0
    api = HfApi()
    print(f"▸ upload: {args.target}")
    api.create_repo(args.target, repo_type="model", private=False, exist_ok=True)
    commit = api.upload_folder(repo_id=args.target, repo_type="model", folder_path=str(out),
                               commit_message="Publish the voice pack, after Adverb's pass")
    sha = api.model_info(args.target).sha
    print(f"Published: https://huggingface.co/{args.target} at {sha}")
    print(f"           {commit.commit_url}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

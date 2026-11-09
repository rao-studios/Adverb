#!/usr/bin/env python3
"""
WHAT: Mirror an MLX model into Rao Studios' Hugging Face org after a safety pass, so every install
      fetches bytes Rao checked, from a repository Rao controls, at one commit: Adverb's writer (plans,
      pages, voice-overs; it reads the stills too when it is a vision model) or its eyes.
      Lifted from Craft (Scripts/release/mirror-model.py): a vision model's processor files are
      allowed, any type Frigate's LLM or VLM factory loads passes, and the card names Adverb's role.
IN:   --source <org/name>@<commit> (the MLX conversion), --base <org/name> (the model it was
      converted from, for its license and the card's lineage), --target rao-studios/<name>, --role
      (writer or eyes), and Frigate's checkout for the model types it can load (default:
      .build/checkouts/Frigate). --seed <folder> starts the download from a copy already on this Mac
      (the Hub's metadata beside it says which commit it is; every file is still checked).
OUT:  A folder ready to upload — the allowed files byte for byte, the base model's LICENSE, a
      README card with the lineage, the shape, the tool format, the safety pass and a SHA-256 per
      file — then, unless --dry-run, the repository created (public) and the folder uploaded. The
      mirror's commit is printed: AdverbCore's ModelCatalog pins it.
PIN:  THE PASS READS, IT NEVER RUNS. Nothing downloaded is imported, unpickled or executed: weights
      are safetensors, whose header is plain JSON read here by hand; any pickle format (.bin, .pt,
      .pth, .pkl, .ckpt) or native code (.so, .dylib) in the source refuses the whole mirror;
      Python files (a tool parser some conversions ship) are dropped and named in the card;
      `auto_map` (remote code) in a config refuses it. Every LFS file is checked against the
      SHA-256 the Hub recorded for it. Run it with `python3 -I`, outside the download folder.
PIN:  NOTHING IS RE-QUANTIZED OR EDITED. The weights, tokenizer, template and config are the
      source's bytes; only the README and LICENSE are Rao's. A base that ships no LICENSE file but
      declares apache-2.0 in its card gets the Apache License 2.0 text from apache.org, and the card
      says so; any other license without a file refuses the mirror.

  python3 -I Scripts/release/mirror-model.py --dry-run \\
      --source mlx-community/Qwen3.8-27B-4bit@10c35caafbb80f7dc6a7a432cdd11af10a6d4818 \\
      --base Qwen/Qwen3.8-27B --target rao-studios/Qwen3.8-27B-mlx-4bit --role writer --work /tmp/mirror-qwen38
"""
import argparse, datetime, hashlib, json, os, pathlib, re, shutil, struct, subprocess, sys, urllib.request

from huggingface_hub import HfApi, hf_hub_download

ALLOWED = re.compile(r"^(model(-\d{5}-of-\d{5})?\.safetensors|model\.safetensors\.index\.json|config\.json|"
                     r"generation_config\.json|tokenizer\.json|tokenizer_config\.json|special_tokens_map\.json|"
                     r"added_tokens\.json|vocab\.json|merges\.txt|chat_template\.jinja|\.gitattributes|README\.md|"
                     r"chat_template\.json|preprocessor_config\.json|processor_config\.json|video_preprocessor_config\.json)$")
REFUSED = (".bin", ".pt", ".pth", ".pkl", ".pickle", ".ckpt", ".h5", ".msgpack", ".so", ".dylib", ".sh", ".exe")
DROPPED = (".py",)
# Metadata other hubs write beside the model (ModelScope's), which no loader reads: left out, named in the card.
DROPPED_NAMES = {"configuration.json"}
DTYPES = {"BOOL", "U8", "I8", "U16", "I16", "F16", "BF16", "U32", "I32", "F32", "U64", "I64", "F64"}

TOOL_FORMATS = {
    "xml_function": ("Qwen3-Coder XML", "the chat template lists every tool as XML, and the model answers with a "
                     "`<tool_call>` block whose parameters are plain text between tags",
                     "<tool_call>\n<function=edit_file>\n<parameter=path>\nSources/App/main.swift\n</parameter>\n"
                     "<parameter=old_string>\nprint(\"hi\")\n</parameter>\n<parameter=new_string>\nprint(\"hello\")\n"
                     "</parameter>\n</function>\n</tool_call>"),
    "json": ("Hermes JSON", "the chat template lists every tool's JSON schema inside `<tools>`, and the model answers "
             "with one JSON object per call inside `<tool_call>` tags",
             "<tool_call>\n{\"name\": \"edit_file\", \"arguments\": {\"path\": \"Sources/App/main.swift\", "
             "\"old_string\": \"print(\\\"hi\\\")\", \"new_string\": \"print(\\\"hello\\\")\"}}\n</tool_call>"),
}


# What a model is for in Adverb: its card's section, and the line the card runs it with.
ROLES = {
    "writer": ("Adverb's writer",
               "Adverb plans a month of social posts with it, writes each day's motion page (HTML, CSS and a "
               "deterministic timeline), its captions, its voice-over script and the translations, all on the Mac. "
               "When the model reads images, it also looks at each page's contact sheet and says what to fix",
               "Write a two-line headline for a Mac app that reads along with you."),
    "eyes": ("Adverb's eyes",
             "Adverb shows it the contact sheet of each page its writer made (both orientations, four frames each) and "
             "it says what to fix: overlaps, overflow, an empty half, text too small to read",
             "Describe what is wrong with the layout in this image."),
}

# Who published a base model, by its Hub org: the card's lineage line.
PUBLISHERS = {"Qwen": "the Qwen team", "ibm-granite": "IBM", "mistralai": "Mistral AI", "nvidia": "NVIDIA",
              "voyageai": "Voyage AI", "google": "Google"}

APACHE_LICENSE_URL = "https://www.apache.org/licenses/LICENSE-2.0.txt"


class Refused(Exception):
    pass


def frigate_model_types(frigate: pathlib.Path) -> set:
    types = set()
    for factory in ("Sources/MLXLLM/LLMModelFactory.swift", "Sources/MLXVLM/VLMModelFactory.swift"):
        types |= set(re.findall(r'"([a-z0-9_]+)":\s*create\(', (frigate / factory).read_text()))
    return types


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safetensors_header(path: pathlib.Path) -> dict:
    """The header, read by hand: an 8-byte little-endian length, then that much JSON."""
    size = path.stat().st_size
    with path.open("rb") as handle:
        (length,) = struct.unpack("<Q", handle.read(8))
        if length <= 0 or 8 + length > size or length > 100 * 1024 * 1024:
            raise Refused(f"{path.name}: header length {length} does not fit a {size}-byte file")
        header = json.loads(handle.read(length))
    data = size - 8 - length
    spans = []
    for name, entry in header.items():
        if name == "__metadata__":
            continue
        if entry.get("dtype") not in DTYPES:
            raise Refused(f"{path.name}: {name} has dtype {entry.get('dtype')}")
        start, end = entry["data_offsets"]
        if not (0 <= start <= end <= data):
            raise Refused(f"{path.name}: {name} reaches past the file")
        spans.append((start, end))
    spans.sort()
    covered = 0
    for start, end in spans:
        if start != covered:
            raise Refused(f"{path.name}: tensors overlap or leave a gap at byte {covered}")
        covered = end
    if covered != data:
        raise Refused(f"{path.name}: {data - covered} bytes after the last tensor")
    return header


def safety_pass(api: HfApi, repo: str, revision: str, work: pathlib.Path, allowed_types: set, seed: pathlib.Path = None) -> dict:
    info = api.model_info(repo, revision=revision, files_metadata=True)
    if info.sha != revision:
        raise Refused(f"{repo}@{revision} resolved to {info.sha}")
    files, dropped = [], []
    for sibling in info.siblings:
        name = sibling.rfilename
        if name.lower().endswith(REFUSED):
            raise Refused(f"{name}: a pickle or native code — never mirrored")
        if name.endswith(DROPPED) or name in DROPPED_NAMES:
            dropped.append(name)
            continue
        if not ALLOWED.match(name):
            raise Refused(f"{name}: not a file an MLX model needs")
        files.append(sibling)
    source = work / "source"
    work.mkdir(parents=True, exist_ok=True)
    if seed and not source.exists():
        # A clone of the copy on this Mac (APFS: no bytes copied): the Hub client finds its metadata
        # and fetches only what is not there; every file is checked against the Hub below either way.
        subprocess.run(["cp", "-c", "-R", str(seed), str(source)], check=True)
    source.mkdir(parents=True, exist_ok=True)
    report = {"repo": repo, "revision": revision, "dropped": dropped, "files": {}}
    for sibling in files:
        name = sibling.rfilename
        local = pathlib.Path(hf_hub_download(repo, name, revision=revision, local_dir=source))
        digest = sha256(local)
        if sibling.lfs is not None and sibling.lfs.sha256 != digest:
            raise Refused(f"{name}: SHA-256 {digest} is not the Hub's {sibling.lfs.sha256}")
        report["files"][name] = {"sha256": digest, "size": local.stat().st_size}
        print(f"  ✓ {name} ({local.stat().st_size:,} bytes)")

    config = json.loads((source / "config.json").read_text())
    if "auto_map" in config:
        raise Refused("config.json names auto_map: remote code")
    model_type = config.get("model_type")
    if config.get("max_position_embeddings") is None and isinstance(config.get("text_config"), dict):
        config["num_hidden_layers"] = config["text_config"].get("num_hidden_layers")
        config["max_position_embeddings"] = config["text_config"].get("max_position_embeddings")
    if model_type not in allowed_types:
        raise Refused(f"model_type {model_type!r} is not one Frigate loads")
    quantization = config.get("quantization") or config.get("quantization_config")
    if not quantization or "bits" not in quantization:
        raise Refused("config.json has no quantization block: not an MLX conversion")
    tokenizer_config = json.loads((source / "tokenizer_config.json").read_text())
    if "auto_map" in tokenizer_config:
        raise Refused("tokenizer_config.json names auto_map: remote code")
    json.loads((source / "tokenizer.json").read_text())
    template = (source / "chat_template.jinja").read_text() if (source / "chat_template.jinja").exists() \
        else tokenizer_config.get("chat_template")
    if not isinstance(template, str) or not template:
        raise Refused("no chat template")

    names = set()
    shards = sorted(n for n in report["files"] if n.endswith(".safetensors"))
    if not shards:
        raise Refused("no safetensors weights")
    for shard in shards:
        names |= {k for k in safetensors_header(source / shard) if k != "__metadata__"}
    index_path = source / "model.safetensors.index.json"
    if index_path.exists():
        weight_map = json.loads(index_path.read_text())["weight_map"]
        if set(weight_map) != names:
            raise Refused(f"the index and the shards disagree on {len(set(weight_map) ^ names)} tensors")
        if set(weight_map.values()) - set(shards):
            raise Refused("the index names a shard that is not there")

    report.update({
        "model_type": model_type, "bits": quantization.get("bits"), "group_size": quantization.get("group_size"),
        "tensors": len(names), "weights_bytes": sum(report["files"][s]["size"] for s in shards),
        "context": config.get("max_position_embeddings"), "layers": config.get("num_hidden_layers"),
        "template_has_tools": "tools" in template,
        "vision": "vision_config" in config,
    })
    return report


def card(target: str, source: str, revision: str, base: str, base_license_commit: str, report: dict,
         tool_format: str = None, role: str = None, license_note: str = None) -> str:
    publisher = PUBLISHERS.get(base.split("/")[0], base.split("/")[0])
    if role:
        role_name, role_how, prompt = ROLES[role]
        purpose = role_how
        shape_row = f"| Role | {role_name} |"
        example = ""
        tag = "adverb"
        why = ("It exists so every install of Adverb fetches the same bytes from a repository Rao controls: Adverb's "
               "onboarding offers it by this Mac's memory, and pins this repository at one commit.")
    else:
        name, how, call = TOOL_FORMATS[tool_format]
        purpose = None
        shape_row = f"| Tools | {name}: {how} |"
        example = f"\nA call, as the model writes it:\n\n```\n{call}\n```\n"
        tag = "code"
        prompt = "Write a binary search in Swift."
        why = ("It exists so every install of Craft fetches the same bytes from a repository Rao controls: Craft's "
               "onboarding recommends it by this Mac's memory, and pins this repository at one commit.")
    license_line = license_note or (f"`LICENSE` (the Apache License 2.0, verbatim from\n"
                                    f"[{base}](https://huggingface.co/{base}) at `{base_license_commit}`)")
    purpose_section = f"\n## What it is for\n\n{purpose}.\n" if purpose else ""
    rows = "\n".join(f"| `{n}` | {f['size']:,} | `{f['sha256']}` |" for n, f in sorted(report["files"].items())
                     if n not in ("README.md", ".gitattributes"))
    dropped = "".join(f"\n- `{n}` was dropped: " + ("Python is never mirrored." if n.endswith(".py") else "another hub's metadata, which no loader reads.")
                      for n in report["dropped"])
    gb = report["weights_bytes"] / 1_000_000_000
    return f"""---
license: apache-2.0
base_model: {source}
pipeline_tag: {"image-text-to-text" if report.get("vision") else "text-generation"}
library_name: mlx
tags:
- mlx
- {report['model_type']}
- {tag}
- mirror
---

# {target}

Rao Studios' mirror of [{source}](https://huggingface.co/{source}) at commit `{revision}`. The weights,
tokenizer, chat template and configuration are byte-for-byte that repository's; nothing was
re-quantized or edited. This card and {license_line} were added.

{why}
{purpose_section}
## Lineage

- [{base}](https://huggingface.co/{base}), by {publisher} (Apache-2.0).
- [{source}](https://huggingface.co/{source}): that model converted to MLX at {report['bits']} bits — the files here.

## Shape (from `config.json`)

| | |
|---|---|
| Architecture | `{report['model_type']}`, {report['layers']} layers |
| Quantization | {report['bits']}-bit, group size {report['group_size']} |
| Weights | {gb:.1f} GB of safetensors, {report['tensors']:,} tensors |
| Context | {report['context']:,} tokens |
{shape_row}
{example}
## Safety pass

Run by Adverb's `Scripts/release/mirror-model.py` (Craft's, lifted) on {datetime.date.today().isoformat()}, before upload:

- Every file is one an MLX model needs; no pickle format and no native code was in the source.
- Every weight file is safetensors, its header read by hand: known dtypes, tensors that tile the
  file exactly, the same tensor names as the index.
- Every file matches the SHA-256 the Hub recorded for it at `{revision}`.
- No `auto_map` (remote code) in the config or the tokenizer config; a chat template is present.{dropped}

| File | Bytes | SHA-256 |
|---|---:|---|
{rows}

## Use with mlx

```bash
pip install mlx-lm
mlx_lm.generate --model {target} --prompt "{prompt}"
```
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", required=True, help="org/name@commit of the MLX conversion")
    parser.add_argument("--base", required=True, help="org/name of the model it was converted from")
    parser.add_argument("--target", required=True, help="rao-studios/<name>")
    parser.add_argument("--role", choices=sorted(ROLES), required=True, help="what the model is for in Adverb")
    parser.add_argument("--seed", help="a copy of the source already on this Mac, to start from")
    parser.add_argument("--work", required=True, help="an empty folder of its own for the download")
    parser.add_argument("--frigate", default=str(pathlib.Path(__file__).resolve().parents[2] / ".build/checkouts/Frigate"))
    parser.add_argument("--dry-run", action="store_true", help="the pass and the card, no upload")
    args = parser.parse_args()

    repo, _, revision = args.source.partition("@")
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        print("error: --source must name a full 40-character commit", file=sys.stderr)
        return 2
    if not args.target.startswith("rao-studios/"):
        print("error: --target must be in rao-studios", file=sys.stderr)
        return 2
    work = pathlib.Path(args.work)
    api = HfApi()
    print(f"▸ safety pass: {repo}@{revision[:12]}")
    try:
        report = safety_pass(api, repo, revision, work, frigate_model_types(pathlib.Path(args.frigate)),
                             seed=pathlib.Path(args.seed).expanduser() if args.seed else None)
    except Refused as refusal:
        print(f"REFUSED: {refusal}", file=sys.stderr)
        return 1

    out = work / "mirror"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    for name in report["files"]:
        if name in ("README.md",):
            continue
        destination = out / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        # A clone on APFS (no bytes copied; the weights are tens of gigabytes), else a copy.
        if subprocess.run(["cp", "-c", str(work / "source" / name), str(destination)], capture_output=True).returncode != 0:
            shutil.copyfile(work / "source" / name, destination)
    base_info = api.model_info(args.base)
    license_note = None
    if any(s.rfilename == "LICENSE" for s in base_info.siblings):
        license_path = hf_hub_download(args.base, "LICENSE", revision=base_info.sha, local_dir=work / "base")
        shutil.copyfile(license_path, out / "LICENSE")
    else:
        declared = (base_info.card_data or {}).get("license") if base_info.card_data else None
        if declared != "apache-2.0":
            print(f"REFUSED: {args.base} ships no LICENSE file and declares {declared!r}", file=sys.stderr)
            return 1
        with urllib.request.urlopen(APACHE_LICENSE_URL, timeout=30) as response:
            (out / "LICENSE").write_bytes(response.read())
        license_note = (f"`LICENSE` (the Apache License 2.0 text from {APACHE_LICENSE_URL}: "
                        f"[{args.base}](https://huggingface.co/{args.base}) declares `license: apache-2.0` in its "
                        f"card at `{base_info.sha}` and ships no LICENSE file)")
    (out / "README.md").write_text(card(args.target, repo, revision, args.base, base_info.sha, report,
                                        role=args.role, license_note=license_note))
    (work / "report.json").write_text(json.dumps(report, indent=2))
    print(f"▸ passed: {report['model_type']}, {report['bits']}-bit, {report['weights_bytes']:,} bytes of weights, "
          f"tools in template: {report['template_has_tools']}, dropped: {report['dropped'] or 'nothing'}")
    print(f"  download bytes (the mirror tree): {sum(f.stat().st_size for f in out.rglob('*') if f.is_file()):,}")

    if args.dry_run:
        print(f"Dry run: {out} is ready; nothing uploaded.")
        return 0
    print(f"▸ upload: {args.target}")
    api.create_repo(args.target, repo_type="model", private=False, exist_ok=True)
    commit = api.upload_folder(repo_id=args.target, repo_type="model", folder_path=str(out),
                               commit_message=f"Mirror {repo}@{revision[:12]}, after Adverb's safety pass")
    sha = api.model_info(args.target).sha
    print(f"Mirrored: https://huggingface.co/{args.target} at {sha}")
    print(f"          {commit.commit_url}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

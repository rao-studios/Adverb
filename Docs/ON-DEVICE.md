# Adverb on this Mac

Adverb plans, writes, looks and speaks with models on the Mac it runs on. No step calls a remote
API; the only network use is downloading a model, once, at a pinned commit, from
[huggingface.co/rao-studios](https://huggingface.co/rao-studios). This page is for whoever works on
that machinery: how it is put together, which models it pins, how a model is published, and how
models are compared against the reference sheets.

## How it is put together

| Target | Names | Holds |
| --- | --- | --- |
| `AdverbCore` | Foundation | The seams: `LanguageModel` (a request of turns, text and images, in a named `AnswerFormat`, to an answer) and `SpeechProvider` / `SpeechSynthesizer` (a line to samples and word times). `ModelCatalog` (every model, pinned), `ModelHome`, `AnswerParser`, the prompts and schemas. |
| `AdverbModels` | Frigate (MLX, mlx-swift-lm) | `MLXLanguageModel` (chat template, prefix-reusing cache, thinking with a budget, images for vision models), `ModelPool` (one loaded model each, loaded on first write), `ModelInstaller` (pinned downloads into the shared home), `MLXStack`, `GPULane`. |
| `AdverbVoice` | Core ML | Ambient's Kokoro engine, lifted (front end, Kokoro-82M windows, the Paradee student), `KokoroSynthesizer`, `VoiceLibrary`, `VoicePackInstaller`. |
| `AdverbAgents` | Granite | The jobs: `PlanJob`, `DraftJob` (a day to its sheet), `RenderJob` (an approved sheet to video), `VoiceJob`, `RetimeJob`; `ModelCall`, the one funnel every model call goes through. |
| `AdverbRuntime` | all of the above | `ModelService` (installed, downloading, loaded), the root's model actions, the compute each run gets. |

The agents never name MLX or Core ML: a test gives them a scripted `LanguageModel`, the probe any
model on disk, the app the pool's handle.

### One call

`ModelCall.structured` appends the format's instructions to the last user turn (a skeleton of the
schema, in the schema's key order), starts the answer in the format when the model does not think
first (`{`, or `<!doctype html>` for a page), streams the thinking and the answer as run events,
reads the answer leniently (`AnswerParser`: a fence, prose around the object, a trailing comma, a
raw newline, an answer cut off), and sends an unreadable answer back once with what was wrong.
What the validators find after that is the job's own fix round (two for a page).

A page is never a JSON string: the model writes the page as itself, then a line
(`=== ADVERB JSON ===`), then a small JSON object (its notes and accessibility text).

### The cache

Every request of a campaign begins with the same system prompt (the skill, trimmed of what Adverb
does itself, and the addendum) and the same frozen project digest, marked `stable`. The model keeps
its last prompt in a `CheckpointedCache` and pins a snapshot where the stable parts end, so each
call after the first rewinds there and reads only its own request: about 30,000 tokens read once,
then a thousand or so per call. A request with images (the sheet's review) is read whole in a cache
of its own and leaves the text cache as it was.

A model with sliding-window layers (Gemma 4: 50 of its 60 layers see the last 1,024 tokens) keeps
those layers in a rotating cache, which cannot be trimmed once it has wrapped, and every prompt here
wraps it. So the model wrapper copies the window layers where the stable parts end (about 1.3 GB on
Gemma 4 31B) and a later call returns exactly there: the full-attention layers trim back, the window
layers are restored from the copy. Frigate's `CheckpointedCache` trims them as if they could be,
which crashed the second call of a Gemma draft until the copy was added.

### A day, sheet first

```
planned ── DraftJob ─▶ sheeted ── approve ─▶ approved ── RenderJob ─▶ rendered ─▶ posted
            │  page (≤ 2 fix rounds) · voice-over · stills · sheet.jpg · the eyes' review (one fix)
            └◀── send back with a note (the page is changed to do it) ──┘
```

With the sheet gate off (Settings › Models), `Drafter` renders a day whose sheet passed in the same
run. The sheet is drawn from the stills at 18, 42, 66 and 97 % (the rao-motion-assets layout); the
render draws it again from the videos.

### The voice

`KokoroSynthesizer` speaks a line with the pack's engine (seeded: the same words are the same
clip), and maps the model's per-phoneme frame counts onto the line's own words. A number the
normalizer expanded ("2026" → "twenty twenty-six") takes the words it became; when the two do not
line up the words are spread over the voiced span instead (`WordTimings`), and `exactTiming` says
so. Both packs report frame counts: the Paradee student and the Kokoro-82M windows.

Languages are a pack's to say (`SpeechPackInfo.languages`). Both packs speak English. A pack for
another language adds its lexicon and voices (Kokoro-82M's ja/zh windows, or FluidInference's
multilingual G2P), and `VoiceJob` speaks it with no other change; until then the language chips
show it and cannot be chosen.

## The models

Pinned in `Sources/AdverbCore/Models/ModelCatalog.swift`; a `nil` revision is a mirror not published
yet, which the app shows and cannot download. The app offers three writers for now: Gemma 4 31B
(the default from 32 GB), Ministral 3 8B (the default below), and Nemotron 3 Super (96 GB and up).
Gemma and Ministral read images, so neither loads a second model; Nemotron's eyes are Ministral.

| Repository | Commit | What it is | Mirror of |
| --- | --- | --- | --- |
| `rao-studios/gemma-4-31b-it-mlx-4bit` | `f8655066` | The default writer from 32 GB (and its own eyes), 18.4 GB, `gemma4` | `mlx-community/gemma-4-31b-it-4bit@696d436c` |
| `rao-studios/kokoro-paradee-8m-coreml` | `0b1168b9` | Heart, Kokoro distilled to 8M, 56 MB | MithrilMan/teacher-in-the-loop, converted by Ambient |
| `rao-studios/kokoro-82m-coreml-en` | `2d5d158f` | Kokoro-82M, eight English voices, 0.7 GB | hexgrad/Kokoro-82M v1.0, FluidInference's Core ML windows |
| `rao-studios/NVIDIA-Nemotron-3-Super-120B-A12B-mlx-4bit` | `e3a66d8c` | The largest writer (96 GB Macs), text only | Craft's mirror |
| `rao-studios/Ministral-3-8B-Instruct-2512-mlx-8bit` | `3d71052d` | The default writer for 24–31 GB (reads images), and the eyes for a writer that cannot see | AII's mirror |

Published to rao-studios and not offered in the app for now: `Qwen3.8-27B-mlx-4bit` (`69b8430d`),
`Qwen3.6-35B-A3B-mlx-4bit` (`eabee79d`), and Craft's `Qwen3-Coder-30B-A3B-Instruct-mlx-4bit` and
`Qwen2.5-Coder-7B-Instruct-mlx-4bit`. The probe still runs any of them by name. Qwen3-VL 8B was not
published: mlx-community's conversion (`defcdea7`) ships an index naming the original checkpoint's
750 tensors, not its shards' 1,258, and the safety pass refused it.

Every architecture offered is in Frigate's vendored registries (mlx-swift-lm 3.31.4): `gemma4`,
`nemotron_h`, `mistral3`. A model whose type is not (Mistral Small 4's `mistral4`, for one) does not
load, whatever its scores.

### Where they are kept, and found

Settings › Models names one folder, `~/.rao/models` unless the person picks another. Downloads go
into it (`huggingface/snapshots/models/<org>/<name>`), and `ModelSearch` looks through all of it,
plus `~/.rao/models` when another folder is chosen, before anything downloads. A folder is a model
when it holds `config.json` (or a voice pack's `vocab_index.json`), and it is a catalog model when
the Hub client's metadata beside those files names the model's pinned commit, wherever the folder
sits. A mirror that copies its upstream byte for byte names that upstream in `sameWeightsAs`, so
mlx-community's Gemma 4 at the mirrored commit is Adverb's Gemma 4 with no second download.
Removing a model removes every copy the search found; the confirmation lists them.

```sh
.build/debug/adverb-model-probe models [--folder <path>]   # what the search finds, and where
```

### Publishing a mirror

```sh
# An MLX model: a safety pass (safetensors headers read by hand, every file against the Hub's
# SHA-256, no pickle, no remote code), a card with its lineage, then the upload. --seed starts
# from a copy already on this Mac.
python3 -I Scripts/release/mirror-model.py --source mlx-community/gemma-4-31b-it-4bit@696d436c404745a59f30e4939a658162b0a9e57f \
    --base google/gemma-4-31b-it --target rao-studios/gemma-4-31b-it-mlx-4bit --role writer \
    --seed ~/.rao/models/huggingface/snapshots/models/mlx-community/gemma-4-31b-it-4bit --work /tmp/mirror-gemma4

# A voice pack: Core ML folders, JSON and the license only.
python3 -I Scripts/release/mirror-voice-pack.py --kind paradee --pack <folder> \
    --target rao-studios/kokoro-paradee-8m-coreml --license <Apache-2.0 text> --work /tmp/pack
```

Each prints the commit; pin it in `ModelCatalog` (and the download size from the mirror folder).

## Comparing models

`adverb-model-probe` runs each step headless, on a campaign folder, and times it. Run it on a copy of
a campaign (it writes as the app does) and build it in release (`swift build -c release --product
adverb-model-probe`, then `Scripts/build-metallib.sh release`).

```sh
P=.build/release/adverb-model-probe
$P bench --model <repo|path>                          # prefill and decode speed, warm
$P cache --model <repo|path>                          # the second call reads only its own request
$P plan  --campaign <folder> --model <repo|path> [--think]
$P draft --campaign <folder> --day 2 --model <repo|path> [--think] [--no-eyes] [--note "…"] [--render]
$P speak --pack paradee-af-heart --voice af_heart --out line.wav "Notes in the margin of everything."
```

The bar is the AII series in `/Volumes/T9/rao/marketing/aii/overview`: each topic's
`N-topic-sheet.jpg` beside the sheet `draft` writes. A writer passes when, on three AII-like days
(what / records / hood):

1. the page boots and holds the contract within its two fix rounds;
2. the sheet reads as the reference does: a 2–7 word headline with an italic gold payoff, one visual
   recipe per scene, nothing overlapping or off the edge in either orientation, the end card;
3. a narrated day's lines fit their windows (no shortening round, or one).

Record each run below: the writer, the day, whether it passed, what the eyes found, and the time.

Speed depends on what else holds the GPU. On 2026-11-08 this M4 Max was shared with a Messages
transcoding agent and AIIServer, and the same Gemma 4 31B folder measured the same in Python's
mlx-lm 0.32.2 as in Adverb, so the Swift stack is not the slow part:

| Runtime | Prefill | Decode |
| --- | --- | --- |
| Adverb (Frigate, mlx-swift 0.31.6), `bench` | 31–67 tok/s | 3.6–4.9 tok/s |
| Python mlx-lm 0.32.2, mlx 0.32.4 | 42 tok/s | 3.5 tok/s |

Both are well under what the chip's memory bandwidth allows. Run `bench` with the GPU otherwise idle
(Activity Monitor's GPU column) before comparing writers by time.

| Date | Writer | Day | Passed | Fix rounds | Time to sheet | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| 2026-11-08 | Gemma 4 31B 4-bit, thinking off | Ambient day 5, narrated (15 s) | The contract, yes; the reference, no | Page 0, voice-over 1 (a line too long for its window), sheet 1 | 25 min to the sheet, 27 min to both videos | The eyes caught the source card over the headline; they missed the highlight sitting off its words and the portrait end card's missing seal, and their fix moved the landscape card over the paragraph. One headline and one card for the whole day, where each AII sheet changes both every scene. |
| 2026-11-08 | Qwen3.8 27B 4-bit, thinking off | Ambient day 5 (15 s) | Stopped | 2, both on a false alarm | 30 min for the page | Both writers were told "Fonts did not load: italic Newsreader" for pages that used no italic body text: the probe asked `document.fonts.check`, which is false for a face no text has used yet. It now loads each face by name. |
| 2026-11-08 | Qwen3.8 27B 4-bit, thinking off | Ambient day 2 (15 s) | — | see the run log | — | GPU shared with AIIServer and a Braid run; first answer had no page (fixed since: the answer is started in the format) |

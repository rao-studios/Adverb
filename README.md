[![Adverb, by Rao Studios: a month of motion, planned and beat-matched. Under the platinum title runs a month as thirty cells, the posting days filled gold, each holding a tiny portrait or landscape frame; beneath them a song's waveform, with a gold tick dropping from every posting day onto the beat where its cut lands.](Docs/README_Assets/hero.png)](Docs/README_Assets/hero.png)

# Adverb — a month of motion

Adverb is a Mac app that turns a project you already work in into a month of social posts. Claude
plans the month with Rao's [motion-assets skill](Sources/AdverbCore/Resources/Prompts/SKILL.md);
Adverb renders every day's asset on your Mac in portrait and landscape, with captions, and lays the
month out on a calendar you post from.

You need a Mac with Apple silicon and macOS 26, and a Claude API key. An ElevenLabs API key is
optional: with one, every asset can be narrated, in English and then in other languages.

```sh
Scripts/make-app.sh && open build/Adverb.app     # or Scripts/dev.sh to build and run
```

## 1. Set up

The first launch asks for three things: your **Claude API key** (kept in your Keychain), a
**working directory** (Adverb keeps everything it makes in an `Adverb` folder there; an external
drive like the T9 works), and a **first project**: a folder you already work in, which Adverb reads
for context and never changes.

<p align="center"><img src="Docs/README_Assets/guide-onboarding.png" alt="First launch: the Claude key step, with the working directory and first project steps after it." width="620"></p>

## 2. Plan a month

**New campaign** asks for the brief: when it starts, the audience, the platforms, which days to
post and how long the videos run. **Create and plan** sends it to Claude, which reads the project
and plans one asset per posting day, each with a caption, hashtags, a platform, and the time to
post with the reason for it. Switch on **Voice-over** to narrate every asset with an ElevenLabs
voice: paste the ElevenLabs key right there if Adverb doesn't have it yet, then hear the voices
and pick one.

<p align="center"><img src="Docs/README_Assets/guide-new-campaign.png" alt="The new campaign brief: name, start date, length, time zone, audience, platforms, posting days and lengths." width="620"></p>

## 3. Build it and follow the calendar

**Build the month** writes and renders every day, two at a time. Built days show a still in
the calendar; the rest show their topic. In a narrated campaign Adverb times when each piece of text arrives
on screen, Claude writes the voice-over line by line to that text, and ElevenLabs speaks it.
The page then plays at the voice's pace, with the same warp a song cut uses: each line's text
arrives on its first word, and a scene that needs longer for its line stretches to give it room.
The captions carry what the voice says. If the voice step fails (no key, no characters left), the day is
built silent and says why. To narrate a campaign made without a voice, choose **Turn on voice-over…**
in its menu. Days already built can be narrated in the same step, or later with **Voice N built
days** in the campaign's bar. That needs no Claude build; a day is rendered again only where its
voice needs different timing. **Go live** marks the month you're posting and exports it
as a captions sheet, a CSV and a calendar file with an alarm at each post time. A project has one
live campaign at a time.

![The calendar: November with two built days, the plan's summary above, and the month's posting days with their platform and time.](Docs/README_Assets/guide-calendar.png)

## 4. Post a day

Click a day. Play it in either orientation with captions on, see when and where it goes and why,
copy the post, and **Mark posted** once it's up. Every day also ships closed captions (WebVTT and
SRT), a descriptions track, alt text and a transcript; **Accessibility** has them and their checks.

The **Voice-over** card lists the narration line by line, each with a play button. **Add a
voice-over…** narrates a day that was built silent, and **Another voice…** swaps the voice,
rendering the page again only if the new voice needs different timing. Once you've listened, **Confirm English**: then choose the languages
(the choice is kept for every day) and **Generate**. Claude translates the lines, ElevenLabs
speaks them in the same voice, and each language gets its own videos, captions and transcript
from the English frames, each line starting where its English one does. The player switches
between them. A song cut on a narrated day follows the voice: each line, and the text with it,
lands on the nearest beat, the song ducks under the voice, and every language is re-mixed.

<p align="center"><img src="Docs/README_Assets/guide-day.png" alt="A day: the landscape video, its post time and reason, the post with its character count, its posted status, and its accessibility card." width="400"></p>

## 5. Cut a day to a song

**Cut to a song…** opens your music folder. Pick a song, drag where it starts (it snaps to the
downbeats), preview it, and apply. Each scene moves onto a downbeat, the song goes under both
videos, and the silent original is kept: **Back to the silent original** restores it.

![The song picker: a library on the left, the song's waveform and beats on the right with the asset's window on it, tempo and downbeat controls, and Preview.](Docs/README_Assets/guide-music.png)

## 6. Settings

Open Settings with the **Settings** button at the foot of the sidebar, or ⌘,.
**General** holds the working directory and music folder, **Claude** the key, model and effort,
**Voice** the ElevenLabs key and the characters left this month, whether new campaigns are
narrated, the default voice and model, and the languages to generate, **Rendering** the video
quality and renderer. The native renderer needs nothing installed; the
optional Chrome renderer needs Python with Playwright, and Settings checks for it.

![Settings, Claude page: the API key, the model and effort, and the planning switches.](Docs/README_Assets/guide-settings.png)

## Cost sheet

A rolling log of what Adverb costs to run on the Claude API, newest first. Add a row each time you
log a new run. Model and effort are the Settings defaults at the time; prices are list price per
million tokens (input / output).

| Date | What | Model (effort) | Price in / out | Tokens (in / out / cache read / cache write) | Cost |
| --- | --- | --- | --- | --- | --- |
| 2026-10-28 | Plan a 30-day month for one project (Ambient) | `claude-opus-5-5` (high) | $4 / $20 | 462 / 62,410 / 371,687 / 117,748 | **$2.05** |

Claude plans the month, writes each page and reviews its stills, and in a narrated campaign writes
and translates the voice-overs; rendering runs on your Mac. Output tokens are most of the bill,
so a lower effort or a smaller model is the lever: `claude-sonnet-5-5` lists at $2 / $10.

ElevenLabs bills the voice-over per character spoken, separately from Claude: a 15 s asset is
about 200–250 characters and a 30 s one about 400–500, once for English and once per language.
Each run's log ends with a `voice:` line giving its characters and an estimate at list price
(about $0.10 per 1,000 for Multilingual v2, $0.05 for Flash v2.5; check your plan). Clips are
kept, so re-cutting to a song or reverting never spends characters again.

## Where things live

| What | Where |
| --- | --- |
| Projects, campaigns, videos, captions, logs | `<working directory>/Adverb/<project>/` |
| Settings | `~/.rao/apps/adverb/settings.json` |
| Claude key | Keychain, `nyc.rao.adverb` (`ANTHROPIC_API_KEY`) |
| ElevenLabs key | Keychain, `nyc.rao.adverb` (`ELEVENLABS_API_KEY`) |
| A day's narration | `<asset>/voice/<language>/` (`script.json` and one clip per line) |
| Voice list and previews | `~/Library/Caches/nyc.rao.adverb/voices/` |

Removing a project asks first and lets you keep its Adverb folder. The folder it reads is never
touched.

## For developers

`Scripts/test.sh` runs every suite. `swift run adverb-render-probe` renders a page, reads a song's
beats or inspects a video without the app. `Docs/README_Assets/src/build.sh` rebuilds the hero and
the icon. The app is built on [Granite](https://github.com/riteshpakala/Granite) in Craft's shape,
with Claude's work running as Craft's `@Agent`s. Apache-2.0 (see [LICENSE](LICENSE)).

> *"The road to hell is paved with adverbs."* — Stephen King

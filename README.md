# Bible Verse — Omarchy plugin

A bar widget for [Omarchy](https://omarchy.org/) that shows a daily Bible
verse and a detail popup, in the style of
[`einarnot.bibleverse`](https://plugins.omarchy.org/plugin.html?id=einarnot.bibleverse)
but with its own "terminal card" look, and backed by the free
[Midvash API](https://api.midvash.com/) instead of scripture.api.bible.

- **Bar pill**: shows a short reference, e.g. `Lucas 6:38`.
- **Popup card**: date, full reference, the verse text, and a footer with
  the translation's attribution, a `COPY` action (copies the verse + quote
  to the clipboard) and an `ASK` action (opens the verse on midvash.com).
- **Language**: Spanish by default, or your system language when it's one
  Midvash has a translation for (falls back to Spanish otherwise). Override
  explicitly via settings (see below).
- The same verse is shown to everyone for a given UTC day (that's how
  Midvash's `/v1/votd` endpoint works); the widget re-checks every 5
  minutes and refetches once the day rolls over.

## Interactions

| Bar pill | Popup |
|---|---|
| Left click — open/close the popup | `↻` — manual refresh (or press `r`) |
| Middle click — refresh | `COPY` — copy verse + reference to clipboard |
| Right click — copy verse to clipboard | `ASK` — open the verse on midvash.com |
| | `Esc` — close |

## Install

Copy (or symlink, for local development) this directory into Omarchy's user
plugin folder, then add it to the bar:

```bash
ln -s "$(pwd)" ~/.config/omarchy/plugins/io.github.daniace.bibleverse
omarchy bar move io.github.daniace.bibleverse --section right   # or left/center
```

Saving any file under `~/.config/omarchy/plugins/` hot-reloads the plugin —
no `omarchy restart shell` needed. If a change doesn't seem to apply, force
a rescan:

```bash
omarchy-shell shell rescanPlugins
```

## Settings

There's no dedicated settings form (that's a first-party-only feature of the
shell today); configure the widget by editing its entry directly in
`~/.config/omarchy/shell.json`:

```json
{
  "bar": {
    "layout": {
      "right": [
        { "id": "io.github.daniace.bibleverse", "language": "es", "version": "rvr1960" }
      ]
    }
  }
}
```

- `language` — `"auto"` (default, follows your system locale, falling back
  to Spanish), or an explicit code: `es`, `en`, `pt-br`, `pt-pt`, `fr`, `de`,
  `it`, `ru`, `zh`, `ko`, `ja`, and others (see `LANGUAGES` in `Model.js`).
- `version` — `"auto"` (default: the language's usual version — e.g. RVR1960
  for Spanish, WEB for English), or any exact
  [Midvash version slug](https://api.midvash.com/v1/versions) (e.g. `nvies`,
  `kjv`, `nvi`).

## Credits & licensing

- Verse text, book names, and translation metadata come from the
  [Midvash API](https://api.midvash.com/) (free, public, no key required).
  Each translation carries its own copyright, shown in the popup footer —
  some are public domain (e.g. WEB), others are used with permission (e.g.
  RVR1960 © Sociedades Bíblicas Unidas). Don't assume public domain just
  because one version is.
- This plugin's code is MIT-licensed — see `LICENSE`.

## Files

- `manifest.json` — plugin declaration (`io.github.daniace.bibleverse`, kind `bar-widget`).
- `BarWidget.qml` — the bar pill + panel host, mirrors `omarchy.weather`/`omarchy.clock`.
- `Panel.qml` — the popup card: fetch chain, state, and layout.
- `Model.js` — pure helpers (language/version resolution, API response parsing, formatting).

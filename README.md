# Daily Bible Verse (Multi-language)

An [Omarchy](https://omarchy.org/) bar-widget plugin that shows a daily
Bible verse and a detail popup, in the spirit of
[`einarnot.bibleverse`](https://plugins.omarchy.org/plugin.html?id=einarnot.bibleverse)
but backed by the free, keyless [Midvash API](https://api.midvash.com/)
(86 versions across 32 languages) instead of scripture.api.bible, and with
language/version pickers built in.

- **Bar pill**: shows a short reference, e.g. `Lucas 6:38`.
- **Popup card**: date, full reference, the verse text, language and Bible
  version pickers, and a footer with the translation's attribution, a
  `COPY` action (copies the verse + reference to the clipboard) and an
  `OPEN` action (opens the verse on midvash.com).
- **Theme-matched**: colors come from the shell's live theme tokens
  (`Color.popups.*`, `Color.accent`, ...) and the shared Ui kit
  (`KeyboardPanel`, `PanelSectionHeader`, `PanelActionButton`,
  `PanelSeparator`), so the card re-colors with whichever Omarchy theme is
  active — same as every first-party panel (weather, clock, network, ...).
- **Language**: Spanish by default, or your system language when Midvash
  has a translation for it (falls back to Spanish otherwise). Change it
  any time from the popup's language picker, or preset it in settings.
- The same verse is shown to everyone for a given UTC day (that's how
  Midvash's `/v1/votd` endpoint works); the widget re-checks every 5
  minutes and refetches once the day rolls over.

## Interactions

| Bar pill | Popup |
|---|---|
| Left click — open/close the popup | Language / Version dropdowns — pick a language or Bible version; selecting either refetches immediately |
| Middle click — refresh | `↻` — manual refresh (or press `r`) |
| Right click — copy verse to clipboard | `COPY` — copy verse + reference to clipboard |
| | `OPEN` — open the verse on midvash.com |
| | `Esc` — close |

Picking a language resets the version to that language's default (e.g.
RVR1960 for Spanish, WEB for English); picking a version keeps the current
language. Both choices persist to `shell.json`, so they survive a restart.

## Install

Copy (or symlink, for local development) this directory into Omarchy's user
plugin folder, then add it to the bar:

```bash
ln -s "$(pwd)" ~/.config/omarchy/plugins/io.github.daniace.dailybibleverse-multilang
omarchy plugin enable io.github.daniace.dailybibleverse-multilang   # right section by default
```

Saving any file under `~/.config/omarchy/plugins/` is *supposed* to
hot-reload the plugin, but in practice that watcher doesn't reliably follow
a symlinked plugin directory back to files edited elsewhere (e.g. a repo
checkout under `~/Work/`) — if edits don't seem to apply, force a real
reload:

```bash
omarchy restart shell
```

(`omarchy-shell shell rescanPlugins` re-discovers added/removed plugins,
but doesn't reliably force a code reload for an already-loaded plugin
either — `omarchy restart shell` is the reliable one.)

## Settings

There's no dedicated settings form (that's a first-party-only feature of the
shell today) — but you don't need one: language and Bible version can be
changed directly from the popup's dropdowns. To pin a starting value instead
of "auto", edit the widget's entry in `~/.config/omarchy/shell.json`:

```json
{
  "bar": {
    "layout": {
      "right": [
        { "id": "io.github.daniace.dailybibleverse-multilang", "language": "es", "version": "rvr1960" }
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
  RVR1960 © Sociedades Bíblicas Unidas). The footer always shows the real
  attribution — never assume public domain just because one version is.
- This plugin's code is MIT-licensed — see `LICENSE`.

## Files

- `manifest.json` — plugin declaration (`io.github.daniace.dailybibleverse-multilang`, kind `bar-widget`).
- `BarWidget.qml` — the bar pill + panel host, mirrors `omarchy.weather`/`omarchy.clock`.
- `Panel.qml` — the popup card: fetch chain, state, language/version pickers, and layout.
- `Model.js` — pure helpers (language/version resolution, API response parsing, formatting).

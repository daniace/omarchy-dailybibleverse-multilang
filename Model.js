// Pure helpers for the Bible Verse of the Day plugin: language/version
// resolution, Midvash API response parsing, and small text-formatting
// utilities. Kept dependency-free (no QML imports) so it stays easy to
// read and, if ever needed, unit-test outside Quickshell.

// Language -> { version, locale, dateFormat } for the Midvash API and for
// Qt.locale()-driven date formatting. `version` is a Midvash version slug
// known to exist in that language (see /v1/versions). `locale` is a
// QLocale-style tag used only to render weekday/month names. `dateFormat`
// follows Qt's date format tokens (see Qt.formatDate / toLocaleDateString).
var LANGUAGES = {
  "es":    { version: "rvr1960",  locale: "es_ES", dateFormat: "dddd, d 'de' MMMM 'de' yyyy" },
  "en":    { version: "web",      locale: "en_US", dateFormat: "dddd, d MMMM yyyy" },
  "pt-br": { version: "aa",       locale: "pt_BR", dateFormat: "dddd, d 'de' MMMM 'de' yyyy" },
  "pt-pt": { version: "bpt",      locale: "pt_PT", dateFormat: "dddd, d 'de' MMMM 'de' yyyy" },
  "pt":    { version: "aa",       locale: "pt_BR", dateFormat: "dddd, d 'de' MMMM 'de' yyyy" },
  "fr":    { version: "lsg",      locale: "fr_FR", dateFormat: "dddd d MMMM yyyy" },
  "de":    { version: "luth1912", locale: "de_DE", dateFormat: "dddd, d. MMMM yyyy" },
  "it":    { version: "riveduta", locale: "it_IT", dateFormat: "dddd d MMMM yyyy" },
  "nl":    { version: "dutch1917",locale: "nl_NL", dateFormat: "dddd d MMMM yyyy" },
  "sv":    { version: "sv1917",   locale: "sv_SE", dateFormat: "dddd d MMMM yyyy" },
  "da":    { version: "dansk1931",locale: "da_DK", dateFormat: "dddd d. MMMM yyyy" },
  "nb":    { version: "nb1930",   locale: "nb_NO", dateFormat: "dddd d. MMMM yyyy" },
  "pl":    { version: "bg",       locale: "pl_PL", dateFormat: "dddd, d MMMM yyyy" },
  "cs":    { version: "bkr",      locale: "cs_CZ", dateFormat: "dddd d. MMMM yyyy" },
  "hu":    { version: "kar",      locale: "hu_HU", dateFormat: "yyyy. MMMM d., dddd" },
  "ro":    { version: "vdc",      locale: "ro_RO", dateFormat: "dddd, d MMMM yyyy" },
  "ru":    { version: "synodal",  locale: "ru_RU", dateFormat: "dddd, d MMMM yyyy" },
  "uk":    { version: "kp",       locale: "uk_UA", dateFormat: "dddd, d MMMM yyyy" },
  "sr":    { version: "skd",      locale: "sr_RS", dateFormat: "dddd, d. MMMM yyyy" },
  "tr":    { version: "ycv",      locale: "tr_TR", dateFormat: "d MMMM yyyy dddd" },
  "ar":    { version: "svd",      locale: "ar_SA", dateFormat: "dddd، d MMMM yyyy" },
  "he":    { version: "mh",       locale: "he_IL", dateFormat: "dddd, d MMMM yyyy" },
  "zh":    { version: "cuv",      locale: "zh_CN", dateFormat: "yyyy MMMM d dddd" },
  "ko":    { version: "kor",      locale: "ko_KR", dateFormat: "yyyy MMMM d dddd" },
  "ja":    { version: "kgy",      locale: "ja_JP", dateFormat: "yyyy MMMM d dddd" },
  "vi":    { version: "vi1934",   locale: "vi_VN", dateFormat: "dddd, d MMMM yyyy" },
  "id":    { version: "indonesian", locale: "id_ID", dateFormat: "dddd, d MMMM yyyy" },
  "tl":    { version: "bnb",      locale: "tl_PH", dateFormat: "dddd, d MMMM yyyy" },
  "sw":    { version: "suv",      locale: "sw_KE", dateFormat: "dddd, d MMMM yyyy" },
  "fi":    { version: "pr1933",   locale: "fi_FI", dateFormat: "dddd d. MMMM yyyy" },
  "eo":    { version: "lsb",      locale: "eo",    dateFormat: "dddd, d MMMM yyyy" },
  "la":    { version: "vulg",     locale: "la",    dateFormat: "dddd, d MMMM yyyy" }
}

var DEFAULT_LANGUAGE = "es"

// ---- Network/process hardening -------------------------------------
//
// Fixed, symlink-resolved executable paths ("verified executable
// identity") — every Process this plugin runs uses one of these, never a
// bare command name resolved through PATH. If a path doesn't exist on a
// given system the Process simply fails to start; there is no fallback
// search.
var CURL_BIN = "/usr/bin/curl"
var WL_COPY_BIN = "/usr/bin/wl-copy"
var XDG_OPEN_BIN = "/usr/bin/xdg-open"
var TIMEOUT_BIN = "/usr/bin/timeout"

// Every fetch response is fully buffered in memory by Quickshell's
// StdioCollector before we ever see it, so the real cap has to be enforced
// in the curl invocation itself, not after: curl's own --max-filesize is
// documented to have no effect on a transfer whose length isn't known in
// advance (e.g. chunked encoding), so it's paired with --limit-rate +
// --max-time, which bounds total bytes (rate × time) regardless of how
// the response is framed. MAX_RESPONSE_CHARS is a second, much tighter
// gate applied in JS before JSON.parse — these are small, flat API
// responses that are normally a few KB.
var MAX_RESPONSE_BYTES = 1048576      // 1 MiB — --max-filesize
var MAX_DOWNLOAD_RATE_BPS = 262144    // 256 KiB/s — --limit-rate
var MAX_RESPONSE_CHARS = 262144       // ~256 KB of JSON text we'll ever parse
var MAX_VERSE_TEXT_CHARS = 20000      // a verse/chapter is never remotely this long
var MAX_VERSIONS_ROWS = 1000          // sanity cap on the /v1/versions array

// A hardened curl invocation: fixed binary, no ambient curl config (-q
// must be the first argument to have effect), HTTPS-only including across
// any redirect, and bounded time + rate + declared size.
function curlCommand(url, maxTimeSeconds) {
  return [
    CURL_BIN,
    "-q",
    "--proto", "=https",
    "--proto-redir", "=https",
    "-fsS",
    "--max-time", String(maxTimeSeconds),
    "--max-filesize", String(MAX_RESPONSE_BYTES),
    "--limit-rate", String(MAX_DOWNLOAD_RATE_BPS),
    String(url)
  ]
}

// Reject oversized responses before they're ever handed to JSON.parse.
function withinResponseLimit(raw) {
  return typeof raw === "string" && raw.length > 0 && raw.length <= MAX_RESPONSE_CHARS
}

// Only ever hand xdg-open a same-host, https verse URL from Midvash —
// `data.url` in the votd/passage response is API-controlled, and passing
// an arbitrary scheme/host straight to a URL opener would let a
// compromised or malicious response invoke local or custom URL handlers.
function isAllowedVerseUrl(url) {
  return /^https:\/\/midvash\.com\//i.test(String(url || ""))
}

// Native display names for the language picker.
var LANGUAGE_LABELS = {
  "es": "Español", "en": "English", "pt-br": "Português (Brasil)",
  "pt-pt": "Português (Portugal)", "pt": "Português", "fr": "Français",
  "de": "Deutsch", "it": "Italiano", "nl": "Nederlands", "sv": "Svenska",
  "da": "Dansk", "nb": "Norsk", "pl": "Polski", "cs": "Čeština",
  "hu": "Magyar", "ro": "Română", "ru": "Русский", "uk": "Українська",
  "sr": "Српски", "tr": "Türkçe", "ar": "العربية", "he": "עברית",
  "zh": "中文", "ko": "한국어", "ja": "日本語", "vi": "Tiếng Việt",
  "id": "Bahasa Indonesia", "tl": "Tagalog", "sw": "Kiswahili",
  "fi": "Suomi", "eo": "Esperanto", "la": "Latina"
}

// UI chrome strings (labels, buttons) — translated for the two languages
// this plugin is built around; every other content language still gets
// its verse text, book name, and date localized via Midvash/Qt, but falls
// back to the English chrome below.
var STRINGS = {
  es: {
    heading: "VERSÍCULO DEL DÍA",
    copy: "COPIAR",
    ask: "ABRIR",
    refresh: "Actualizar",
    loading: "Cargando versículo…",
    error: "No se pudo cargar el versículo.",
    retry: "Reintentando…",
    dataVia: "Datos vía"
  },
  en: {
    heading: "VERSE OF THE DAY",
    copy: "COPY",
    ask: "OPEN",
    refresh: "Refresh",
    loading: "Loading verse…",
    error: "Couldn't load the verse.",
    retry: "Retrying…",
    dataVia: "Data via"
  }
}

// Qt.locale().name looks like "es_AR", "pt_BR", "en_US", "C" (no locale
// configured). Normalize to one of our language keys, preferring an exact
// "xx-YY" match (currently only Portuguese needs the distinction) before
// falling back to the bare language code.
function normalizeLanguage(qtLocaleName) {
  var raw = String(qtLocaleName || "").replace(/^\s+|\s+$/g, "")
  if (!raw || raw === "C") return ""

  var parts = raw.split(/[-_]/)
  var lang = (parts[0] || "").toLowerCase()
  var region = (parts[1] || "").toLowerCase()

  if (lang === "pt") {
    var withRegion = "pt-" + region
    if (LANGUAGES[withRegion]) return withRegion
    return "pt-br"
  }

  return LANGUAGES[lang] ? lang : ""
}

// Resolve the effective content language: an explicit override wins, then
// the system locale (when supported), then Spanish.
function resolveLanguage(overrideSetting, qtLocaleName) {
  var override = String(overrideSetting || "").replace(/^\s+|\s+$/g, "").toLowerCase()
  if (override && override !== "auto" && LANGUAGES[override]) return override

  var fromSystem = normalizeLanguage(qtLocaleName)
  if (fromSystem) return fromSystem

  return DEFAULT_LANGUAGE
}

// Resolve the Midvash version slug: an explicit override wins, else the
// language's default version.
function resolveVersion(overrideSetting, language) {
  var override = String(overrideSetting || "").replace(/^\s+|\s+$/g, "").toLowerCase()
  if (override && override !== "auto") return override

  var entry = LANGUAGES[language] || LANGUAGES[DEFAULT_LANGUAGE]
  return entry.version
}

function localeTagFor(language) {
  var entry = LANGUAGES[language] || LANGUAGES[DEFAULT_LANGUAGE]
  return entry.locale
}

function dateFormatFor(language) {
  var entry = LANGUAGES[language] || LANGUAGES[DEFAULT_LANGUAGE]
  return entry.dateFormat
}

function stringsFor(language) {
  return STRINGS[language] || STRINGS.en
}

// UTC day key ("YYYY-MM-DD") matching Midvash's "same verse for everyone
// on a given UTC day" rule, so the refresh timer only refetches when the
// day actually rolls over.
function utcDayKey(date) {
  var d = date || new Date()
  return d.toISOString().slice(0, 10)
}

// GET /v1/votd response -> a flat verse object, or null on anything
// unexpected (including "too big to be a real response").
function parseVotd(raw) {
  if (!withinResponseLimit(raw)) return null
  try {
    var data = JSON.parse(raw)
    if (!data || typeof data.text !== "string" || !data.text) return null
    if (data.text.length > MAX_VERSE_TEXT_CHARS) return null
    var url = String(data.url || "")
    return {
      text: data.text,
      version: String(data.version || ""),
      bookSlug: String(data.book_slug || ""),
      chapter: data.chapter,
      verseStart: data.verse_start,
      verseEnd: data.verse_end,
      // Blanked rather than passed through when it doesn't match the
      // expected host/scheme — see isAllowedVerseUrl().
      url: isAllowedVerseUrl(url) ? url : ""
    }
  } catch (e) {
    return null
  }
}

// GET /v1/books/{slug} response -> localized display name for `language`,
// falling back to English, then to the raw slug.
function parseBookName(raw, language, fallbackSlug) {
  if (!withinResponseLimit(raw)) return fallbackSlug || ""
  try {
    var data = JSON.parse(raw).data
    var names = data && data.name
    if (names && typeof names === "object") {
      if (typeof names[language] === "string" && names[language]) return names[language]
      if (typeof names.en === "string" && names.en) return names.en
    }
  } catch (e) {
    // fall through to fallback below
  }
  return fallbackSlug || ""
}

// GET /v1/versions/{slug} response -> { shortName, attribution }.
// `attribution` is the second line of the version's copyright blob (e.g.
// "© 1960 Sociedades Bíblicas Unidas." or "Public Domain (CC0)."), which is
// the concise, accurate credit line — never assume "public domain" for a
// version whose copyright says otherwise.
function parseVersionMeta(raw) {
  if (!withinResponseLimit(raw)) return null
  try {
    var data = JSON.parse(raw).data
    if (!data) return null
    var lines = String(data.copyright || "").split("\n").map(function(l) { return l.replace(/^\s+|\s+$/g, "") }).filter(Boolean)
    return {
      shortName: String(data.shortName || data.slug || "").toUpperCase(),
      attribution: lines.length > 1 ? lines[1] : (lines[0] || "")
    }
  } catch (e) {
    return null
  }
}

// "3" + 16 + 16 -> "3:16"; "3" + 16 + 20 -> "3:16-20".
function formatVerseRange(chapter, verseStart, verseEnd) {
  var range = String(verseStart)
  if (verseEnd !== undefined && verseEnd !== null && String(verseEnd) !== String(verseStart)) range += "-" + verseEnd
  return chapter + ":" + range
}

function buildReference(bookName, chapter, verseStart, verseEnd) {
  var parts = [bookName || "", formatVerseRange(chapter, verseStart, verseEnd)]
  return parts.filter(Boolean).join(" ")
}

// { value, label } rows for the language Dropdown, sorted by native name.
function languageOptions() {
  var out = []
  for (var code in LANGUAGES) {
    out.push({ value: code, label: LANGUAGE_LABELS[code] || code })
  }
  out.sort(function(a, b) { return a.label < b.label ? -1 : (a.label > b.label ? 1 : 0) })
  return out
}

// GET /v1/versions response -> a flat array of { slug, shortName, name,
// language }, for filtering into per-language version options.
function parseVersionsList(raw) {
  if (!withinResponseLimit(raw)) return []
  try {
    var rows = JSON.parse(raw).data
    if (!Array.isArray(rows)) return []
    return rows.slice(0, MAX_VERSIONS_ROWS).map(function(v) {
      return {
        slug: String(v.slug || ""),
        shortName: String(v.shortName || v.slug || "").toUpperCase(),
        name: String(v.name || ""),
        language: String(v.language || "")
      }
    })
  } catch (e) {
    return []
  }
}

// { value, label } rows for the version Dropdown, filtered to one language
// and sorted by short name (e.g. "RVR1960 — Reina-Valera 1960").
function versionOptionsForLanguage(list, language) {
  var rows = (list || []).filter(function(v) { return v.language === language })
  rows.sort(function(a, b) { return a.shortName < b.shortName ? -1 : (a.shortName > b.shortName ? 1 : 0) })
  return rows.map(function(v) {
    return { value: v.slug, label: v.name ? (v.shortName + " — " + v.name) : v.shortName }
  })
}

if (typeof module !== "undefined") {
  module.exports = {
    LANGUAGES: LANGUAGES,
    DEFAULT_LANGUAGE: DEFAULT_LANGUAGE,
    LANGUAGE_LABELS: LANGUAGE_LABELS,
    CURL_BIN: CURL_BIN,
    WL_COPY_BIN: WL_COPY_BIN,
    XDG_OPEN_BIN: XDG_OPEN_BIN,
    TIMEOUT_BIN: TIMEOUT_BIN,
    curlCommand: curlCommand,
    withinResponseLimit: withinResponseLimit,
    isAllowedVerseUrl: isAllowedVerseUrl,
    normalizeLanguage: normalizeLanguage,
    resolveLanguage: resolveLanguage,
    resolveVersion: resolveVersion,
    localeTagFor: localeTagFor,
    dateFormatFor: dateFormatFor,
    stringsFor: stringsFor,
    utcDayKey: utcDayKey,
    parseVotd: parseVotd,
    parseBookName: parseBookName,
    parseVersionMeta: parseVersionMeta,
    formatVerseRange: formatVerseRange,
    buildReference: buildReference,
    languageOptions: languageOptions,
    parseVersionsList: parseVersionsList,
    versionOptionsForLanguage: versionOptionsForLanguage
  }
}

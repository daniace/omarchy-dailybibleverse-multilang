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

// UI chrome strings (labels, buttons) — translated for the two languages
// this plugin is built around; every other content language still gets
// its verse text, book name, and date localized via Midvash/Qt, but falls
// back to the English chrome below.
var STRINGS = {
  es: {
    heading: "VERSÍCULO DEL DÍA",
    copy: "COPIAR",
    ask: "ABRIR",
    loading: "Cargando versículo…",
    error: "No se pudo cargar el versículo.",
    retry: "Reintentando…",
    dataVia: "Datos vía"
  },
  en: {
    heading: "VERSE OF THE DAY",
    copy: "COPY",
    ask: "OPEN",
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
// unexpected.
function parseVotd(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    if (!data || typeof data.text !== "string" || !data.text) return null
    return {
      text: data.text,
      version: String(data.version || ""),
      bookSlug: String(data.book_slug || ""),
      chapter: data.chapter,
      verseStart: data.verse_start,
      verseEnd: data.verse_end,
      url: String(data.url || "")
    }
  } catch (e) {
    return null
  }
}

// GET /v1/books/{slug} response -> localized display name for `language`,
// falling back to English, then to the raw slug.
function parseBookName(raw, language, fallbackSlug) {
  try {
    var data = JSON.parse(String(raw || "")).data
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
  try {
    var data = JSON.parse(String(raw || "")).data
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

// Single-quote a string for safe use inside a `bar.run("...")` shell
// command (wraps in '...', escaping embedded single quotes).
function shellQuote(value) {
  return "'" + String(value == null ? "" : value).replace(/'/g, "'\\''") + "'"
}

if (typeof module !== "undefined") {
  module.exports = {
    LANGUAGES: LANGUAGES,
    DEFAULT_LANGUAGE: DEFAULT_LANGUAGE,
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
    shellQuote: shellQuote
  }
}

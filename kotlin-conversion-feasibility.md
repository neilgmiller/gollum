# Kotlin Conversion Feasibility Assessment

**Project:** Gollum Wiki Engine v6.1.0
**Date:** 2026-04-02

---

## Codebase Summary

Gollum is a Git-backed wiki engine built on Sinatra (Ruby) with:

- ~2,500 LOC of core Ruby (`lib/gollum/`)
- ~1,240 LOC of view classes (20 Mustache-backed view classes)
- ~4,500 LOC of frontend JavaScript (29 files)
- ~1,400 LOC of SCSS (15 files)
- 20 Mustache templates
- ~3,069 LOC of tests (22 files)
- WAR file output via JRuby + Warbler

---

## Verdict: Feasible, but significant effort

The core Ruby code is modest (~2,500 LOC), well-structured, and the layered architecture maps cleanly to Kotlin/JVM idioms. However, the real challenge lies in replacing the ecosystem of Ruby gems — particularly `gollum-lib`, which is the heart of the wiki.

---

## The Critical Blocker: gollum-lib

The biggest risk is **gollum-lib** — a separate gem that provides:

- All Git operations (page CRUD, history, diffs, search)
- Multi-format markup rendering (Markdown, AsciiDoc, Textile, Org, MediaWiki, etc. — 10+ formats)
- Wiki link/tag parsing and resolution
- Redirect management
- Metadata extraction

The Sinatra app (`app.rb`) is essentially a thin web layer over gollum-lib. Options:

1. **Rewrite gollum-lib in Kotlin** — The bulk of the work. Use JGit for Git operations and find/wrap Java/Kotlin libraries for each markup format. Likely 5-10x more code than the web layer.
2. **Use JRuby as a bridge** — Call gollum-lib from Kotlin via JRuby's embedding API. Defeats much of the purpose of converting.

---

## Component-by-Component Breakdown

| Component | Ruby LOC | Kotlin Equivalent | Effort |
|-----------|----------|-------------------|--------|
| **Web routes** (`app.rb`) | 747 | Ktor or Spring Boot routes | **Medium** — straightforward mapping |
| **Views** (20 classes) | 1,240 | Kotlin + Mustache/Thymeleaf/kotlinx.html | **Medium** — mostly data preparation |
| **Templates** (20 Mustache files) | ~20 files | Can reuse Mustache as-is (JMustache exists) | **Low** |
| **Helpers/utils** | 286 | Kotlin utility functions | **Low** |
| **Frontend JS/SCSS** | ~6,000 | Reuse as-is — no conversion needed | **None** |
| **Asset pipeline** (Sprockets) | 55 | Gradle + WebJars or Webpack | **Low-Medium** |
| **CLI entry point** (`bin/gollum`) | 302 | Clikt or picocli | **Low** |
| **gollum-lib replacement** | N/A | JGit + markup libraries | **Very High** |
| **Tests** | 3,069 | JUnit5/Kotest rewrite | **High** |

---

## Recommended Kotlin Stack

| Layer | Library |
|-------|---------|
| Web framework | **Ktor** (lightweight, similar philosophy to Sinatra) |
| Templating | **JMustache** (drop-in for existing templates) |
| Git operations | **JGit** (Eclipse's pure-Java Git, already used by gollum's JRuby adapter) |
| Markdown | **flexmark-java** (excellent GFM support) |
| AsciiDoc | **AsciidoctorJ** |
| Other markups | Mixed — some have JVM libraries, some don't |
| Build/WAR | **Gradle** with `war` plugin |
| CLI | **Clikt** |
| Testing | **Kotest** + **Ktor test client** |

---

## Conversion Phases

### Phase 1 — Web layer + Markdown only

Ktor routes, JMustache templates, JGit page CRUD, flexmark rendering. Gets a working wiki with Markdown support.

### Phase 2 — Full markup support

Add AsciiDoc, Textile, Org, MediaWiki, etc. Some formats lack mature JVM libraries.

### Phase 3 — Feature parity

Search, diffs, history, uploads, emoji, math rendering, editor modes, i18n.

### Phase 4 — WAR packaging + tests

Gradle WAR build, full test suite.

---

## Key Risks

### 1. Markup format coverage

Ruby's `github-markup` delegates to native tools (e.g., `wikicloth` for MediaWiki, `RedCloth` for Textile). Some formats have no quality JVM library. May need to shell out to external tools or accept reduced format support.

### 2. gollum-lib's Git abstraction

gollum-lib does significant work: wiki link resolution, tag parsing, page metadata extraction, sidebar/header/footer handling, redirect management. This is domain-specific logic that must be reimplemented from scratch or ported by reading gollum-lib's source.

### 3. Frontend JavaScript

The ~4,500 LOC of JS and SCSS can be reused without conversion, but the asset pipeline (Sprockets) needs replacing. Gradle + a simple copy/minify task would work.

### 4. Behavioral fidelity

Gollum has 16 years of edge-case handling. The test suite (3,069 LOC) is the best specification, but some behavior is implicit in Ruby idioms (e.g., string handling, regex differences).

---

## Core Ruby Dependencies and Kotlin Equivalents

### Runtime Dependencies

| Ruby Gem | Purpose | Kotlin/JVM Equivalent |
|----------|---------|----------------------|
| sinatra (~4.0) | Web framework | Ktor |
| sinatra-contrib (~4.0) | Sinatra extensions | Ktor plugins |
| mustache-sinatra (~2.0) | Server-side templating | JMustache |
| gollum-lib (~6.0) | Core wiki logic | **Must rewrite** (JGit + markup libs) |
| rack (>=3.0) | Web server interface | Servlet API |
| kramdown (~2.3) | Markdown parser | flexmark-java |
| kramdown-parser-gfm (~1.1.0) | GitHub Flavored Markdown | flexmark-java (built-in GFM) |
| sprockets (~4.1) | Asset pipeline | Gradle / Webpack |
| i18n (~1.8) | Internationalization | kotlin-i18n or ResourceBundle |
| gemojione (~4.1) | Emoji support | emoji-java or custom |
| octicons (~19.0) | SVG icon system | octicons npm package (reuse) |
| rss (~0.3) | RSS feed generation | ROME library |
| useragent (~0.16.2) | User agent parsing | ua-parser (JVM) |
| webrick (~1.7) | Fallback web server | Embedded Jetty/Netty (via Ktor) |

### Node.js Dependencies (reusable as-is)

| Package | Purpose |
|---------|---------|
| @primer/css (^20.8.0) | GitHub's CSS framework |
| ace-builds (^1.33) | Code editor component |
| katex (^0.16.21) | LaTeX/math rendering |
| mermaid (^11.10.1) | Diagram generation |
| mousetrap (^1.6.5) | Keyboard shortcut library |

---

## Route Inventory

All routes that must be reimplemented in Kotlin:

| Route | Methods | Purpose |
|-------|---------|---------|
| `/` | GET | Redirect to index page |
| `/gollum/feed/` | GET | RSS feed of recent changes |
| `/gollum/assets/*` | GET | Static assets (CSS, JS) |
| `/gollum/last_commit_info` | GET | JSON commit metadata |
| `/gollum/octicon/:name` | GET | SVG icon by name |
| `/gollum/emoji/:name` | GET | PNG emoji by name |
| `/gollum/data/*` | GET | Raw page data |
| `/gollum/edit/*` | GET/POST | Page editor UI/API |
| `/gollum/create/*` | GET/POST | New page creation |
| `/gollum/delete/*` | POST | Page deletion |
| `/gollum/rename/*` | POST | Page renaming with redirect support |
| `/gollum/revert/*/:sha1/:sha2` | POST | Revert to previous version |
| `/gollum/upload_file` | POST | File upload (AJAX) |
| `/gollum/preview` | POST | Preview formatted page |
| `/gollum/history/*` | GET | Page version history |
| `/gollum/latest_changes` | GET | Wiki changelog |
| `/gollum/compare/*` | GET | Diff between versions |
| `/gollum/commit/:sha` | GET | Specific commit view |
| `/gollum/search` | GET | Full-text search |
| `/gollum/overview` | GET | Wiki directory tree |
| `/:path/:version` | GET | Specific version of page |
| `/*` | GET | Page display or file download |

---

## Configuration Options to Support

The Kotlin version must support these CLI options (currently 50+):

- `-p/--port` — Port to bind
- `-h/--host` — Host to bind
- `-c/--config` — Config file path
- `-r/--ref` — Git branch
- `-b/--base-path` — URL base path
- `--page-file-dir` — Restrict to subdirectory
- `--css/--js` — Inject custom files
- `--no-edit` — Read-only mode
- `--allow-uploads` — Enable file uploads
- `--math` — Math rendering (mathjax/katex)
- `--critic-markup` — Enable annotations
- `--h1-title` — Use first h1 as title
- `--user-icons` — Avatar style (gravatar/identicon)
- `--template-dir` — Custom template directory
- `--emoji` — Parse emoji
- `--mermaid` — Enable diagrams
- And ~30 more

---

## Markup Format Coverage — Detailed Analysis

### How Gollum Renders Markup Today

The rendering pipeline flows through several layers:

1. **File extension** detected by `Gollum::Page.format_for()` → determines format
2. **gollum-lib** delegates to `github-markup` gem → dispatches to format-specific Ruby gem
3. **Format gem** (kramdown, asciidoctor, RedCloth, etc.) renders markup → HTML
4. **gollum-lib** post-processes: wiki link resolution, tag expansion, metadata extraction, TOC generation
5. **View layer** (`page.rb`) does format-specific DOM parsing (e.g., h1 extraction differs by format)

The view layer has format-specific behavior in `find_header_node()`:

- **AsciiDoc**: `div#gollum-root > h1:first-child`
- **Pod**: `div#gollum-root > a.dummyTopAnchor:first-child + h1`
- **RST**: `div#gollum-root > div > div > h1:first-child`
- **All others**: `div#gollum-root > h1:first-child`

Each format also has a dedicated editor language file (`editor/langs/*.js`) providing syntax-aware toolbar buttons, formatting templates, and help content. AsciiDoc notably disables Gollum's `[[link]]` tag syntax.

---

### Format-by-Format JVM Library Assessment

#### Markdown / GFM — FULL PARITY

| | Ruby | JVM |
|---|---|---|
| **Library** | kramdown + kramdown-parser-gfm | commonmark-java (recommended) or flexmark-java |
| **Maven** | — | `org.commonmark:commonmark:0.28.0` |
| **Last release** | — | Oct 2025 |
| **Maintenance** | Active | Active |
| **Parity** | — | **Full** |

commonmark-java supports GFM via extension artifacts (tables, strikethrough, autolink, alerts, footnotes). flexmark-java (`com.vladsch.flexmark:flexmark-all:0.64.8`) is more feature-rich and has a kramdown emulation profile, but has been unmaintained since May 2023.

**Verdict: No degradation.**

---

#### AsciiDoc — FULL PARITY

| | Ruby | JVM |
|---|---|---|
| **Library** | asciidoctor | AsciidoctorJ |
| **Maven** | — | `org.asciidoctor:asciidoctorj:2.5.13` |
| **Last release** | — | Oct 2025 |
| **Maintenance** | Active | Active (same project) |
| **Parity** | — | **Full** (runs Ruby asciidoctor via embedded JRuby) |

AsciidoctorJ bundles JRuby internally (~30-40 MB added to artifact). First invocation has JRuby warm-up cost. This is the gold standard for AsciiDoc on JVM.

**Verdict: No degradation. Adds ~30-40 MB to WAR size.**

---

#### Textile — PARTIAL PARITY

| | Ruby | JVM |
|---|---|---|
| **Library** | RedCloth | Eclipse Mylyn WikiText (Textile module) |
| **Maven** | — | `org.eclipse.mylyn.docs:org.eclipse.mylyn.wikitext.textile:3.0.48` |
| **Last release** | — | 2023 (Maven Central); 4.7.0 in Eclipse p2 (Mar 2025) |
| **Maintenance** | Active | Active (Eclipse project) |
| **Parity** | — | **Partial** |

Covers core Textile syntax (headings, bold, italic, links, lists, tables, block quotes). May miss some RedCloth-specific extensions.

**Verdict: Minor degradation for advanced Textile features.**

---

#### MediaWiki — PARTIAL PARITY

| | Ruby | JVM |
|---|---|---|
| **Library** | wikicloth | Eclipse Mylyn WikiText (MediaWiki module) |
| **Maven** | — | `org.eclipse.mylyn.docs:org.eclipse.mylyn.wikitext.mediawiki:3.0.48` |
| **Last release** | — | 2023 (Maven Central) |
| **Maintenance** | Active | Active (Eclipse project) |
| **Parity** | — | **Partial** |

Handles core MediaWiki markup (headings, links, lists, tables, bold/italic, basic templates). Does NOT support full template expansion, Lua modules, or parser functions. Alternative: Sweble Wikitext Parser (academic, more complete grammar, uncertain maintenance).

**Verdict: Degradation for complex MediaWiki pages with templates/transclusion.**

---

#### Org-mode — SIGNIFICANT DEGRADATION

| | Ruby | JVM |
|---|---|---|
| **Library** | org-ruby | org-java (orgzly) |
| **Maven** | — | `com.orgzly:org-java:1.2.3` |
| **Last release** | — | Unknown (low activity) |
| **Maintenance** | Active | Low / community fork |
| **Parity** | — | **Partial — no HTML rendering** |

org-java is a parser/generator, not a renderer. It parses Org document structure (headings, tags, timestamps, properties) but does not produce HTML output. Would need custom rendering logic built on top.

Alternatives: pmiddend/org-parser (Kotlin, attempting comprehensive parsing), spacecowboy/orgparser (Java), 200ok-ch/org-parser (Clojure/JVM). None produce HTML comparable to org-ruby.

**Verdict: Major degradation. Requires significant custom rendering work or JRuby fallback.**

---

#### reStructuredText (RST) — NO JVM LIBRARY

| | Ruby | JVM |
|---|---|---|
| **Library** | Shells out to Python docutils | JRst (abandoned) |
| **Maven** | — | Not on Maven Central |
| **Last release** | — | Last commit 3+ years ago |
| **Maintenance** | N/A (subprocess) | Abandoned |
| **Parity** | — | **Minimal** |

JRst generates XML from RST then transforms via XSLT. Unlikely to handle all RST directives. Note: Ruby already shells out to Python for this format, so shelling out from Kotlin is the same approach.

**Verdict: Must shell out to Python `docutils` (same as Ruby does). No pure-JVM option.**

---

#### Creole — FULL PARITY

| | Ruby | JVM |
|---|---|---|
| **Library** | creole gem | Eclipse Mylyn WikiText (Creole module) |
| **Maven** | — | `org.eclipse.mylyn.docs:org.eclipse.mylyn.wikitext.creole:3.0.48` |
| **Last release** | — | 2023 (Maven Central) |
| **Maintenance** | Active | Active (Eclipse project) |
| **Parity** | — | **Full** |

Creole 1.0 is a simple spec and WikiText covers it completely.

**Verdict: No degradation.**

---

#### RDoc — NO JVM LIBRARY

| | Ruby | JVM |
|---|---|---|
| **Library** | rdoc gem (Ruby stdlib) | None |
| **Parity** | — | **None** |

RDoc is deeply Ruby-specific. No one has ported its markup parser to another language.

**Verdict: Lost entirely without JRuby. Must use JRuby to run the `rdoc` gem directly.**

---

#### Pod (Perl) — NO JVM LIBRARY

| | Ruby | JVM |
|---|---|---|
| **Library** | Shells out to `pod2html` | None |
| **Parity** | — | **None** |

Pod is Perl-specific with no demand outside the Perl ecosystem. Ruby already shells out to `pod2html`.

**Verdict: Must shell out to `pod2html` (same as Ruby does). Requires Perl on the host.**

---

#### BibTeX — FULL PARITY

| | Ruby | JVM |
|---|---|---|
| **Library** | bibtex-ruby | JBibTeX |
| **Maven** | — | `org.jbibtex:jbibtex:1.0.20` |
| **Last release** | — | March 2022 |
| **Maintenance** | Stable | Stable (BibTeX format doesn't change) |
| **Parity** | — | **Full** |

Parses BibTeX databases, resolves string constants and crossref fields, includes LaTeX-to-plaintext converter.

**Verdict: No degradation.**

---

#### PlainText — TRIVIAL

Wrap in `<pre>` tags. No library needed.

**Verdict: No degradation.**

---

### Summary: Pure Kotlin Conversion

| Format | JVM Library | Parity | Status |
|--------|-------------|--------|--------|
| **Markdown/GFM** | commonmark-java | **Full** | No loss |
| **AsciiDoc** | AsciidoctorJ | **Full** | No loss (bundles JRuby internally) |
| **Creole** | Mylyn WikiText | **Full** | No loss |
| **BibTeX** | JBibTeX | **Full** | No loss |
| **PlainText** | N/A | **Full** | No loss |
| **Textile** | Mylyn WikiText | **Partial** | Minor edge-case differences |
| **MediaWiki** | Mylyn WikiText | **Partial** | Template expansion lost |
| **Org-mode** | org-java | **Partial** | No HTML renderer — needs custom work or JRuby |
| **RST** | None | **None** | Must shell out to Python docutils |
| **RDoc** | None | **None** | Lost entirely without JRuby |
| **Pod** | None | **None** | Must shell out to pod2html (Perl) |

**5 formats at full parity, 3 degraded, 3 require external tools or JRuby.**

---

## What Changes If We Use JRuby to Run gollum-lib

### Architecture: Kotlin + Embedded JRuby Hybrid

Instead of rewriting gollum-lib, embed JRuby in the Kotlin application and call gollum-lib directly via JRuby's `ScriptingContainer` API (JSR-223). Kotlin compiles to JVM bytecode, so JRuby interop works identically to Java — no special bridge needed.

### What You Gain

- **100% markup format parity** — All 11 formats work exactly as they do today, using the same Ruby gems
- **All gollum-lib logic preserved** — Wiki link resolution, tag parsing, metadata extraction, sidebar/header/footer handling, redirect management, search — none of this needs reimplementation
- **Dramatically reduced scope** — The conversion becomes purely a web-layer rewrite (Sinatra → Ktor, ~750 LOC of routes + ~1,240 LOC of views)
- **Proven pattern** — AsciidoctorJ already does exactly this (wraps Ruby asciidoctor via embedded JRuby)

### What You Pay

#### WAR Size
- JRuby core adds ~50-80 MB to the WAR
- gollum-lib + all Ruby gem dependencies add another ~30-50 MB
- **Total WAR: ~100-150 MB** (vs. current ~80-100 MB, vs. pure Kotlin ~30-50 MB)

#### Startup Time
- JRuby warm-up is significant (several seconds on first request)
- JRuby 10 (April 2025) mitigates this with Application Class Data Store (ACDS) on Java 21, reportedly halving startup time
- Subsequent requests are fast — JRuby with invokedynamic can match or exceed MRI Ruby performance

#### Memory
- JRuby adds ~100-200 MB baseline heap usage for the Ruby runtime
- Total memory footprint: ~300-500 MB (vs. ~100-200 MB for pure Kotlin)

#### Complexity
- Two language runtimes in one process (Kotlin + JRuby)
- Debugging spans two worlds — Kotlin stack traces may include JRuby frames
- Dependency management across two ecosystems (Gradle + Bundler)
- JRuby version pinning and compatibility tracking

#### Marshalling Overhead
- Data crossing the Kotlin↔JRuby boundary must be converted (Ruby Hash → Kotlin Map, etc.)
- For render-heavy workloads, this is negligible (input: string, output: HTML string)
- For metadata-heavy operations (page listings, search results), may need careful object mapping

### Hybrid Strategy: Best of Both Worlds

Use native JVM libraries for the high-quality formats, JRuby only for the long tail:

| Format | Strategy | Library |
|--------|----------|---------|
| **Markdown/GFM** | Native JVM | commonmark-java |
| **AsciiDoc** | Native JVM (already uses JRuby internally) | AsciidoctorJ |
| **Creole** | Native JVM | Mylyn WikiText |
| **BibTeX** | Native JVM | JBibTeX |
| **PlainText** | Native JVM | Trivial |
| **Textile** | Native JVM (accept minor gaps) | Mylyn WikiText |
| **MediaWiki** | Native JVM (accept template gaps) | Mylyn WikiText |
| **Org-mode** | JRuby fallback | org-ruby via JRuby |
| **RST** | Shell out to Python | docutils (same as Ruby) |
| **RDoc** | JRuby fallback | rdoc gem via JRuby |
| **Pod** | Shell out to Perl | pod2html (same as Ruby) |

This gives 7 formats running natively on the JVM (fast, no JRuby overhead) and 2 falling back to JRuby (only loaded if those formats are actually used). RST and Pod shell out to external tools regardless.

### Decision Matrix

| Approach | Markup Parity | WAR Size | Startup | Memory | Rewrite Scope | Maintenance |
|----------|--------------|----------|---------|--------|---------------|-------------|
| **Pure Kotlin** | 5 full, 3 partial, 3 lost | ~30-50 MB | Fast | Low | Very High (rewrite gollum-lib) | Own everything |
| **Kotlin + JRuby for gollum-lib** | 100% | ~100-150 MB | Slow first request | High | Low (web layer only) | Track gollum-lib updates |
| **Kotlin + JRuby hybrid** | 9 full, 2 partial | ~80-120 MB | Medium (JRuby lazy-loaded) | Medium | Medium | Mixed ownership |

---

## Bottom Line

The **web layer conversion is straightforward** — Sinatra-to-Ktor is a clean mapping, and the templates can be reused. The **hard part is reimplementing gollum-lib** (the wiki engine core), which is a separate, larger codebase. If Phase 1 is scoped to Markdown-only with basic page CRUD/history, a working prototype is achievable relatively quickly. Full feature parity with all 10+ markup formats would be a substantially larger undertaking.

The **JRuby hybrid approach** offers the most pragmatic path: rewrite the web layer in Kotlin for clean architecture, use native JVM libraries for the 7 formats that have good coverage, and lazy-load JRuby only for the 2 niche formats (Org-mode, RDoc) that have no JVM equivalent. RST and Pod already shell out to external tools in the Ruby version, so that behavior is unchanged.

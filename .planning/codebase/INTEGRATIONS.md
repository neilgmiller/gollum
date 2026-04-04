# External Integrations

**Analysis Date:** 2026-04-02

## APIs & External Services

**Content Rendering:**
- github-markup - Multi-format document rendering support
  - Package: `github-markup` 4.0.2
  - Purpose: Supports rendering of various markup formats (Markdown, AsciiDoc, Textile, Org, etc.)
  - No auth required

**User Avatar Display:**
- Gravatar - Email-based avatar service (optional)
  - Integration: MD5 hash of user email for Gravatar URL construction
  - Location: `lib/gollum/views/has_user_icons.rb`
  - Pattern: Users can set `user_icons: 'gravatar'` wiki option

- Identicon - Generated avatar fallback (optional)
  - Integration: Built-in generation via MD5 hashing
  - Location: `lib/gollum/templates/history_authors/identicon.mustache`
  - Pattern: Users can set `user_icons: 'identicon'` wiki option

**Emoji Rendering:**
- gemojione 4.3.3 - Emoji data and rendering
  - Purpose: Provides emoji assets and rendering for wiki content
  - Endpoint: `/gollum/emoji/:name` - Serves emoji PNG images
  - No external API calls (local emoji set)

**Icons:**
- Octicons 19.23.1 - GitHub Octicons SVG library
  - Purpose: UI icons for wiki interface
  - Endpoint: `/gollum/octicon/:name` - Serves SVG icons
  - Package: octicons gem
  - Location: Used in `lib/gollum/assets.rb` for icon helpers

## Data Storage

**Primary Repository:**
- Git (local filesystem)
  - Connection: Via gollum-lib, file system path
  - Client: gollum-lib with rjgit adapter (JRuby) or libgit2 (MRI)
  - Configuration: `GOLLUM_PATH` environment variable points to repository location
  - Default: Current working directory if GOLLUM_PATH not set
  - Access: Read-write for page editing, version history, file uploads

**Page Storage:**
- Local filesystem (within Git repository)
  - Supported formats: Markdown, AsciiDoc, Textile, Org, RDoc, Creole, PlainText, MediaWiki, POD, BibTeX
  - Upload directory: `uploads/` (configurable as `per_page_uploads`)
  - Max file size: 190MB (set via `Gollum::set_git_max_filesize(190 * 10**6)`)
  - Location: `lib/gollum/app.rb` lines 37-38

**File Storage:**
- Local filesystem only (no cloud storage integration)
  - Uploads stored alongside wiki pages in Git
  - Per-page uploads: Can organize uploads per page if enabled
  - Configuration: `allow_uploads` and `per_page_uploads` wiki options

**Caching:**
- None configured (direct Git operations)
- Optional: Rack-session for storing editor state

## Authentication & Identity

**Auth Provider:**
- Custom/None - No built-in authentication
- Implementation: Wiki is open by default, read/write access determined by:
  - `allow_editing` wiki option - Controls page editing capability globally
  - HTTP authentication layer (must be configured externally, e.g., reverse proxy)
  - No user database or login system

**Author Attribution:**
- Git-based: Uses Git commit author (name and email)
  - Configuration: Via session hash `session['gollum.author']` containing author info
  - Display: Author name shown in page history
  - Location: `lib/gollum/app.rb` lines 279-281

## Monitoring & Observability

**Error Tracking:**
- None configured - Application errors logged via standard Ruby mechanisms

**Logging:**
- Standard Ruby logging (Rack-based)
- Environment-dependent:
  - Development/Staging: `enable :show_exceptions, :dump_errors`
  - Test: `enable :logging, :raise_errors, :dump_errors`
  - Production: Errors logged to stderr/stdout

**Performance Monitoring:**
- None configured - No APM integration

## CI/CD & Deployment

**Hosting Platforms:**
- Docker (primary modern deployment)
  - Image: `ruby:3.3-alpine` base
  - Registry: Docker Hub (GitHub Actions builds images)

- Standalone executable WAR (Java application servers)
  - Targets: Tomcat, Jetty, WildFly, GlassFish, etc.
  - Build tool: Warbler 2.1.0
  - Java requirement: 17+

- Manual/VPS deployment
  - Direct Ruby installation
  - Systemd/OpenRC service files included
  - Location: `contrib/systemd/`, `contrib/openrc/`, `contrib/sysv-debian/`

**CI Pipeline:**
- GitHub Actions (`.github/workflows/`)
  - Primary tests: `.github/workflows/test.yaml`
    - JRuby 9.4 on Ubuntu
    - Ruby 3.2.1, 3.3, 3.4 on Ubuntu
    - Selenium integration tests (Capybara + ChromeDriver)

  - Asset precompilation: `.github/workflows/precompile-assets.yaml`

  - Docker build & test: `.github/workflows/docker-test-deploy.yml`

  - Release: `.github/workflows/release.yml`
    - Publishes to RubyGems
    - Pushes Docker image

**Build Artifacts:**
- RubyGem: Published to RubyGems.org
  - Gem file format: `gollum-{version}.gem`
  - Installation: `gem install gollum`

- WAR (Web Archive): `gollum.war`
  - Built via: `bundle exec warble runnable war`
  - Executable standalone JAR-WAR hybrid
  - Can be deployed to app servers or run directly

- Docker Image: Published to Docker Hub
  - Repository: `gollum/gollum` (or custom registry)
  - Automated builds on release

## Environment Configuration

**Required Environment Variables:**
- `GOLLUM_PATH` - Path to Git repository (default: current directory)
- `RACK_ENV` - Environment selection: production/development/test/staging (default: production)

**Optional Environment Variables:**
- None explicitly documented in code
- Configuration via wiki_options hash in `config.ru`

**Secrets Location:**
- Git authentication: Handled by Git credential system or SSH keys
- No hardcoded secrets in codebase
- Docker deployment: User SSH keys can be mounted at `/home/www-data/.ssh`
- Author info: Stored in Rack session (in-memory or session middleware)

## Webhooks & Callbacks

**Incoming:**
- None configured - Gollum does not expose webhook endpoints for external systems
- Git post-receive hooks would need to be configured externally

**Outgoing:**
- None configured - Gollum does not make outbound webhook calls
- RSS feed available at `/gollum/feed/` for content updates
  - Format: RSS 2.0
  - Content: Latest changes/commits to wiki
  - Location: `lib/gollum/app.rb` lines 164-172
  - Generated via: `lib/gollum/views/rss.rb`

## Data Format & Serialization

**REST API Responses:**
- JSON format for AJAX endpoints
  - `/gollum/last_commit_info` - Returns: `{author: string, date: ISO8601}`
  - `/gollum/data/*` - Returns raw page data
  - Location: `lib/gollum/app.rb` lines 189-220

**Content Formats:**
- Multi-markup support (determined by file extension):
  - `.md` or `.markdown` - Markdown
  - `.asciidoc` or `.adoc` - AsciiDoc
  - `.textile` - Textile
  - `.org` - Org-mode
  - `.rdoc` - RDoc
  - `.creole` - Creole
  - `.txt` or `.text` - PlainText
  - `.mediawiki` - MediaWiki syntax
  - `.pod` - POD (Perl documentation)
  - `.bib` - BibTeX

- Diagram support (via filters):
  - Mermaid diagrams: ```` ```mermaid ... ``` ````
    - Location: `lib/gollum/app.rb` line 40
    - Rendered client-side via Mermaid JS library

- Math notation:
  - KaTeX for inline/block math (optional, via `math` wiki option)
  - MathJax for LaTeX rendering (optional, via `math` wiki option)

## Third-Party Libraries (No Live Integration)

**Icon & Emoji Assets:**
- Octicons - GitHub Octicons (SVG, served locally)
- gemojione - Emoji data (served locally as PNG)

**Parsing & Rendering:**
- rouge - Syntax highlighting (integrated via gollum-lib)
- nokogiri - HTML/XML parsing (used for sanitization)
- loofah - HTML sanitization (prevents XSS in user content)
- twitter-text - Text normalization

**Build/Compilation:**
- SassC/Sass-Embedded - SCSS compilation
- Terser - JavaScript minification
- Sprockets - Asset pipeline management

---

*Integration audit: 2026-04-02*

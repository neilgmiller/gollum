# Architecture

**Analysis Date:** 2026-04-02

## Pattern Overview

**Overall:** Sinatra-based MVC web application with a modular view layer using Mustache templates. The architecture follows a traditional web framework pattern with clear separation between request handling (routes), business logic (via gollum-lib), and view rendering (Mustache).

**Key Characteristics:**
- Sinatra framework for HTTP request routing and response handling
- Mustache/Sinatra for template-based view rendering
- Modular view classes using mixins for shared behavior
- Asset pipeline managed through Sprockets
- Rack-based middleware support for extensibility
- Wiki core logic delegated to external `gollum-lib` gem

## Layers

**Request/Route Layer (Controllers):**
- Purpose: Handle HTTP requests, parse parameters, delegate to wiki operations, prepare data for views
- Location: `lib/gollum/app.rb` (747 lines, main application)
- Contains: Sinatra route handlers (GET/POST), error handling, session management
- Depends on: Sinatra, gollum-lib, Rack, view classes
- Used by: HTTP clients, browsers

**View/Presentation Layer:**
- Purpose: Render HTML templates with wiki content and UI elements
- Location: `lib/gollum/views/` (multiple specialized view classes)
- Contains:
  - `Layout` base class (`layout.rb`) - inherits from Mustache, includes helper mixins
  - Feature-specific views: `Page`, `Edit`, `Create`, `History`, `Compare`, `Search`, `Overview`, `RSSView`
  - Concern mixins: `HasPage`, `HasMath`, `HasUserIcons`, `Editable`, `Pagination`
  - Helper mixins: `AppHelpers`, `RouteHelpers`, `OcticonHelpers`, `SprocketsHelpers`, `LocaleHelpers`
- Depends on: Mustache, Sprockets, Nokogiri (for HTML parsing), assets
- Used by: Route handlers for template rendering

**Data/Business Logic Layer:**
- Purpose: Core wiki operations (page reading, writing, history, search)
- Location: External dependency `gollum-lib` gem
- Contains: Wiki, Page, Committer, Repository abstractions
- Depends on: Git libraries (rugged or rjgit), Gollum::Markup for content rendering
- Used by: Route handlers in app.rb

**Asset/Static Resources:**
- Purpose: JavaScript, CSS, and static assets for frontend
- Location: `lib/gollum/public/` (MathJax, editor libraries, stylesheets)
- Contains: JavaScript (editor, behaviors, MathJax), SCSS stylesheets, fonts, emoji
- Managed by: Sprockets asset pipeline
- Served via: `/gollum/assets/*` routes

**Template Layer:**
- Purpose: Mustache templates for HTML rendering
- Location: `lib/gollum/templates/` (.mustache files)
- Contains: layout.mustache (base template), page.mustache, edit.mustache, history.mustache, etc.
- Rendered by: View classes extending Layout

## Data Flow

**Page View (Read):**

1. GET request to `/*` hits catch-all route in `app.rb`
2. Route calls `show_page_or_file(fullpath)`
3. Function queries `wiki.page(fullpath)` via gollum-lib
4. If page exists:
   - Populates instance variables (@page, @content, @toc_content, @editable)
   - Renders via `mustache :page` (invokes Page view class)
5. Page view class processes template with instance variables
6. Mustache template renders HTML with breadcrumbs, sidebar, TOC, formatted content
7. Response sent to client

**Page Edit/Create:**

1. GET `/gollum/edit/*` or `/gollum/create/*` - route checks edit permissions
2. Route populates form data (page content, format, upload destination)
3. Renders edit.mustache or create.mustache view
4. User submits form to POST `/gollum/edit/*` or POST `/gollum/create`
5. Route extracts params, creates Committer, calls wiki operation
6. wiki.update_page() or wiki.write_page() creates git commit
7. Redirect to newly saved page

**State Management:**
- Session state: `session['gollum.author']` and `session['gollum.note']` stored in Rack session
- Wiki state: Transient - wiki instance created per-request via `wiki_new()`
- Page state: Immutable - pages fetched from git via gollum-lib on demand
- Configuration state: Settings via Sinatra `set()` - stored in app environment

## Key Abstractions

**WikiPage (OpenStruct):**
- Purpose: Wraps wiki page metadata and gollum-lib Page object
- Implementation: `wiki_page()` helper returns OpenStruct with :wiki, :page, :name, :path, :ext, :fullname, :fullpath
- Pattern: Simple wrapper for convenient access during request handling

**View Hierarchy:**
- `Layout` (base) → inherits from `Mustache` and includes multiple helper mixins
- Specialized views (`Page`, `Edit`, `History`, etc.) → inherit from `Layout`
- Mixins inject route generation, locale handling, asset paths, page data access

**Helper Mixins (Composition over Inheritance):**
- `HasPage` - provides page URL/format/ID accessors
- `HasMath` - math rendering configuration
- `HasUserIcons` - user avatar handling
- `Editable` - edit state and permission checks
- `Pagination` - pagination logic helpers
- `AppHelpers` - page directory extraction for custom file paths
- `RouteHelpers` - dynamic route path generation (gollum_path, history_path, etc.)
- `OcticonHelpers` - SVG icon rendering
- `SprocketsHelpers` - asset tag generation
- `LocaleHelpers` - internationalization

## Entry Points

**bin/gollum (Command-line):**
- Location: `bin/gollum` executable
- Triggers: User runs `gollum [git-repo]` from command line
- Responsibilities: Parse options, configure wiki settings, launch WEBrick server with Precious::App

**config.ru (Rack):**
- Location: `config.ru`
- Triggers: Used in WAR deployment or rackup server
- Responsibilities: Load Precious::App, set environment, configure wiki options, mount as Rack application

**Precious::App (Sinatra Application):**
- Location: `lib/gollum/app.rb`
- Triggers: HTTP requests to mounted Rack application
- Responsibilities: Route requests, authenticate/authorize, call wiki operations, render views

**Precious::MapGollum (Path Mapping):**
- Location: `lib/gollum/app.rb` (MapGollum class)
- Triggers: When base-path option is used
- Responsibilities: Map wiki to a base path and redirect root traffic to that path

## Error Handling

**Strategy:** Defensive routing with fallback error views

**Patterns:**
- 404 Not Found: `not_found()` helper renders error.mustache view
- 403 Forbidden: `forbid()` helper for permission checks (edit mode, resource protection)
- 412 Conflict: Edit collision detection - returns ETag mismatch with latest SHA and content
- 409 Conflict: Duplicate page/file error returns message
- Server Errors: `halt` with error responses for invalid operations
- Missing Pages: Redirect to create form if allow_editing, else show 404

## Cross-Cutting Concerns

**Logging:** Sinatra built-in logging (configurable by environment)

**Validation:**
- URL path validation: `clean_url()` normalizes slashes and escaping
- Page name validation: `Gollum::Page.valid_extension?()` for file formats
- Permission validation: `forbid()` checks @allow_editing flag before POST/PUT/DELETE
- Path traversal protection: `Pathname.cleanpath()` and directory checks for relative paths

**Authentication:**
- Session-based: `session['gollum.author']` and `session['gollum.note']` populated by middleware (external)
- No built-in auth - delegate to Rack middleware (e.g., Basic Auth, OAuth wrappers)
- Per-request access to author via commit_options helper

**Internationalization:**
- i18n gem for locale management
- Supported locales: `:en`, `:cn`
- View access via LocaleHelpers mixin: `t[:key]` accessor
- Default locale: `:en`
- Locale files: `lib/gollum/locales/{cn,en}.yml`

---

*Architecture analysis: 2026-04-02*

# Codebase Structure

**Analysis Date:** 2026-04-02

## Directory Layout

```
gollum/
├── bin/                           # Executable entry points
│   ├── gollum                     # Main CLI launcher
│   └── gollum-migrate-tags        # Migration utility
├── lib/                           # Main source code
│   └── gollum/
│       ├── app.rb                 # Sinatra application, route handlers
│       ├── helpers.rb             # Helper utilities (emoji, path handling)
│       ├── assets.rb              # Asset pipeline configuration
│       ├── uri_encode_component.rb # URI encoding utility
│       ├── views/                 # View classes for template rendering
│       │   ├── layout.rb          # Base view class (extends Mustache)
│       │   ├── page.rb            # Page display view
│       │   ├── edit.rb            # Page edit form view
│       │   ├── create.rb          # Page create form view
│       │   ├── history.rb         # Page history/versions view
│       │   ├── compare.rb         # Diff comparison view
│       │   ├── search.rb          # Search results view
│       │   ├── overview.rb        # Wiki directory tree view
│       │   ├── latest_changes.rb  # Recent changes view
│       │   ├── commit.rb          # Commit detail view
│       │   ├── rss.rb             # RSS feed view
│       │   ├── error.rb           # Error page view
│       │   ├── editable.rb        # Edit permission mixin
│       │   ├── has_page.rb        # Page data mixin
│       │   ├── has_math.rb        # Math rendering mixin
│       │   ├── has_user_icons.rb  # User avatar mixin
│       │   ├── pagination.rb      # Pagination mixin
│       │   ├── template_cascade.rb # Custom template loading
│       │   └── helpers/           # Helper modules for views
│       │       ├── locale_helpers.rb  # Internationalization
│       │       └── (defined in helpers.rb: AppHelpers, RouteHelpers, etc.)
│       ├── templates/             # Mustache template files (.mustache)
│       │   ├── layout.mustache    # Base HTML structure
│       │   ├── page.mustache      # Page display template
│       │   ├── edit.mustache      # Edit form template
│       │   ├── create.mustache    # Create form template
│       │   ├── history.mustache   # History view template
│       │   ├── compare.mustache   # Diff display template
│       │   ├── search.mustache    # Search results template
│       │   ├── overview.mustache  # Directory listing template
│       │   ├── latest_changes.mustache # Recent changes template
│       │   ├── commit.mustache    # Commit detail template
│       │   ├── error.mustache     # Error page template
│       │   ├── navbar.mustache    # Navigation bar template
│       │   ├── mobilenav.mustache # Mobile nav template
│       │   ├── searchbar.mustache # Search form template
│       │   ├── wiki_content.mustache # Content wrapper
│       │   ├── editor.mustache    # Editor UI template
│       │   ├── pagination.mustache # Pagination controls
│       │   └── history_authors/   # User avatar templates
│       ├── public/                # Static assets (compiled/served)
│       │   ├── assets/            # Sprockets-compiled CSS/JS
│       │   │   └── katex/         # KaTeX math library
│       │   └── gollum/            # Gollum-specific assets
│       │       ├── javascript/    # JavaScript source
│       │       │   ├── MathJax/   # MathJax library
│       │       │   ├── editor/    # Editor plugins and language modes
│       │       │   ├── app.js     # Main app initialization
│       │       │   ├── editor.js  # Editor interface
│       │       │   ├── gollum.*.js# Feature modules (behaviors, dialogs, etc.)
│       │       │   ├── jquery-1.9.1.min.js # jQuery dependency
│       │       │   ├── polyfills.js
│       │       │   ├── identicon.js
│       │       │   └── clipboard.min.js
│       │       └── stylesheets/   # SCSS source files
│       │           ├── app.scss   # Main stylesheet
│       │           ├── editor.scss
│       │           ├── template.scss.erb  # Customizable template styles
│       │           ├── wiki_content.scss # Content styling
│       │           ├── dialog.scss
│       │           ├── emoji.scss
│       │           ├── highlights.scss
│       │           ├── tables.scss
│       │           ├── criticmarkup.scss
│       │           ├── print.scss
│       │           └── _*.scss    # SCSS partials
│       └── locales/               # i18n translation files
│           ├── en.yml            # English translations
│           └── cn.yml            # Chinese translations
├── test/                          # Test suite
│   ├── test_app.rb               # App route tests
│   ├── test_app_helpers.rb       # Helper function tests
│   ├── test_page_view.rb         # Page view tests
│   ├── test_history_view.rb      # History view tests
│   ├── test_compare.rb           # Compare view tests
│   ├── test_overview_view.rb     # Overview view tests
│   ├── test_latest_changes_view.rb # Latest changes tests
│   ├── test_rss_view.rb          # RSS feed tests
│   ├── test_template_cascade.rb  # Template loading tests
│   ├── test_migrate.rb           # Migration tool tests
│   ├── test_local_time_option.rb # Locale/time handling tests
│   ├── helper.rb                 # Test setup and utilities
│   ├── capybara_helper.rb        # Browser automation setup
│   ├── integration/              # Integration/E2E tests
│   │   ├── test_app.rb           # Full app workflow tests
│   │   ├── test_page.rb          # Page operations tests
│   │   ├── test_editor.rb        # Editor UI tests
│   │   ├── test_search.rb        # Search functionality tests
│   │   ├── test_localization.rb  # i18n tests
│   │   └── test_js_errors.rb     # JavaScript error detection
│   ├── examples/                 # Test git repositories
│   │   └── *.git                 # Various test repo structures
│   ├── gollum/                   # Unit tests for view helpers
│   │   └── views/
│   │       └── test_locale_helper.rb
│   └── support/                  # Test support utilities
├── config/                        # Configuration files
│   └── (environment-specific configs)
├── contrib/                       # Deployment/system integration
│   ├── automation/               # Automation scripts
│   ├── openrc/                   # OpenRC init scripts
│   ├── systemd/                  # Systemd service files
│   └── sysv-debian/              # Debian init scripts
├── docs/                          # Documentation and guides
├── config.rb                      # Sprockets/asset config
├── config.ru                      # Rack configuration entry point
├── Rakefile                       # Build/deployment rake tasks
├── Gemfile                        # Ruby gem dependencies
├── gollum.gemspec                 # Gem specification
├── package.json                   # JavaScript package info
├── Dockerfile                     # Container definition
├── docker-run.sh                  # Docker startup script
└── README.md                      # Project documentation
```

## Directory Purposes

**bin/:**
- Purpose: Executable entry points for end users
- Contains: CLI launcher scripts
- Key files: `bin/gollum` (main entry), `bin/gollum-migrate-tags` (migration tool)

**lib/gollum/:**
- Purpose: Main application source code
- Contains: Sinatra app, views, helpers, assets, templates
- Core file: `app.rb` (747 lines - all route handlers)

**lib/gollum/views/:**
- Purpose: View classes that render Mustache templates
- Contains: Layout hierarchy, feature-specific views, helper mixins
- Pattern: Each view class corresponds to a template file

**lib/gollum/templates/:**
- Purpose: Mustache template files (.mustache) for HTML rendering
- Contains: HTML structure, form templates, layout wrappers
- Pattern: Named to match view classes (e.g., page.rb → page.mustache)

**lib/gollum/public/:**
- Purpose: Static assets served to browsers
- Contains: JavaScript, CSS, fonts, MathJax, editor libraries
- Management: Asset pipeline via Sprockets compiles/fingerprints assets
- Served via: `/gollum/assets/*` routes in app.rb

**test/:**
- Purpose: Automated test suite
- Contains: Unit tests (views, helpers), integration tests (full workflows)
- Framework: Minitest with Shoulda, Mocha for mocking, Capybara for browser tests
- Test setup: `helper.rb` provides shared fixtures and utilities

**config/, contrib/, docs/:**
- Purpose: Non-code resources (deployment configs, docs, system integration)
- Uses: Referenced in deployment pipelines, not core to runtime

## Key File Locations

**Entry Points:**
- `bin/gollum`: Command-line launcher - parses options, starts server
- `config.ru`: Rack/WAR entry - loads app, sets environment
- `lib/gollum/app.rb`: Sinatra app - all route handlers

**Configuration:**
- `Gemfile` / `gollum.gemspec`: Dependency declarations
- `config.rb`: Sprockets asset pipeline setup
- `lib/gollum.rb`: Module initialization, i18n setup, version

**Core Logic:**
- `lib/gollum/app.rb`: Route handlers (747 lines)
  - Routes: GET/POST for viewing, editing, creating, deleting, reverting pages
  - Routes: Asset serving, search, history, compare, RSS feed
  - Routes: File upload, rename, create operations
  - Private helpers: `wiki_page()`, `wiki_new()`, `commit_options()`, `show_page_or_file()`
- `lib/gollum-lib` (external gem): Page, Wiki, Markup, Repository abstractions

**Testing:**
- `test/helper.rb`: Shared setup - test environment, Rack::Test, fixture utilities
- `test/test_app.rb`: Route handler tests (GET/POST)
- `test/integration/test_app.rb`: Full workflow integration tests
- `test/examples/`: Git repositories for test fixtures

## Naming Conventions

**Files:**
- View classes: `snake_case.rb` (e.g., `has_page.rb`, `latest_changes.rb`)
- Templates: `snake_case.mustache` (e.g., `page.mustache`, `edit.mustache`)
- Mixins: `has_*.rb` (e.g., `has_page.rb`, `has_math.rb`)
- Tests: `test_*.rb` (e.g., `test_app.rb`, `test_page_view.rb`)
- Stylesheets: `snake_case.scss` (e.g., `app.scss`, `editor.scss`)
- JavaScript: `snake_case.js` with `gollum.*` prefix for feature modules (e.g., `gollum.behaviors.js`)

**Directories:**
- Feature folders: `snake_case` (e.g., `views/`, `templates/`, `public/`)
- Nested features: `snake_case/` (e.g., `javascript/editor/`, `stylesheets/`)
- Test structure mirrors source: `test/gollum/views/` mirrors `lib/gollum/views/`

**Classes/Modules:**
- View classes: `PascalCase` (e.g., `Page`, `Edit`, `History`)
- Modules (mixins): `PascalCase` or short names (e.g., `HasPage`, `Editable`)
- Precious namespace for frontend: `module Precious` and `module Precious::Views`
- Gollum namespace for core: `module Gollum` (in gollum-lib)

## Where to Add New Code

**New Feature (New Page Type):**
- View class: `lib/gollum/views/feature_name.rb` - inherit from `Layout`
- Template: `lib/gollum/templates/feature_name.mustache` - HTML structure
- Routes: Add GET/POST handlers in `lib/gollum/app.rb`
- Tests: `test/test_feature_name.rb` or `test/integration/test_feature_name.rb`

**New Component/Widget:**
- Template partial: `lib/gollum/templates/_component_name.mustache`
- View helper: Add method to appropriate view class or mixin
- Styles: `lib/gollum/public/gollum/stylesheets/_component_name.scss`
- JavaScript: `lib/gollum/public/gollum/javascript/gollum.component_name.js`

**Utilities/Helpers:**
- Shared helpers: `lib/gollum/helpers.rb` (path utilities, emoji, encoding)
- View helpers: `lib/gollum/views/helpers.rb` (route generation, icon rendering)
- View concerns: `lib/gollum/views/has_*.rb` or `lib/gollum/views/*able.rb`

**Styles/Assets:**
- Compiled assets: Sprockets compiles from `lib/gollum/public/gollum/stylesheets/`
- Source: SCSS files in `lib/gollum/public/gollum/stylesheets/`
- Import order: Base → Features → App (see app.scss)

**Tests:**
- Unit tests: `test/test_*.rb` (test view classes, helpers in isolation)
- Integration: `test/integration/test_*.rb` (test full request/response flow)
- Test fixtures: `test/examples/` (git repos), populated via `cloned_testpath()` helper

## Special Directories

**lib/gollum/public/gollum/javascript/MathJax/:**
- Purpose: MathJax library for mathematical notation rendering
- Generated: Yes - downloaded/vendored as part of build
- Committed: Yes - included in gem
- Size: Large (~50 MB+ uncompressed) - contains many language/font files

**lib/gollum/locales/:**
- Purpose: i18n translation files
- Generated: No
- Committed: Yes
- Format: YAML files (en.yml, cn.yml)
- Usage: Loaded by i18n at startup, accessed via `t[:key]` in views

**test/examples/:**
- Purpose: Test git repositories with various wiki structures
- Generated: No (static fixtures)
- Committed: Yes
- Usage: Cloned into temp directories by `cloned_testpath()` helper for isolation

**lib/gollum/public/assets/:**
- Purpose: Compiled Sprockets output (fingerprinted CSS/JS)
- Generated: Yes - compiled by Sprockets on first request or pre-compiled
- Committed: Depends on deployment (pre-compiled for production)
- Path: Referenced via Sprockets::Helpers in templates

---

*Structure analysis: 2026-04-02*

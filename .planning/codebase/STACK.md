# Technology Stack

**Analysis Date:** 2026-04-02

## Languages

**Primary:**
- Ruby 3.2.1+ (MRI) - Main application framework and backend
- JRuby 9.4.9 - Java-compatible Ruby runtime for WAR deployment
- JavaScript - Frontend interactivity and asset pipeline
- SCSS - Styling via asset pipeline
- Mustache/ERB - Server-side templating

**Secondary:**
- HTML/CSS - Frontend markup and styling
- JSON - Data serialization and API responses

## Runtime

**Environment:**
- Ruby 3.2.1, 3.3, 3.4 (MRI - primary development)
- JRuby 9.4.9 (WAR executable, Java/application server deployment)
- Node.js 16.15.0+ (for asset pipeline via Yarn)

**Package Managers:**
- Bundler (Ruby gem manager) - Primary dependency management
  - Lockfile: `Gemfile.lock` (present)
- Yarn (Node.js) - Frontend dependency management
  - Lockfile: `yarn.lock` (present)

## Frameworks

**Core:**
- Sinatra 4.2.1 - Lightweight Ruby web framework
- Rack 3.2.6 - HTTP application interface
- Rackup 2.3.1 - Rack application server launcher

**View/Templating:**
- Mustache-Sinatra 2.0.0 - Logic-less templating with Sinatra integration
- Mustache 1.1.2 - Template rendering engine

**Asset Pipeline:**
- Sprockets 4.2.2 - Asset packaging, minification, and preprocessing
- Sprockets-Helpers 1.4.0 - Helpers for asset path resolution
- Terser 1.2.7 - JavaScript minification

**Content Processing:**
- gollum-lib 6.1.0 - Core wiki functionality, Markdown parsing, Git integration
- github-markup 4.0.2 - Multi-format document rendering
- kramdown 2.5.2 - Markdown processor
- kramdown-parser-gfm 1.1.0 - GitHub-flavored Markdown parser
- rouge 3.30.0 - Syntax highlighting for code blocks
- loofah 2.25.1 - HTML/XML processing, sanitization
- nokogiri 1.18.10 - XML/HTML parsing

**Styling/JavaScript Processing:**
- sassc-embedded 1.80.8 - SCSS compilation
- sass-embedded 1.98.0 - SASS compilation
- therubyrhino 2.1.2 - JavaScript runtime (Rhino engine for JRuby)

**Testing:**
- Minitest 5.27.0 - Test framework
- Shoulda 3.6.0 - Testing DSL and matchers
- Mocha 2.8.2 - Mocking and stubbing
- Test-Unit 3.3.9 - Unit testing framework
- Capybara 3.40.0 - Integration testing, browser automation
- Selenium-WebDriver 4.1.0 - Browser automation
- Rack-Test 0.6.3 - HTTP request testing

**Build/Packaging:**
- Rake 13.3.1 - Task automation
- Warbler 2.1.0 - WAR (Web Archive) packaging for JRuby
- jruby-jars 9.4.14.0 - JRuby JAR files
- jruby-rack 1.2.6 - Rack support for JRuby servlet containers

## Key Dependencies

**Critical:**
- gollum-lib 6.1.0 - Provides core wiki engine, Git integration, page management
- gollum-rjgit_adapter 2.0 - Git operations adapter using RJGit for JRuby
- rjgit 6.8.0 - JRuby-based Git library
- Sinatra 4.2.1 - Web framework routing and request handling
- Rack 3.2.6+ - MUST be >= 3.0 per gemspec requirements

**Text & Markup:**
- twitter-text 1.14.7 - Text processing and parsing
- gemojione 4.3.3 - Emoji rendering and data
- octicons 19.23.1 - GitHub Octicons SVG library
- rdoc 6.17.0 - Ruby documentation generator

**Infrastructure:**
- Webrick 1.9.2 - HTTP server
- i18n 1.14.8 - Internationalization (supported locales: en, cn)
- useragent 0.16.11 - User-Agent string parsing
- rss 0.3.2 - RSS feed generation

**Development Only:**
- minitest-reporters 1.3.8 - Minitest output formatting
- sassc-embedded 1.80.8+ - SCSS compilation during development
- google-protobuf 4.34.1 - Protocol Buffers (force_ruby_platform workaround for musl systems)

## Configuration

**Environment:**
- Development: Ruby with live asset reloading, detailed error pages
- Production: Precompiled static assets, minified JavaScript/CSS
- Test: Minitest runner with integration tests via Capybara
- Staging: Configured via Sinatra environment variable
- gollum_development: Special mode with dynamic Sprockets compilation

**Build Configuration:**
- `Rakefile` - Build tasks: test, precompile, release, coverage
- `config.rb` - Ruby configuration for the application
- `config.ru` - Rack configuration file for server launch
  - GOLLUM_PATH environment variable: Points to wiki Git repository (defaults to working directory)
  - RACK_ENV: Selects environment (defaults to production)
  - Wiki options set via Precious::App.set(:wiki_options, {...})

**Key Wiki Options:**
- allow_editing: Enable/disable page editing (default: true)
- allow_uploads: Enable/disable file uploads (default: false in config.ru)
- wiki_options.title: Wiki title display
- wiki_options.static: Use static precompiled assets (default: true except in gollum_development)
- wiki_options.base_path: Base URL path for the wiki
- math: Enable mathematical notation support
- mermaid: Enable diagram rendering (default: true)

## Deployment Modes

**Standalone:**
- Direct Ruby execution via `gollum` command-line tool
- Rack server (Rackup/Puma/WEBrick)
- Serves from local Git repository

**WAR (Web Archive) - Java Application Servers:**
- Built via Warbler 2.1.0
- Targets JRuby 9.4+
- Deployable to: Tomcat, Jetty, WildFly, etc.
- Environment: Java 17+
- Created in CI/CD via `warble runnable war` command

**Docker:**
- Base image: `ruby:3.3-alpine`
- Multi-stage build (builder + runtime)
- Build tools included: build-base, cmake, git, icu-dev, openssl-dev, yaml-dev
- Runtime: Minimal Alpine Linux with bash, git, openssh, libc6-compat
- Entry point: `/docker-run.sh`
- Volume: `/wiki` for Git repository
- User: www-data (non-root)

## Platform Requirements

**Development:**
- Ruby 3.2.1+ or JRuby 9.4.9
- Bundler for dependency management
- Node.js 16.15.0+ (for JavaScript/CSS asset pipeline)
- Yarn (Node package manager)
- Git (for version control integration)
- System libraries: libyaml-dev (Linux), build tools, cmake
- Chrome/Chromedriver (for Selenium integration tests)

**Production:**
- Ruby 3.2.1+ or Java 17+ (for JRuby/WAR)
- Bundler (only if installing from source)
- Git (runtime requirement for wiki backend)
- Minimum 256MB RAM (typical), 512MB+ recommended
- Deployment targets: Docker, Application servers (Tomcat, Jetty), Linux systems, macOS

**Build Requirements (Asset Precompilation):**
- Yarn must successfully run `yarn install`
- Terser for JavaScript minification
- SassC/SassC-Embedded for SCSS compilation
- All standard development dependencies

## Version Constraints

**Ruby Version:**
- Required: >= 2.6 (per gemspec)
- Tested: 3.2.1, 3.3, 3.4 (MRI)
- JRuby: 9.4.9 (jruby-9.4.9.0 in .ruby-version)
- Node: >= 16.15.0

**Critical Gem Versions:**
- Rack: >= 3.0 (breaking change from 2.x)
- Sinatra: ~> 4.0 (latest major version)
- gollum-lib: ~> 6.0
- Kramdown: ~> 2.3
- jar-dependencies: < 0.5 (JRuby compatibility workaround for psych issue)

---

*Stack analysis: 2026-04-02*

# Warble Executable WAR — Debugging Session Notes

## Goal

Build Gollum as an executable WAR (`bundle exec warble executable war`) that starts
cleanly under `java -jar gollum.war` using JRuby + Jetty.

## Environment

| Component | Version |
|---|---|
| JRuby (dev) | 9.4.14.0 (Ruby 3.1.7) |
| Java | 21 (HotSpot, arm64) |
| Rack | 3.2.5 |
| Warbler | 2.1.0 |
| jruby-rack | 1.2.6 |
| Sprockets | 4.2.2 |

---

## Bugs Found and Fixed

### 1. Wrong JRuby version embedded in WAR

**Symptom:**
```
INFO: jruby 10.0.4.0 (3.4.5) ...
ERROR: java.lang.NullPointerException: Cannot invoke "Object.getClass()" because "self" is null
```

**Root cause:** Warbler uses the `jruby-jars` gem to embed a JRuby runtime into the
WAR. The gem `jruby-jars 10.0.4.0` was resolving because warbler's gemspec allows
`>= 9.4, < 10.1`. JRuby 10.0 uses Ruby 3.4 syntax/semantics but all bundled gems
were compiled for JRuby 9.4 / Ruby 3.1 — the mismatch caused a hard NPE during
runtime initialisation.

Additionally, the Gemfile was pointing warbler at the git source, which lacks the
Maven-built `warbler_jar.jar` required at runtime. Switched to released gem 2.1.0.

**Fix:** Pin both in Gemfile:
```ruby
gem 'warbler', '~> 2.1', platforms: :jruby
gem 'jruby-jars', '~> 9.4.9', platforms: :jruby
```
`jruby-jars` resolved to `9.4.14.0` (latest 9.4.x patch).

---

### 2. `rack/chunked` removed in Rack 3 — jruby-rack 1.2.6 loads it unconditionally

**Symptom:**
```
LoadError: no such file to load -- rack/chunked
  jruby/rack/chunked.rb:6
```

**Root cause:** `DefaultRackApplicationFactory.java` contains a hardcoded boot hook:
```java
ruby.evalScriptlet("JRuby::Rack::Booter.on_boot { require 'jruby/rack/chunked' }")
```
This is triggered when `jruby.rack.response.dechunk` is `"patch"` (the default).
`jruby/rack/chunked.rb` monkey-patches `Rack::Chunked::Body` to disable chunking on
servlets. `Rack::Chunked` was removed entirely in Rack 3 — the file no longer exists.

**Fix:** Set the init param in `config/warble.rb`:
```ruby
config.webxml['jruby.rack.response.dechunk'] = 'false'
```
With Rack 3 there is no `Rack::Chunked::Body` to patch; the dechunk behaviour is
irrelevant.

---

### 3. `=begin`/`=end` block in config.ru causes syntax error

**Symptom:**
```
SyntaxError: config.ru:1: syntax error, unexpected '='
...et.new( Rack::Builder.new { (=begin
```

**Root cause:** jruby-rack loads config.ru by wrapping it:
```ruby
Rack::Builder.new { (<config.ru contents>) }.to_app
```
Ruby's `=begin` heredoc marker is only legal at column 0 of a bare top-level line.
Inside a block expression it is a syntax error.

**Fix:** Replace `=begin`/`=end` with `#` comments in `config.ru`.

---

### 4. `config.ru` had no `run` statement (was a template)

**Symptom:**
```
RuntimeError: missing run or map statement
```

**Root cause:** The default `config.ru` shipped with Gollum is a comment template
with no `run` call. Rack::Builder requires a `run` or `map` to produce a valid app.

**Fix:** Add a proper Gollum entry point to `config.ru`:
```ruby
require 'gollum/app'

gollum_path = ENV.fetch('GOLLUM_PATH', Dir.pwd)

Precious::App.set(:environment, ENV.fetch('RACK_ENV', 'production').to_sym)
Precious::App.set(:gollum_path, gollum_path)
Precious::App.set(:wiki_options, { allow_uploads: false, allow_editing: true })

run Precious::App
```
`GOLLUM_PATH` can be set at runtime to point at an external git repository.

---

### 5. Sprockets manifest dotfile excluded by warbler

**Symptom:**
```
LoadError: no such file to load -- sassc
  sprockets/autoload/sassc.rb:2
  sprockets/sassc_processor.rb:42:in `initialize'
  sprockets/helpers.rb:137:in `stylesheet_tag'
```

**Root cause:** In production mode Gollum uses precompiled assets served via
`Rack::Static` from `lib/gollum/public/assets/`. The asset URL→digested filename
mapping lives in `.sprockets-manifest-<hash>.json` (a dotfile). Warbler skips
dotfiles by default, so the manifest was absent from the WAR.

Without the manifest, `Sprockets::Helpers#find_asset_path` can't resolve
`"app.css"` → `"app-<digest>.css"` from the manifest index, and falls through to
live Sprockets compilation. Sprockets 4 unconditionally registers `SasscProcessor`
as the transformer for `.scss`/`.sass`, and `SasscProcessor#initialize` requires
`sassc` — which is excluded from the WAR (it's a dev-only C extension).

**Fix:** Force warbler to include the manifest file:
```ruby
config.includes.include('lib/gollum/public/assets/.sprockets-manifest-*.json')
```

---

## Other Changes

- `lib/gollum/assets.rb`: guarded sassc processor registration with
  `Gem.loaded_specs.key?('sassc')` so it is safely skipped when sassc is not
  activated (inside the WAR, only activated gems appear in `loaded_specs`).
- `config/warble.rb`: set `jruby.rack.logging = stdout` to route jruby-rack init
  errors directly to stdout, bypassing SLF4J entirely. This is sufficient — adding
  a competing SLF4J binding (e.g. slf4j-simple) conflicts with Jetty's bundled
  binding in the Rack/Jetty path and with the `-S gollum` classpath.
- `.gitignore`: added `gollum.war`.

---

## Final State

```
$ java -jar gollum.war
INFO: jruby 9.4.14.0 (3.1.7) ...
INFO: using a shared (thread-safe) runtime
# → HTTP 302 redirect → 200 on wiki pages
```

Build command: `bundle exec warble executable war`

# Coding Conventions

**Analysis Date:** 2026-04-02

## Naming Patterns

**Files:**
- Ruby classes in `lib/gollum/` use lowercase file names matching their module structure: `app.rb`, `helpers.rb`, `assets.rb`
- View classes in `lib/gollum/views/` follow the pattern `view_name.rb` (e.g., `page.rb`, `edit.rb`, `compare.rb`)
- Test files use prefix `test_` followed by descriptive name: `test_app.rb`, `test_allow_editing.rb`
- Integration tests in `test/integration/` use same `test_*.rb` pattern

**Classes:**
- PascalCase for class names: `Precious::App`, `Precious::Views::Page`, `Precious::Helpers`
- Mustache view classes inherit from `Precious::Views::Layout` and use descriptive names
- Module names use PascalCase with double colons for namespacing: `Precious::Views::AppHelpers`, `Precious::Views::RouteHelpers`

**Methods:**
- snake_case for method names: `show_history`, `wiki_page`, `find_upload_dest`, `commit_options`
- Instance methods used for view rendering: `title`, `author`, `date`, `content`
- Helper methods with specific purpose: `forbid`, `not_found`, `sanitize_empty_params`, `strip_page_name`
- Predicate methods with `?`: `has_path`, `editable`, `noindex` (also used as property accessors in views)
- Private/internal helper methods use underscores: `page_header_from_content`, `content_without_page_header`

**Variables:**
- Instance variables prefixed with `@`: `@page`, `@name`, `@path`, `@wiki`, `@allow_editing`, `@base_url`
- Snake_case for local variables: `fullpath`, `wiki_page`, `commit_options`
- Constants in UPPERCASE: `DATE_FORMAT`, `DEFAULT_AUTHOR`, `VALID_COUNTER_STYLES`, `KEYBINDINGS`
- Class variables with `@@`: `@@filters` (in `Gollum::TemplateFilter`), `@@route_methods`

**Parameters and Arguments:**
- Snake_case for parameter names in method signatures
- Use meaningful names that describe content: `content`, `format`, `message`, `page`, `path`
- Optional parameters often have defaults: `version = nil`, `wiki = nil`

## Code Style

**Formatting:**
- No explicit linter configuration file (.rubocop.yml) — style is conventional Ruby
- UTF-8 encoding declaration at top of files: `# ~*~ encoding: utf-8 ~*~`
- Two-space indentation consistently throughout
- Methods organized by functionality within classes

**Linting:**
- No automated linting tool detected in project configuration
- Style follows Ruby best practices and conventions

**Strings:**
- Use single quotes for simple strings
- Use double quotes or heredoc (`<<~TEXT`) for strings with interpolation or multi-line content
- String interpolation with `#{}` for dynamic content: `"#{prefix}/#{name}"`

**Conditionals:**
- Inline if/unless modifiers for simple cases: `return nil if url.nil?`, `redirect to("/") unless @page.nil?`
- `if...else...end` blocks for complex logic
- Ternary operator for simple true/false assignments: `@version ? page.version : page.last_version`

**Comments:**
- Comments use `#` prefix with space: `# This is a comment`
- Multi-line documentation uses `=begin...=end` blocks for license headers (see `lib/gollum/uri_encode_component.rb`)
- Comments describe **why**, not what: "Remove file extension", "Revert escaped whitespaces"
- URL references in comments: `# https://www.w3.org/TR/css-counter-styles-3/`
- Implementation notes with context: `# Well-formed SVG with XMLNS and height/width removed, for use in CSS`

**Documentation:**
- Brief docstring comments above helper methods explaining purpose
- Parameter descriptions in comments when non-obvious
- No formal RDoc/YARD-style documentation found in active code

## Import Organization

**Order:**
1. Standard library (`require 'cgi'`, `require 'digest/md5'`, `require 'json'`)
2. External gems (`require 'sinatra'`, `require 'i18n'`, `require 'rack/test'`)
3. Internal files (`require './lib/gollum/app.rb'`, `require File.expand_path(...)`)
4. Conditional requires based on environment: `require 'rhino' if RUBY_PLATFORM == 'java'`

**Module/Class Requires:**
- Deep requires for specific modules: `require 'gollum/views/helpers'`
- View helpers explicitly required before using: `require 'gollum/views/layout'`
- Test helper loaded first: `require File.expand_path(File.join(File.dirname(__FILE__), 'helper'))`

**Module Composition:**
- Include patterns for mixins: `include Rack::Test::Methods`, `include Precious::Helpers`, `include Capybara::DSL`
- Register patterns for Sinatra: `register Mustache::Sinatra`, `register Sinatra::Namespace`
- Extend patterns for class methods: `self.extend Precious::Views::TemplateCascade`

## Error Handling

**Patterns:**
- Explicit rescue blocks with specific exception classes:
  ```ruby
  begin
    wiki.write_page(...)
  rescue Gollum::DuplicatePageError, Gollum::IllegalDirectoryPath => e
    @message = e.message
    mustache :error
  end
  ```
- Rescue and set error message for display: `@message = "The patch does not apply."`
- Custom error handling via Sinatra `status` and `halt`: `status 404; halt mustache :error`
- Helper methods for common error responses: `forbid(msg)`, `not_found(msg)`

**Status Codes:**
- HTTP status set before response: `status 404`, `status 403`
- Redirect on success: `redirect to("/path")`
- Return HTTP status directly: `assert_equal last_response.status, 303`

**Validation:**
- Parameter sanitization: `sanitize_empty_params(params[:path])` — returns nil for empty values
- URL encoding validation: `CGI.escape()`, `CGI.unescape()`
- File path validation: `Gollum::Page.valid_extension?()`, `strip_page_name()`

## Logging

**Framework:** No explicit logging framework found — uses standard `puts` for console output

**Patterns:**
- Informational messages to stdout: `puts "\n  Installing `yarn`-managed JavaScript dependencies...  \n\n"`
- Task completion messages: `puts "\n  Precompiling assets to #{path}...  \n\n"`
- Status messages: `puts "Updated version to #{bump_version}"`

## Control Flow

**Before Hooks:**
- Sinatra `before` blocks for pre-request setup
- Configuration occurs once per request: `@allow_editing = settings.wiki_options.fetch(...)`
- Shared state initialization: `@base_url`, `@page_dir`, `@wiki_title`

**Early Returns:**
- Methods exit early with guard clauses: `return path unless @page_dir`
- Redirect instead of return for HTTP responses: `redirect to("/")`
- Status + halt for error responses: `status 404; halt mustache :error`

## Instance Variables in Views

**Shared Pattern:**
- View template variables set as instance variables in controller/view method
- Accessed in Mustache templates via property names: `@content` → `{{content}}`, `@editable` → `{{editable}}`
- Boolean properties used for conditional rendering: `@editable`, `@navbar`, `@preview`

**Common Assignments:**
```ruby
@page = wiki_page(path)
@name = page.filename_stripped
@content = page.formatted_data
@editable = true
@toc_content = wiki.universal_toc ? @page.toc_data : nil
@allow_uploads = wiki.allow_uploads
```

## Module Design

**Modules as Mixins:**
- Helper modules included in classes: `include Precious::Helpers` in App
- View helper modules: `include Precious::Views::RouteHelpers`, `include Precious::Views::OcticonHelpers`
- Test helper modules: `include Rack::Test::Methods`, `include Capybara::DSL`

**Module Methods:**
- Modules define helper methods for classes that include them
- Self-configuration via `self.included` hook:
  ```ruby
  def self.included(base)
    @@route_methods = {}
    self.parse_routes(ROUTES)
  end
  ```

**Barrel Exports:**
- No barrel/star exports observed
- Individual requires for each module/class

---

*Convention analysis: 2026-04-02*

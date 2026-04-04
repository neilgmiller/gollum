# Testing Patterns

**Analysis Date:** 2026-04-02

## Test Framework

**Runner:**
- Minitest with TestTask via Rake (no RSpec)
- Config: `lib/gollum` and `test` added to load path
- Entry point: `test/helper.rb` required by all tests

**Assertion Library:**
- Minitest assertions: `assert`, `assert_equal`, `assert_match`, `refute`, `assert_nil`, `assert_includes`
- Shoulda matchers via `gem 'shoulda'` for assertion helpers
- Mocha for mocking/stubbing: `gem 'mocha'`

**Run Commands:**
```bash
bundle exec rake test              # Run all unit tests
bundle exec rake test:capybara     # Run integration tests
bundle exec ruby <test_file.rb>    # Run single test file
```

**Additional Test Dependencies:**
- `rack-test` (~> 0.6.3) — HTTP testing with `get`, `post`
- `capybara` — Browser automation for integration tests
- `selenium-webdriver` — WebDriver for Capybara browser control
- `minitest-reporters` (~> 1.3.6) — Formatted test output with colors

## Test File Organization

**Location:**
- Unit tests: `test/test_*.rb` (co-located with test/helper.rb)
- Integration tests: `test/integration/test_*.rb`
- Helper utilities: `test/capybara_helper.rb`, `test/helper.rb`

**Naming:**
- Test files: `test_<feature>.rb` (e.g., `test_app.rb`, `test_allow_editing.rb`, `test_compare.rb`)
- Test contexts: descriptive strings (e.g., `"Frontend"`, `"Precious::Views::Editing"`)
- Test cases: descriptive strings (e.g., `"utf-8 kcode"`, `"broken four space"`)

**Structure:**
```
test/
├── test_*.rb                    # Unit tests
├── integration/
│   └── test_*.rb                # Integration tests
├── examples/
│   └── lotr.git/                # Test git repositories
├── helper.rb                    # Shared test setup
└── capybara_helper.rb           # Capybara-specific setup
```

## Test Structure

**Minitest with Custom DSL:**

The project uses a custom RSpec-like DSL via the `context` helper (defined in `test/helper.rb`):

```ruby
# Test file pattern
require File.expand_path(File.join(File.dirname(__FILE__), "helper"))

context "Frontend" do
  include Rack::Test::Methods

  setup do
    # Per-test setup
    @path = cloned_testpath("examples/revert.git")
    @wiki = Gollum::Wiki.new(@path)
    Precious::App.set(:gollum_path, @path)
  end

  teardown do
    # Per-test cleanup
    FileUtils.rm_rf(@path)
  end

  test "utf-8 kcode" do
    assert_equal 'μ†ℱ'.scan(/./), ["μ", "†", "ℱ"]
  end

  test "broken four space" do
    # Test implementation
    get page
    assert_match /<pre><code>one\ntwo\nthree\nfour\n<\/code><\/pre>\n/m, last_response.body
  end
end
```

**Integration Test Pattern (Capybara):**

```ruby
require_relative "../capybara_helper"

context "editor interface" do
  include Capybara::DSL

  setup do
    @path = cloned_testpath "examples/lotr.git"
    @wiki = Gollum::Wiki.new @path

    Precious::App.set :gollum_path, @path
    Precious::App.set :wiki_options, {}

    Capybara.app = Precious::App
  end

  teardown do
    @path = nil
    @wiki = nil
    Capybara.reset_sessions!
    Capybara.use_default_driver
  end

  test "editor renders help panel" do
    visit "/create/new-article"
    in_editor_toolbar do
      click_on "Help"
    end
    help_widget = find "#gollum-editor-help"
    within help_widget do
      assert_includes page.text, "Emoji"
    end
  end
end
```

**Setup/Teardown Pattern:**
- `setup` block runs before each test
- `teardown` block runs after each test
- File cleanup always performed: `FileUtils.rm_rf(@path)`
- App state reset between tests: `Precious::App.set(:wiki_options, ...)`

## Helper Functions and Fixtures

**Test Helpers (in `test/helper.rb`):**

```ruby
def testpath(path)
  File.join(TEST_DIR, path)
end

def cloned_testpath(path, bare = false)
  # Clone test git repository to temp directory
  repo   = File.expand_path(testpath(path))
  tmpdir = Dir.mktmpdir(self.class.name)
  %x{git clone #{bare} '#{repo}' #{tmpdir} #{redirect}}
  tmpdir
end

def commit_details
  { :message => "Did something at #{Time.now}",
    :name    => "Tom Preston-Werner",
    :email   => "tom@github.com" }
end

def normal(text)
  text.gsub!(' ', '')
  text.gsub!("\n", '')
  text
end
```

**Capybara Helpers (in `test/capybara_helper.rb`):**

```ruby
def create_page(title:, content:)
  visit "/"
  click_on "New"
  fill_in "Page Name", with: title
  # ... assertions and interactions
  using_wait_time 10 do
    assert page.current_path, "/#{title}.md"
  end
end

def wait_for_ajax
  Timeout.timeout(Capybara.default_max_wait_time) do
    loop until page.evaluate_script('jQuery.active').zero?
  end
end

def in_editor_toolbar &block
  return unless block_given?
  within "#gollum-editor-function-bar" do
    yield
  end
end
```

**Test Data:**
- Example git repositories in `test/examples/` (e.g., `lotr.git`, `revert.git`)
- Repositories cloned to temp directory per test for isolation
- Commit details fixture for creating pages

## Mocking and Stubbing

**Framework:** Mocha

**Patterns:**
- Mocha included via `require 'mocha/minitest'`
- Stub/mock objects for isolated unit tests
- Instance variable assignment for test state: `view.instance_variable_set(:@diff, diff)`

**What to Mock:**
- External API calls
- Expensive file operations
- Git operations when testing view logic

**What NOT to Mock:**
- Core wiki functionality (use real `Gollum::Wiki` instance)
- Git repositories (use cloned test repositories)
- Page rendering logic (test with actual content)

## Integration Testing

**Capybara Configuration (in `test/capybara_helper.rb`):**

```ruby
Selenium::WebDriver::Chrome.path = ENV['CHROME_PATH'] if ENV['CHROME_PATH']

CAPYBARA_DRIVER =
  if ENV['CI']
    :selenium_chrome_headless
  else
    ENV.fetch('CAPYBARA_DRIVER', :selenium_chrome).to_sym
  end

Capybara.default_driver = CAPYBARA_DRIVER
Capybara.enable_aria_label = true

if ENV['GOLLUM_CAPYBARA_URL']
  Capybara.configure do |config|
    config.run_server = false
    config.app_host = ENV['GOLLUM_CAPYBARA_URL']
  end
else
  Capybara.server = :webrick
end
```

**Driver Selection:**
- Default: `:selenium_chrome` (headless in CI)
- Override: `ENV['CAPYBARA_DRIVER']`
- Browser path: `ENV['CHROME_PATH']`
- Remote server: `ENV['GOLLUM_CAPYBARA_URL']`

**Integration Test Locations:**
- `test/integration/test_*.rb` — Capybara-based browser tests
- Tests use `include Capybara::DSL` to access DSL methods
- Test contexts follow same pattern as unit tests

## Rack::Test for HTTP Testing

**Pattern (in unit tests with `include Rack::Test::Methods`):**

```ruby
test 'creating pages is not blocked' do
  post '/gollum/create',
    content: 'abc',
    format: 'markdown',
    message: 'def',
    page: 'D'

  assert_equal last_response.status, 303
  refute_nil @wiki.page('D')
end
```

**Common Methods:**
- `get path` — Make GET request
- `post path, params` — Make POST request
- `last_response` — Access response object
- `last_response.status` — HTTP status code
- `last_response.body` — Response body
- `last_response.ok?` — Boolean for 2xx status

## Test Coverage

**Tool:** RCov (legacy, found in Rakefile)

**View Coverage:**
```bash
bundle exec rake coverage
# Generates coverage report and opens in browser
```

**Requirements:** None enforced (no coverage threshold detected)

**Coverage Gaps Observed:**
- Error path testing present but not comprehensive
- Edge cases for Unicode handling tested
- Page rendering tested with various formats

## Special Test Utilities

**Wiki Setup:**
- `Precious::App.set(:gollum_path, @path)` — Configure app for test
- `Precious::App.set(:wiki_options, {...})` — Set wiki configuration
- `Gollum::Wiki.new(@path)` — Create wiki instance from test repo

**Assertions for Web Tests:**
```ruby
assert last_response.ok?
assert_equal last_response.status, 303
assert_match /pattern/, last_response.body
assert last_response.body.include? "text"
refute last_response.body.include? "text"
```

**Assertions for Capybara:**
```ruby
visit '/page'
find(:id, 'element-id').click
fill_in "Form Field", with: "value"
click_on "Button Text"
assert_includes page.text, "Expected content"
using_wait_time 10 { assert page.current_path, "/expected" }
```

## Test Execution

**Running Tests:**
```bash
# All unit tests (excludes integration tests)
bundle exec rake test

# Integration tests only
bundle exec rake test:capybara

# Single test file
bundle exec ruby test/test_app.rb

# With verbose output
bundle exec rake test TESTOPTS="--verbose"
```

**Test Order:**
- Default: runs all `test/**/test_*.rb` except `test/integration/**`
- Integration: runs only `test/integration/**/test_*.rb`
- Separation allows fast unit test iteration

---

*Testing analysis: 2026-04-02*

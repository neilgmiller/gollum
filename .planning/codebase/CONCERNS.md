# Codebase Concerns

**Analysis Date:** 2026-04-02

## Tech Debt

**jQuery 1.9.1 security vulnerability and deprecation:**
- Issue: Gollum bundles jQuery 1.9.1, shipped in 2013. The codebase includes a workaround for CVE-2020-11023 (jQuery XSS vulnerability affecting versions < 3.5.0)
- Files: `lib/gollum/public/gollum/javascript/jquery-1.9.1.min.js`, `lib/gollum/public/gollum/javascript/gollum.js.erb` (lines 3-8)
- Impact: Ancient jQuery means missing security patches, modern browser compatibility issues, and XSS risk despite the patch workaround
- Fix approach: Upgrade jQuery to latest 3.x version (3.7.x). This requires:
  - Migrating to npm package management (currently inline bundled)
  - Testing all editor and page interaction scripts (gollum.editor.js, gollum.dialog.js)
  - Removing the htmlPrefilter patch once upgraded
- Priority: High - active security vulnerability

**Ace Editor integration has architectural limitations:**
- Issue: Editor functions are designed to work on textarea elements, but Ace Editor operates on its own session. The FIXME at `lib/gollum/public/gollum/javascript/editor/gollum.editor.js:781-784` notes that function bar operations use the third parameter incorrectly for Ace
- Files: `lib/gollum/public/gollum/javascript/editor/gollum.editor.js` (lines 750-846)
- Impact: Some editor function bar operations may fail or behave unexpectedly with Ace Editor due to text manipulation mismatches
- Fix approach: Refactor editor function execution to operate directly on Ace session context instead of passing jQuery textarea reference
- Priority: Medium - affects editor UX in specific scenarios

**Deprecated RACK_ENV fallback with removal deadline:**
- Issue: The bin/gollum script (line 273-276) includes a deprecation fallback for RACK_ENV that will be removed in Gollum 7
- Files: `bin/gollum` (lines 273-276)
- Impact: Applications using RACK_ENV instead of APP_ENV will break when Gollum 7 is released
- Fix approach: This is an accepted migration path. Users need to switch to APP_ENV before Gollum 7 release
- Priority: Low - intentional deprecation with notice

**Deprecated --lenient-tag-lookup and --mathjax CLI options:**
- Issue: Two command-line options have deprecation warnings that will be removed in future releases
- Files: `bin/gollum` (lines 155-159 for --lenient-tag-lookup, lines 123-128 for --mathjax)
- Impact: Scripts using these flags will break in future versions
- Fix approach: Users must migrate to --math flag and config.rb option approach. No code change needed, just user documentation
- Priority: Low - intentional deprecation

**JRuby 9.4.9 psych/jar-dependencies upstream issue:**
- Issue: A Gemfile workaround (lines 6-14) locks jar-dependencies to < 0.5 due to upstream JRuby 9.4.9.0 issue #8488
- Files: `Gemfile` (lines 6-14)
- Impact: Workaround required for JRuby users; will be automatically resolved with JRuby 9.4.10.0+
- Fix approach: Remove jar-dependencies lock once JRuby 9.4.10.0+ is released and adopted
- Priority: Low - upstream dependency issue with known resolution

**Protobuf force_ruby_platform workaround:**
- Issue: google-protobuf gem requires force_ruby_platform workaround on Linux musl systems
- Files: `Gemfile` (lines 23-25)
- Impact: Temporary workaround affecting JRuby + Linux musl deployments
- Fix approach: Monitor upstream protobuf issue #16853. Remove when upstream fixes it
- Priority: Low - upstream workaround

## Known Bugs

**Ace Editor RTL (right-to-left) text direction handling incomplete:**
- Symptoms: RTL text direction switching works but may not handle all bidirectional scenarios correctly
- Files: `lib/gollum/public/gollum/javascript/editor/gollum.editor.js` (lines 23-35, 139-141, 267-268)
- Trigger: Editing pages that start with RTL text (Hebrew, Arabic, Persian, etc.) or switching text direction
- Current implementation: `isRTL()` function checks first line only; switching updates Ace bidi handler but may miss edge cases
- Workaround: None documented; users can switch direction manually via UI button
- Test coverage: Likely limited (no dedicated RTL test files found)

**localStorage autosave location exposure:**
- Symptoms: Editor recovery text stored in browser localStorage uses full window.location as key component
- Files: `lib/gollum/public/gollum/javascript/editor/gollum.editor.js` (lines 21, 51, 97, 183)
- Trigger: Any page edit session
- Risk: Multiple wiki instances on same domain at different paths could have storage collisions
- Current mitigation: Key includes full URL but collision still possible if URL varies only in query params
- Workaround: Clear browser localStorage between switching wiki instances
- Priority: Low - affects UX more than security, collision unlikely in practice

**Octicon injection via AJAX without type validation:**
- Symptoms: SVG octicons injected into page via AJAX success callback
- Files: `lib/gollum/public/gollum/javascript/gollum.js.erb` (lines 23-32)
- Trigger: Page load with octicon div elements
- Current mitigation: Octicons from fixed /gollum/octicon/ endpoint; data not user-supplied in URL
- Issue: If octicon endpoint is compromised or XSS vector exists elsewhere, injected SVG could be malicious
- Priority: Low - controlled endpoint, but pattern is vulnerable to regression

## Security Considerations

**XSS risk from historical jQuery version:**
- Risk: jQuery 1.9.1 has known XSS vulnerabilities (pre-3.5.0)
- Files: `lib/gollum/public/gollum/javascript/jquery-1.9.1.min.js`, `lib/gollum/public/gollum/javascript/gollum.js.erb`
- Current mitigation: Partial patch in gollum.js.erb lines 5-8 overrides htmlPrefilter for CVE-2020-11023
- Recommendations:
  1. Upgrade jQuery to 3.7.x immediately
  2. Implement Content Security Policy (CSP) headers to restrict inline script execution
  3. Audit all user-supplied content rendering paths to ensure proper escaping
  4. Add automated dependency scanning (npm audit, bundler-audit) to CI

**URL escaping and XSS in breadcrumbs:**
- Risk: Breadcrumb generation escapes titles but URL paths use escaped_url_path
- Files: `lib/gollum/views/page.rb`, `lib/gollum/views/overview.rb`
- Current mitigation: `CGI.escapeHTML()` used for display text; `escaped_url_path` for links
- Status: Appears properly escaped, but escaping patterns vary across views
- Recommendations: Ensure all user-controlled values (page titles, file paths) are escaped consistently; add automated XSS test cases

**File upload security:**
- Risk: File uploads allowed if --allow-uploads flag set
- Files: `lib/gollum/public/gollum/javascript/editor/gollum.editor.js` (lines 286-344), `bin/gollum` (lines 111-115)
- Current mitigation: Upload endpoint validates requests but details not visible in frontend code
- Questions: Are file type restrictions enforced? Are uploaded files served with correct Content-Type headers?
- Recommendations: Audit upload endpoint implementation in gollum-lib for proper file type/size validation; serve uploads with appropriate CSP headers

**Git command execution via gollum-lib:**
- Risk: Gollum wraps Git operations; malformed page names/paths could inject commands
- Files: `lib/gollum/app.rb` uses gollum-lib which executes git commands
- Current mitigation: Input sanitization via `sanitize_empty_params()` and `clean_url()`
- Status: Medium risk - depends entirely on gollum-lib's command construction safety
- Recommendations: Audit critical git-invocation paths in gollum-lib for shell injection; validate all path inputs

## Performance Bottlenecks

**Asset precompilation on every deployment:**
- Problem: Application serves precompiled assets in production but compilation happens during deployment
- Files: `lib/gollum/assets.rb`, Sprockets configuration
- Cause: Assets (CSS, JS) compiled at build time but process is I/O intensive
- Current: Recent commits show asset precompilation is automated in CI (see git history: "Precompile assets")
- Improvement path:
  1. Consider moving to asset CDN for static resources
  2. Cache Sprockets intermediate files between builds
  3. Consider lazy-loading non-critical JS (Mermaid, MathJax)
- Priority: Medium

**Full page reload on format change:**
- Problem: Changing wiki format (markdown → asciidoc) requires full page reload or complex JS state management
- Files: `lib/gollum/public/gollum/javascript/editor/gollum.editor.js` (lines 166-175)
- Cause: Editor mode and function bar definitions tightly coupled to page state
- Impact: UX friction when testing different formats during editing
- Priority: Low

**Search across large repositories:**
- Problem: Search functionality not visible in frontend files; likely handled by gollum-lib Git operations
- Files: `lib/gollum/views/search.rb`
- Cause: Git grep or linear search through all commits/files
- Risk: Scales poorly with very large wikis (thousands of pages)
- Recommendation: Consider git search optimization or Elasticsearch integration for large deployments
- Priority: Low (affects large installations only)

## Fragile Areas

**Editor keyboard handler persistence via localStorage:**
- Files: `lib/gollum/public/gollum/javascript/editor/gollum.editor.js` (lines 60-70, 117-121)
- Why fragile: Three separate locations store/retrieve 'gollum-kbm' setting; no abstraction layer
- Safe modification: Create a GollumSettings or EditorPreferences abstraction class that handles all localStorage access
- Test coverage: Likely missing - no dedicated test for keyboard handler persistence
- Risk: Bug fix or feature change to keyboard handling will require updating multiple locations

**Mustache template rendering with dynamic content:**
- Files: `lib/gollum/templates/*.mustache`, `lib/gollum/views/*.rb` - template helper files
- Why fragile: Templates receive data from views; any view change could break template assumptions
- Safe modification: View changes should always include template validation tests; avoid adding new context variables without template updates
- Test coverage: Page view tests exist but coverage may be incomplete
- Risk: Template rendering errors from missing or malformed context variables

**WAR deployment configuration (recent, still fragile):**
- Files: `config/warble.rb`, `config.ru`, `lib/gollum/assets.rb`
- Why fragile: Recent fixes (commit 8f6205d4) for WAR buildability introduced many interdependencies:
  - Warbler manifest dotfile inclusion for asset resolution
  - SasscProcessor guard in assets.rb
  - jruby.rack.response.dechunk = 'false' setting
  - Removal of =begin blocks from config.ru
- Safe modification: Any change to asset pipeline, config.ru, or warble.rb requires full WAR build test (`bundle exec warble executable war`)
- Test coverage: Limited - only manual testing documented in `docs/warble-war-debugging.md`
- Risk: High - one misconfiguration can make entire WAR unrunnable

## Scaling Limits

**In-process Git repository operations:**
- Current capacity: Designed for single-server, local filesystem Git repository access
- Limit: Will not scale beyond single machine; no distributed locking or remote repo support
- Scaling path:
  1. Add support for Git over SSH/HTTPS backends (currently local filesystem only)
  2. Implement distributed file locking for multi-server deployments
  3. Consider git-http-backend or gitolite integration for large-scale deployments

**MathJax/Mermaid rendering in browser:**
- Current capacity: MathJax and Mermaid.js loaded and rendered client-side
- Limit: Large numbers of complex equations/diagrams will freeze browser
- Scaling path: Move to server-side rendering (SVG generation) or lazy-load on scroll
- Current code: `lib/gollum/public/gollum/javascript/gollum.mermaid.js`, MathJax directory

**Browser localStorage for editor recovery:**
- Current capacity: localStorage typically 5-10MB per domain
- Limit: Very large pages (>5MB) will exceed localStorage quota
- Scaling path: Fall back to IndexedDB for large content, or implement server-side draft storage
- Files: `lib/gollum/public/gollum/javascript/editor/gollum.editor.js`

## Dependencies at Risk

**Sinatra 4.0 (recent major version bump):**
- Risk: Gollum depends on Sinatra ~> 4.0 which is a major version (likely breaking changes from 3.x)
- Impact: Potential routing or request/response handling differences if Sinatra API changed significantly
- Migration plan: Monitor Sinatra changelog; Gollum maintainers should document compatibility notes
- Current: Appears to be working post-upgrade based on recent commits

**sprockets 4.x with platform-specific dependencies:**
- Risk: Sprockets depends on Sassc for SCSS compilation; Sassc is a C extension that fails to build on some platforms (musl Linux)
- Impact: JRuby + musl Linux deployments cannot build assets
- Current mitigation: Assets precompiled in CI; Sassc guard in assets.rb prevents loading when unavailable
- Fragility: WAR builds will fail if precompiled assets are missing or corrupt

**gollum-lib dependency (external, non-vendored):**
- Risk: Core wiki functionality in external library; security/bug fixes depend on upstream releases
- Impact: Version mismatches can cause runtime errors; security vulnerabilities in gollum-lib affect Gollum
- Current: Locked to ~> 6.0 (major version pin)
- Recommendation: Monitor gollum-lib security advisories; coordinate release schedules

## Missing Critical Features

**Authentication/Authorization:**
- Problem: No built-in user authentication; anyone with network access can read/edit
- Blocks: Multi-user wikis, sensitive documentation, audit trails
- Current workaround: Deploy behind reverse proxy with auth (nginx, Apache); set --no-edit flag to disable editing
- Impact: Enterprise deployments require additional infrastructure

**Access Control Lists (ACLs):**
- Problem: No per-page or per-branch permissions
- Blocks: Restricting access to sensitive pages; collaborative wikis with role-based content
- Current: All-or-nothing read/edit model

**Audit logging:**
- Problem: Limited to Git commit history; no structured logs of who viewed/edited what
- Blocks: Compliance requirements, user activity tracking
- Current: Must parse git history manually

## Test Coverage Gaps

**JavaScript editor functionality:**
- What's not tested: Ace Editor integration, function bar actions, RTL text handling, drag-drop uploads
- Files: `lib/gollum/public/gollum/javascript/editor/gollum.editor.js` (900+ lines)
- Risk: Bugs in editor go undetected until user reports; RTL handling especially fragile
- Priority: High - editor is critical UI component

**WAR deployment build:**
- What's not tested: Executable WAR builds; recent fixes are only verified via manual testing
- Files: `config/warble.rb`, `config.ru`, `lib/gollum/assets.rb`
- Risk: CI may pass but WAR production builds fail; requires manual `bundle exec warble executable war` test
- Priority: High - recent fixes are fragile (documented in warble-war-debugging.md)

**File upload handling:**
- What's not tested: Upload size limits, file type restrictions, special characters in filenames, concurrent upload conflicts
- Files: `lib/gollum/public/gollum/javascript/editor/gollum.editor.js` (lines 297-343), upload endpoint (not in this repo)
- Risk: Undetected file handling bugs in production
- Priority: Medium - uploads can compromise repo integrity

**Security-focused tests:**
- What's not tested: XSS via page titles/content, Git command injection via malformed page names, localStorage isolation between instances
- Risk: Regressions in security fixes go undetected
- Priority: High - security is critical

**Internationalization (i18n):**
- What's not tested: Locale-specific rendering, RTL language handling beyond basic tests
- Files: `lib/gollum/locales/`, `lib/gollum/views/helpers/locale_helpers.rb`
- Coverage gaps: RTL layout, text directionality in complex UI elements
- Priority: Medium - affects international users

---

*Concerns audit: 2026-04-02*

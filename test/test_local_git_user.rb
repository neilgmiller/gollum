# ~*~ encoding: utf-8 ~*~
require File.expand_path(File.join(File.dirname(__FILE__), 'helper'))
require 'tempfile'

context "Local git user web edit" do
  include Rack::Test::Methods

  setup do
    @path = cloned_testpath('examples/revert.git')
    system("git -C #{@path} config user.name 'Test User'")
    system("git -C #{@path} config user.email 'test@example.com'")
    Precious::App.set(:gollum_path, @path)
    Precious::App.set(:wiki_options, { allow_editing: true, local_git_user: true })
  end

  teardown do
    Precious::App.set(:wiki_options, { allow_editing: true })
    FileUtils.rm_rf(@path)
  end

  def app
    Precious::App
  end

  test "POST /gollum/create with local_git_user uses git config author" do
    post '/gollum/create', content: 'test content', format: 'markdown', message: 'test create', page: 'LocalUserTest'
    assert last_response.redirect?, "Expected redirect, got #{last_response.status}"
    author_line = `git -C #{@path} log -1 --format='%an <%ae>'`.strip
    assert_equal 'Test User <test@example.com>', author_line
  end

  test "POST /upload_file with local_git_user uses git config author" do
    Precious::App.set(:wiki_options, { allow_editing: true, local_git_user: true, allow_uploads: true })
    tmpfile = Tempfile.new(['upload_test', '.txt'])
    tmpfile.write('upload content')
    tmpfile.rewind
    post '/gollum/upload_file', file: Rack::Test::UploadedFile.new(tmpfile.path, 'text/plain')
    author_line = `git -C #{@path} log -1 --format='%an <%ae>'`.strip
    assert_equal 'Test User <test@example.com>', author_line
    tmpfile.close!
  end

  test "git config read fresh on each write request" do
    post '/gollum/create', content: 'first content', format: 'markdown', message: 'first', page: 'FreshRead1'
    author1 = `git -C #{@path} log -1 --format='%an'`.strip
    assert_equal 'Test User', author1

    system("git -C #{@path} config user.name 'Changed User'")
    post '/gollum/create', content: 'second content', format: 'markdown', message: 'second', page: 'FreshRead2'
    author2 = `git -C #{@path} log -1 --format='%an'`.strip
    assert_equal 'Changed User', author2
  end

  test "missing git config falls back to Gollum defaults without crash" do
    system("git -C #{@path} config --unset user.name")
    system("git -C #{@path} config --unset user.email")

    # Isolate from real global config so fallback behavior is tested
    tmpfile = Tempfile.new(['empty_gitconfig', ''])
    old_env = ENV['GIT_CONFIG_GLOBAL']
    ENV['GIT_CONFIG_GLOBAL'] = tmpfile.path

    begin
      post '/gollum/create', content: 'fallback content', format: 'markdown', message: 'fallback test', page: 'FallbackTest'
      assert last_response.redirect?, "Expected redirect, got #{last_response.status}"
      author_name = `git -C #{@path} log -1 --format='%an'`.strip
      refute_equal 'Test User', author_name
    ensure
      ENV['GIT_CONFIG_GLOBAL'] = old_env
      tmpfile.close!
    end
  end

  test "partial git config (name only) falls back entirely to Gollum defaults" do
    system("git -C #{@path} config --unset user.email")

    # Isolate from real global config so partial fallback is tested
    tmpfile = Tempfile.new(['empty_gitconfig', ''])
    old_env = ENV['GIT_CONFIG_GLOBAL']
    ENV['GIT_CONFIG_GLOBAL'] = tmpfile.path

    begin
      post '/gollum/create', content: 'partial content', format: 'markdown', message: 'partial test', page: 'PartialTest'
      assert last_response.redirect?, "Expected redirect, got #{last_response.status}"
      author_name = `git -C #{@path} log -1 --format='%an'`.strip
      refute_equal 'Test User', author_name
    ensure
      ENV['GIT_CONFIG_GLOBAL'] = old_env
      tmpfile.close!
    end
  end

  test "session author overrides local git user" do
    gollum_author = { :name => 'Session User', :email => 'session@test.com' }
    session = { 'gollum.author' => gollum_author }
    post '/gollum/create', { content: 'session content', format: 'markdown', message: 'session test', page: 'SessionTest' }, { 'rack.session' => session }
    assert last_response.redirect?, "Expected redirect, got #{last_response.status}"
    author_line = `git -C #{@path} log -1 --format='%an <%ae>'`.strip
    assert_equal 'Session User <session@test.com>', author_line
  end
end

context "resolve_local_git_user helper" do
  include Rack::Test::Methods

  setup do
    @path = cloned_testpath('examples/revert.git')
    Precious::App.set(:gollum_path, @path)
  end

  teardown do
    Precious::App.set(:wiki_options, { allow_editing: true })
    FileUtils.rm_rf(@path)
  end

  def app
    Precious::App
  end

  test "returns name and email hash with symbol keys when git config is set" do
    system("git -C #{@path} config user.name 'Test User'")
    system("git -C #{@path} config user.email 'test@example.com'")
    app_instance = Precious::App.new!
    result = app_instance.send(:resolve_local_git_user)
    assert_equal({ name: 'Test User', email: 'test@example.com' }, result)
  end

  test "reads global git config when no repo-local config is set" do
    # Ensure no repo-local user config
    system("git -C #{@path} config --unset user.name 2>/dev/null; true")
    system("git -C #{@path} config --unset user.email 2>/dev/null; true")

    # Create a temporary global config with user identity
    tmpfile = Tempfile.new(['gitconfig', ''])
    tmpfile.write("[user]\n\tname = Global User\n\temail = global@example.com\n")
    tmpfile.flush

    old_env = ENV['GIT_CONFIG_GLOBAL']
    ENV['GIT_CONFIG_GLOBAL'] = tmpfile.path

    begin
      app_instance = Precious::App.new!
      result = app_instance.send(:resolve_local_git_user)
      assert_equal({ name: 'Global User', email: 'global@example.com' }, result)
    ensure
      ENV['GIT_CONFIG_GLOBAL'] = old_env
      tmpfile.close!
    end
  end

  test "returns nil when git config user.name is empty" do
    system("git -C #{@path} config --unset user.name 2>/dev/null; true")
    system("git -C #{@path} config --unset user.email 2>/dev/null; true")

    # Isolate from real global config so we truly get no user identity
    tmpfile = Tempfile.new(['empty_gitconfig', ''])
    old_env = ENV['GIT_CONFIG_GLOBAL']
    ENV['GIT_CONFIG_GLOBAL'] = tmpfile.path

    begin
      app_instance = Precious::App.new!
      result = app_instance.send(:resolve_local_git_user)
      assert_nil result
    ensure
      ENV['GIT_CONFIG_GLOBAL'] = old_env
      tmpfile.close!
    end
  end
end

context "Local git user CLI flag" do
  test "parses --local-git-user flag" do
    wiki_options = {}
    parser = OptionParser.new do |opts|
      opts.on('--local-git-user') do
        wiki_options[:local_git_user] = true
      end
    end
    parser.parse!(['--local-git-user'])
    assert_equal true, wiki_options[:local_git_user]
  end

  test "default wiki_options does not include local_git_user" do
    default_opts = { allow_editing: true }
    assert_nil default_opts[:local_git_user]
    assert_equal false, default_opts.key?(:local_git_user)
  end
end

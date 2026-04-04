# ~*~ encoding: utf-8 ~*~
require File.expand_path(File.join(File.dirname(__FILE__), 'helper'))

context "Branch tracking CLI flag" do
  include Rack::Test::Methods

  setup do
    @path = cloned_testpath('examples/revert.git')
    Precious::App.set(:gollum_path, @path)
    Precious::App.set(:wiki_options, { allow_editing: true, track_current_branch: true })
  end

  teardown do
    Precious::App.set(:wiki_options, { allow_editing: true })
    FileUtils.rm_rf(@path)
  end

  def app
    Precious::App
  end

  test "track_current_branch option is available in wiki_options" do
    assert_equal true, Precious::App.wiki_options[:track_current_branch]
  end

  test "default wiki_options does not include track_current_branch" do
    default_opts = { allow_editing: true }
    assert_nil default_opts[:track_current_branch], "A fresh wiki_options hash should not contain track_current_branch"
    assert_equal false, default_opts.key?(:track_current_branch)
  end
end

context "Branch tracking mutual exclusion" do
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

  test "ref and track_current_branch conflict is detected" do
    wiki_opts = { track_current_branch: true, ref: 'main' }
    cli_opts = { track_current_branch: true, ref: 'main' }
    Kernel.expects(:exit).with(1).once
    err = capture_stderr do
      Precious::App.validate_wiki_options!(wiki_opts, cli_opts)
    end
    assert_match(/mutually exclusive/, err)
  end

  test "default ref does not conflict with track_current_branch" do
    wiki_opts = { track_current_branch: true }
    cli_opts = { track_current_branch: true }
    # Should not raise or exit
    err = capture_stderr do
      Precious::App.validate_wiki_options!(wiki_opts, cli_opts)
    end
    assert_equal '', err
    refute wiki_opts.key?(:ref)
  end

  test "error message identifies CLI source for ref" do
    wiki_opts = { track_current_branch: true, ref: 'main' }
    cli_opts = { track_current_branch: true, ref: 'main' }
    Kernel.stubs(:exit)
    err = capture_stderr do
      Precious::App.validate_wiki_options!(wiki_opts, cli_opts)
    end
    assert_match(/CLI \(--ref\)/, err)
  end

  test "error message identifies config file source for ref" do
    wiki_opts = { track_current_branch: true, ref: 'main' }
    cli_opts = { track_current_branch: true }  # ref NOT in cli, so it came from config
    Kernel.stubs(:exit)
    err = capture_stderr do
      Precious::App.validate_wiki_options!(wiki_opts, cli_opts)
    end
    assert_match(/config file/, err)
  end

  test "error message identifies config file source for track_current_branch" do
    wiki_opts = { track_current_branch: true, ref: 'main' }
    cli_opts = { ref: 'main' }  # track_current_branch NOT in cli, so it came from config
    Kernel.stubs(:exit)
    err = capture_stderr do
      Precious::App.validate_wiki_options!(wiki_opts, cli_opts)
    end
    assert_match(/config file/, err)
    assert_match(/CLI \(--ref\)/, err)
  end

  private

  def capture_stderr
    old_stderr = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = old_stderr
  end
end

context "Branch tracking HEAD resolution" do
  include Rack::Test::Methods

  setup do
    @path = cloned_testpath('examples/revert.git')
    Precious::App.set(:gollum_path, @path)
    Precious::App.set(:wiki_options, { allow_editing: true, track_current_branch: true })
    @wiki = Gollum::Wiki.new(@path)
  end

  teardown do
    Precious::App.set(:wiki_options, { allow_editing: true })
    FileUtils.rm_rf(@path)
  end

  def app
    Precious::App
  end

  test "serves pages from current branch" do
    get '/A'
    assert last_response.ok?
  end

  test "follows branch switch" do
    system("git -C #{@path} checkout -b test-follow-branch 2>/dev/null")
    wiki = Gollum::Wiki.new(@path, ref: 'test-follow-branch')
    wiki.write_page('FollowPage', :markdown, 'follow-branch-content', commit_details)
    get '/FollowPage'
    assert last_response.ok?
    assert_match /follow-branch-content/, last_response.body
  end

  test "resolve_current_branch returns branch name for normal HEAD" do
    result = app.new!.send(:resolve_current_branch)
    assert_equal false, result[:detached]
    refute_nil result[:ref]
    refute_empty result[:ref]
  end

  test "resolve_current_branch returns SHA for detached HEAD" do
    sha = `git -C #{@path} rev-parse HEAD`.strip
    system("git -C #{@path} checkout #{sha} 2>/dev/null")
    result = app.new!.send(:resolve_current_branch)
    assert_equal true, result[:detached]
    assert_equal sha, result[:ref]
  end
end

context "Branch tracking detached HEAD editing" do
  include Rack::Test::Methods

  setup do
    @path = cloned_testpath('examples/revert.git')
    Precious::App.set(:gollum_path, @path)
    Precious::App.set(:wiki_options, { allow_editing: true, track_current_branch: true })
  end

  teardown do
    Precious::App.set(:wiki_options, { allow_editing: true })
    FileUtils.rm_rf(@path)
  end

  def app
    Precious::App
  end

  test "detached HEAD disables editing" do
    sha = `git -C #{@path} rev-parse HEAD`.strip
    system("git -C #{@path} checkout #{sha} 2>/dev/null")
    post '/gollum/create', content: 'test', format: 'markdown', message: 'test', page: 'DetachedTest'
    assert_equal 403, last_response.status
  end

  test "re-attaching HEAD re-enables editing" do
    sha = `git -C #{@path} rev-parse HEAD`.strip
    branch = `git -C #{@path} rev-parse --abbrev-ref HEAD`.strip
    system("git -C #{@path} checkout #{sha} 2>/dev/null")
    # Detached: editing disabled
    post '/gollum/create', content: 'test', format: 'markdown', message: 'test', page: 'DetachedTest'
    assert_equal 403, last_response.status
    # Re-attach
    system("git -C #{@path} checkout #{branch} 2>/dev/null")
    post '/gollum/create', content: 'test2', format: 'markdown', message: 'test2', page: 'ReattachTest'
    assert_equal 303, last_response.status
  end

  test "detached HEAD still serves pages" do
    sha = `git -C #{@path} rev-parse HEAD`.strip
    system("git -C #{@path} checkout #{sha} 2>/dev/null")
    get '/A'
    assert last_response.ok?
  end
end

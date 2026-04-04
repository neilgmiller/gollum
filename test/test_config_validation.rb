# ~*~ encoding: utf-8 ~*~
require File.expand_path(File.join(File.dirname(__FILE__), 'helper'))
require 'stringio'
require 'tmpdir'
require 'fileutils'

# Ensure wiki_options setting exists (Sinatra set creates the accessor)
Precious::App.set(:wiki_options, { allow_editing: true })

context "Config file feature parity (CONF-01)" do
  include Rack::Test::Methods

  setup do
    @path = cloned_testpath('examples/revert.git')
    Precious::App.set(:gollum_path, @path)
    Precious::App.wiki_options.replace({ allow_editing: true })
    @tmpdir = Dir.mktmpdir
  end

  teardown do
    Precious::App.wiki_options.replace({ allow_editing: true })
    FileUtils.rm_rf(@path)
    FileUtils.rm_rf(@tmpdir)
  end

  def app
    Precious::App
  end

  test "config file track_current_branch sets wiki_options identically to CLI" do
    config_content = <<~RUBY
      Precious::App.settings.wiki_options[:track_current_branch] = true
    RUBY
    wiki_options, _cli = simulate_config_load({ allow_editing: true }, config_content)
    assert_equal true, wiki_options[:track_current_branch]
    get '/A'
    assert last_response.ok?
  end

  test "config file local_git_user sets wiki_options identically to CLI" do
    config_content = <<~RUBY
      Precious::App.settings.wiki_options[:local_git_user] = true
    RUBY
    wiki_options, _cli = simulate_config_load({ allow_editing: true }, config_content)
    assert_equal true, wiki_options[:local_git_user]
  end

  test "both features via config file only work together" do
    config_content = <<~RUBY
      Precious::App.settings.wiki_options[:track_current_branch] = true
      Precious::App.settings.wiki_options[:local_git_user] = true
    RUBY
    wiki_options, cli_wiki_options = simulate_config_load({ allow_editing: true }, config_content)
    assert_equal true, wiki_options[:track_current_branch]
    assert_equal true, wiki_options[:local_git_user]
    err = capture_stderr do
      Precious::App.validate_wiki_options!(wiki_options, cli_wiki_options)
    end
    assert_equal '', err
  end

  test "config file track_current_branch with CLI track_current_branch are additive" do
    config_content = <<~RUBY
      Precious::App.settings.wiki_options[:track_current_branch] = true
    RUBY
    wiki_options, cli_wiki_options = simulate_config_load({ allow_editing: true, track_current_branch: true }, config_content)
    assert_equal true, wiki_options[:track_current_branch]
    err = capture_stderr do
      Precious::App.validate_wiki_options!(wiki_options, cli_wiki_options)
    end
    assert_equal '', err
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

  def simulate_config_load(cli_opts, config_content)
    config_file = File.join(@tmpdir, "config_#{rand(100000)}.rb")
    File.write(config_file, config_content)
    # Use replace to ensure clean state (Sinatra set merges hashes)
    Precious::App.wiki_options.replace(cli_opts)
    cli_wiki_options = Precious::App.wiki_options.dup
    load config_file
    wiki_options = Precious::App.wiki_options
    [wiki_options, cli_wiki_options]
  end
end

context "Cross-source mutual exclusion (CONF-02)" do
  include Rack::Test::Methods

  setup do
    @path = cloned_testpath('examples/revert.git')
    Precious::App.set(:gollum_path, @path)
    Precious::App.wiki_options.replace({ allow_editing: true })
    @tmpdir = Dir.mktmpdir
  end

  teardown do
    Precious::App.wiki_options.replace({ allow_editing: true })
    FileUtils.rm_rf(@path)
    FileUtils.rm_rf(@tmpdir)
  end

  def app
    Precious::App
  end

  test "CLI ref conflicts with config file track_current_branch" do
    config_content = <<~RUBY
      Precious::App.settings.wiki_options[:track_current_branch] = true
    RUBY
    wiki_options, cli_wiki_options = simulate_config_load({ allow_editing: true, ref: 'main' }, config_content)
    Kernel.expects(:exit).with(1).once
    err = capture_stderr do
      Precious::App.validate_wiki_options!(wiki_options, cli_wiki_options)
    end
    assert_match(/mutually exclusive/, err)
    assert_match(/CLI \(--ref\)/, err)
    assert_match(/config file/, err)
  end

  test "config file ref conflicts with CLI track_current_branch" do
    config_content = <<~RUBY
      Precious::App.settings.wiki_options[:ref] = 'main'
    RUBY
    wiki_options, cli_wiki_options = simulate_config_load({ allow_editing: true, track_current_branch: true }, config_content)
    Kernel.expects(:exit).with(1).once
    err = capture_stderr do
      Precious::App.validate_wiki_options!(wiki_options, cli_wiki_options)
    end
    assert_match(/mutually exclusive/, err)
    assert_match(/config file/, err)
    assert_match(/CLI \(--track-current-branch\)/, err)
  end

  test "both ref and track_current_branch in config file conflict" do
    config_content = <<~RUBY
      Precious::App.settings.wiki_options[:ref] = 'main'
      Precious::App.settings.wiki_options[:track_current_branch] = true
    RUBY
    wiki_options, cli_wiki_options = simulate_config_load({ allow_editing: true }, config_content)
    Kernel.expects(:exit).with(1).once
    err = capture_stderr do
      Precious::App.validate_wiki_options!(wiki_options, cli_wiki_options)
    end
    assert_match(/mutually exclusive/, err)
  end

  test "no conflict when only track_current_branch set via config" do
    config_content = <<~RUBY
      Precious::App.settings.wiki_options[:track_current_branch] = true
    RUBY
    wiki_options, cli_wiki_options = simulate_config_load({ allow_editing: true }, config_content)
    err = capture_stderr do
      Precious::App.validate_wiki_options!(wiki_options, cli_wiki_options)
    end
    assert_equal '', err
  end

  test "no conflict when only ref set via config" do
    config_content = <<~RUBY
      Precious::App.settings.wiki_options[:ref] = 'main'
    RUBY
    wiki_options, cli_wiki_options = simulate_config_load({ allow_editing: true }, config_content)
    err = capture_stderr do
      Precious::App.validate_wiki_options!(wiki_options, cli_wiki_options)
    end
    assert_equal '', err
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

  def simulate_config_load(cli_opts, config_content)
    config_file = File.join(@tmpdir, "config_#{rand(100000)}.rb")
    File.write(config_file, config_content)
    # Use replace to ensure clean state (Sinatra set merges hashes)
    Precious::App.wiki_options.replace(cli_opts)
    cli_wiki_options = Precious::App.wiki_options.dup
    load config_file
    wiki_options = Precious::App.wiki_options
    [wiki_options, cli_wiki_options]
  end
end

context "Startup summary (development mode)" do
  include Rack::Test::Methods

  setup do
    @path = cloned_testpath('examples/revert.git')
    Precious::App.set(:gollum_path, @path)
    @original_env = Precious::App.environment
  end

  teardown do
    Precious::App.wiki_options.replace({ allow_editing: true })
    Precious::App.set(:environment, @original_env)
    FileUtils.rm_rf(@path)
  end

  def app
    Precious::App
  end

  test "startup summary shows features with source attribution" do
    Precious::App.set(:environment, :development)
    wiki_options = { allow_editing: true, track_current_branch: true, local_git_user: true }
    cli_wiki_options = { allow_editing: true, track_current_branch: true }
    err = capture_stderr do
      generate_startup_summary(wiki_options, cli_wiki_options)
    end
    assert_match(/Active features:/, err)
    assert_match(/track-current-branch: ON \(CLI\)/, err)
    assert_match(/local-git-user: ON \(config file\)/, err)
  end

  test "startup summary is silent in production mode" do
    Precious::App.set(:environment, :production)
    wiki_options = { allow_editing: true, track_current_branch: true, local_git_user: true }
    cli_wiki_options = { allow_editing: true, track_current_branch: true }
    err = capture_stderr do
      generate_startup_summary(wiki_options, cli_wiki_options)
    end
    assert_equal '', err
  end

  test "startup summary is silent when no features active" do
    Precious::App.set(:environment, :development)
    wiki_options = { allow_editing: true }
    cli_wiki_options = { allow_editing: true }
    err = capture_stderr do
      generate_startup_summary(wiki_options, cli_wiki_options)
    end
    assert_equal '', err
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

  # Replicates the exact startup summary logic from bin/gollum
  def generate_startup_summary(wiki_options, cli_wiki_options)
    if Precious::App.environment == :development
      features = []
      if wiki_options[:track_current_branch]
        src = cli_wiki_options.key?(:track_current_branch) ? "CLI" : "config file"
        features << "track-current-branch: ON (#{src})"
      end
      if wiki_options[:local_git_user]
        src = cli_wiki_options.key?(:local_git_user) ? "CLI" : "config file"
        features << "local-git-user: ON (#{src})"
      end
      $stderr.puts "Active features: #{features.join(', ')}" unless features.empty?
    end
  end
end

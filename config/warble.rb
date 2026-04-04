Warbler::Config.new do |config|
  # Route jruby-rack's internal logging to stdout so init errors are visible
  # instead of being swallowed by SLF4J NOP logger (Jetty default).
  config.webxml['jruby.rack.logging'] = 'stdout'
  # Warbler skips dotfiles by default. The Sprockets manifest is a dotfile
  # (.sprockets-manifest-*.json) and must be present for static asset serving
  # to work — without it, Sprockets falls back to live compilation (which fails
  # because sassc is not in the WAR).
  config.includes.include('lib/gollum/public/assets/.sprockets-manifest-*.json')
  # Disable jruby-rack's default 'patch' dechunk mode which tries to load
  # rack/chunked — a file removed in Rack 3. With Rack 3 there is no
  # Rack::Chunked::Body to patch, so dechunking is a no-op anyway.
  config.webxml['jruby.rack.response.dechunk'] = 'false'
end

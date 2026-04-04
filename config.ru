# Use this file to launch Gollum as a Rack app or alter startup behaviour.
#
# For more information and examples:
# - https://github.com/gollum/gollum/wiki/Gollum-via-Rack
# - https://github.com/gollum/gollum#config-file

require 'gollum/app'

# When running inside a WAR, Dir.pwd is the app root extracted from the archive.
# Users can override GOLLUM_PATH to point at an external git repository.
gollum_path = ENV.fetch('GOLLUM_PATH', Dir.pwd)

Precious::App.set(:environment, ENV.fetch('RACK_ENV', 'production').to_sym)
Precious::App.set(:gollum_path, gollum_path)
Precious::App.set(:wiki_options, { allow_uploads: false, allow_editing: true })

run Precious::App

require 'pathname'
require 'sinatra/base'
require 'sequel'
require 'omniauth'
require 'openid/store/filesystem'
require 'json'

module FFXIV
  Root = Pathname.new(File.expand_path(File.join(File.dirname(__FILE__), '..')))
  Database = Sequel.connect(YAML.load_file(Root + "config" + "database.yml"), :logger => Logger.new(STDOUT))
end
Sequel::Model.plugin :validation_helpers

path = FFXIV::Root + "lib" + "ffxiv"
require path + "application"
require path + "row"
require path + "category"
require path + "item"
require path + "user"
require path + "character"
require path + "note"
require path + "price"

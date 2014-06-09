# this file is required by worker processes in order to load the command sets

include Yoleaux::CommandSetHelper

Dir.glob('./commands/*.rb').each do |command_set|
  require command_set
end


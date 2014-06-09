require "yoleaux/version"

require 'socket'
require 'time'
require 'securerandom'
require 'ostruct'
require 'yaml'

require "yoleaux/bot"
require "yoleaux/command_set"
require "yoleaux/database"
require "yoleaux/queue"
require "yoleaux/scheduler"
require "yoleaux/sender"
require "yoleaux/structs"
require "yoleaux/worker"

module Yoleaux
  def self.new *a, &b
    Yoleaux::Bot.new *a, &b
  end
  
  # normalises a nick according to IRC's casefolding rules
  def self.nick nick
    nick.downcase.tr('{}^\\', '[]~|')
  end
end

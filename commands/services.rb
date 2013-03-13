
# This shows how you can implement command-sets that (a): register
# commands dynamically and (b): don't use the default CommandSet API.
#
# There is a race condition here concerning access to the services
# database, if two people call (add|del)-command(-help) simultaneously.
# Worst case scenario, someone has to type .add-command twice, but it
# would be nice to come up with a mutex mechanism for DB access to fix
# this. (also a way to get access to the inqueue and outqueue from the
# class, ie. without the env object being passed to the instance.)
#
# (In fact, this package is very roughly-made in general, and could do
# with a rewrite.)

require 'net/http'
require 'securerandom'

class Yoleaux
  class ServiceCommands
    @@special_commands = %w{add-command del-command command-help o}
    @@commands = {}
    
    def initialize env
      @env = env
    end
    
    def call
      self.class.load_commands_list
      command = normalise_name @env.command
      case command
      when 'add-command'
        m = @env.args.to_s.match(/\A(?::([^\s]+) )?([^\s]+) (.+)\Z/)
        if not m
          return respond "Syntax: #{@env.prefix}add-command name url"
        end
        _, type, name, uri = m.to_a
        type ||= 'oblique'
        type.downcase!
        name = normalise_name name
        if @@commands.has_key? name and not @@commands[name][:owner] == @env.nick
          respond 'Sorry, that command name is already taken.'
        else
          @@commands[name] = {:uri => uri, :type => type, :owner => @env.nick}
          self.class.save_commands_list
          respond "Added command #{name}: #{type} service. (Please add a help string with \"#{@env.prefix}command-help #{name} ...\")"
        end
      when 'del-command'
        name = @env.args.to_s
        name = normalise_name name
        if name.empty?
          respond "Syntax: #{@env.prefix}del-command name"
        else
          if not @@commands.has_key? name
            respond "#{@env.nick}: Sorry, there's no such service to delete"
          else
            command = @@commands[name]
            return respond("#{@env.nick}: Sorry, only the service's owner, #{@@commands[name][:owner]}, can delete that service") unless @@commands[name][:owner] == @env.nick or @env.admin
            @@commands.delete name
            self.class.save_commands_list
            respond("#{@env.nick}: I deleted the #{@env.prefix}#{name} command")
          end
        end
      when 'command-help'
        name, help = @env.args.to_s.split(' ', 2)
        name = normalise_name name
        if @@commands.has_key? name
          service = @@commands[name]
          if service[:owner] == @env.nick or @env.admin
            service[:help] = help
            self.class.save_commands_list
            respond "#{@env.nick}: Set help string of #{@env.prefix}#{name}. Thank you!"
          else
            respond "#{@env.nick}: Sorry, only the owner of that service, #{service[:owner]}, can set its help string."
          end
        else
          respond "#{@env.nick}: Sorry, that command doesn't seem to exist!"
        end
      else
        prepend = ''
        if command == 'o'
          command, args = @env.args.to_s.split(' ', 2)
          @env.args = args
          prepend = "(#{@env.prefix}o is deprecated; use #{@env.prefix}#{command}) "
        end
        if @@commands.has_key? command
          run_command @@commands[command], prepend
        end
      end
    end
    
    def run_command command, prepend=''
      # todo: better error reportage
      case command[:type]
      when 'oblique'
        resp = Net::HTTP.get_response URI(command[:uri].gsub(/\$\{(?:nick|args|argurl|sender)\}/i) do |m|
          if m.downcase.include? 'nick'
            URI.encode(@env.nick, /./)
          elsif m.downcase.include? 'args'
            URI.encode(@env.args.to_s, /./)
          elsif m.downcase.include? 'argurl'
            URI.encode((@env.args or @env.last_url).to_s, /./)
          elsif m.downcase.include? 'sender'
            URI.encode(@env.channel, /./)
          end
        end)
        if not resp['Content-Type'].downcase.include? 'text/plain'
          return respond "#{@env.nick}: Sorry: that command is a web-service, but it didn't respond in plain text."
        elsif (lines=resp.body.rstrip.lines.to_a).length > 1 or lines.first.bytesize > (500-prepend.bytesize)
          return respond "#{@env.nick}: Sorry: that command is a web-service, but its response was too long."
        else
          response = "#{prepend}#{lines.first}"
          response.force_encoding('utf-8')
          response.force_encoding('iso-8859-1').encode!('utf-8') if not response.valid_encoding?
          respond response
        end
#       when 'yoleaux'
#         query = {nick: @env.nick,
#                  channel: @env.channel,
#                  prefix: @env.prefix,
#                  name: normalise_name(@env.command),
#                  args: @env.args.to_s,
#                  last_url: @env.last_url}
#         response = Net::HTTP.get URI(command[:uri]+'?'+URI.encode_www_form(query))
#         respond response
      else
        respond "#{@env.nick}: ?"
      end
    end
    
    def respond message
      @env.out.send(Message.new(@env.channel, message.gsub(/[\r\n]/, '').strip))
    end
    
    def self.priority; 2; end
    def self.has_command? command
      load_commands_list
      command = normalise_name command
      @@special_commands.include?(command) or @@commands.has_key?(command)
    end
    def self.has_callback? *a; false; end
    def self.command_list; load_commands_list; @@special_commands+@@commands.keys; end
    def self.call env
      self.new(env).call
    end
    def self.help command
      load_commands_list
      command = normalise_name command
      if @@commands[command]
        @@commands[command][:help]
      elsif @@special_commands.include? command
        case command
        when 'add-command'
          'Add a command of your own creation as a web service'
        when 'command-help'
          'Add help to a web-service command'
        when 'del-command'
          'Delete a web-service command'
        when 'o'
          '(Deprecated) Call a web-service command'
        end
      else
        nil
      end
    end
    
    def self.load_commands_list
      db = "#{Yoleaux::BASE}/services.db"
      File.write(db, Marshal.dump({})) if not File.exist? db
      @@commands = Marshal.load File.read(db)
    end
    def self.save_commands_list
      db = "#{Yoleaux::BASE}/services.db"
      temp = db+".#{SecureRandom.hex(4)}"
      File.write(temp, Marshal.dump(@@commands))
      File.rename temp, db
    end
    
    def self.normalise_name name
      name.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-+|-+$/, '')
    end
    def normalise_name name; self.class.normalise_name name; end
  end
end

Yoleaux.command_sets << [:services, Yoleaux::ServiceCommands]


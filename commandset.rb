
# do you like my artworks? i call this one: WORLD'S WORST HAX

class Yoleaux
  class CommandSet
    def self.call *a, &b
      self.new.call *a, &b
    end
    
    def initialize
      @commands = self.class.commands
      @callbacks = self.class.callbacks
      @name = self.class.name
    end
    
    attr_reader :env
    def call env
      @env = env
      if env.respond_to? :callback
        callback = @callbacks[env.callback]
        (puts "no such callback #{env.callback} ..."; return) if not callback # callback must be obsolete
        instance_exec *(@env.args), &callback
      elsif env.respond_to? :command
        command = env.command
        until command.is_a? Proc or command.nil?
          command = @commands[command]
        end
        raise NoSuchCommand if command.nil?
        begin
          instance_eval(&command)
        rescue CommandHaltStackJump
        end
      end
    end
    
    @@switchre = /^((?::\S+\s)+)?(.*)$/
    
    def argstr
      (@env.args or '').strip
    end
    
    def switches
      m = argstr.match(@@switchre) or return []
      return [] unless m[1]
      m[1].split(/\s+/).map {|sw| sw[1..-1] }
    end
    def argtext
      text = (argstr.match(@@switchre) or [])
      text = (text[2] or '')
      text.strip
    end
    
    def docs command=nil
      if command
        command = @commands[command] until @commands[command].is_a? Proc
        self.class.command_docs[normalize_command_name(command)]
      else
        docs @env.command
      end
    end
    
    def halt *a
      raise CommandHaltStackJump
    end
    
    def require_argstr
      if argstr.empty?
        respond (docs or "Sorry, that command requires an argument.")
        halt
      end
    end
    def require_argtext
      if argtext.empty?
        respond (docs or "Sorry, that command requires an argument.")
        halt
      end
    end
    def admin_only
      unless @env.admin
        halt respond "#{@env.nick}: Sorry, this command is admin-only."
      end
    end
    
    def respond text
      send @env.channel, text
    end
    def action text
      respond "\x01ACTION #{text}\x01"
    end
    
    def send channel, message
      message = message.gsub(/[\r\n]/, '').strip
      @env.out.send Message.new channel, message
    end
    def raw_send command, params=[], text=nil
      @env.out.send RawMessage.new command, params, text
    end
    def core_eval vars={}, code
      @env.out.send CoreEval.new(@env.command_id, code, vars)
      @env.in.receive
    end
    
    def schedule time, callback, *args
      @env.out.send ScheduledTask.new time, nil, [@name, callback], args
    end
    def on_next_message to, callback, *args
      @env.out.send Tell.new to, [@name, callback], args
    end
    
    def nick *args
      Yoleaux.nick(*args)
    end
    
    def db name, val={}
      DatabaseProxy.new(name, val, @env.in, @env.out)
    end
    
    def normalize_command_name *a; self.class.normalize_command_name *a; end
    
    class << self
      def init
        @commands = {}
        @command_docs = {}
        @callbacks = {}
        
        @awaiting_docs = [] # hack hack hack
      end
      
      attr_accessor :name
      attr_reader :commands, :command_docs, :callbacks
      
      def command name, docs=nil, &block
        @commands[normalize_command_name(name)] = block
        @command_docs[normalize_command_name(name)] = docs if docs
        
        @awaiting_docs.reject! do |waiter|
          from, to = waiter
          if to == normalize_command_name(name)
            @command_docs[normalize_command_name(from)] = docs if docs
            true
          else
            false
          end
        end
      end
      def alias_command from, to
        @commands[normalize_command_name(from)] = normalize_command_name(to)
        @command_docs[normalize_command_name(from)] = @command_docs[normalize_command_name(to)] or (@awaiting_docs << [normalize_command_name(from), normalize_command_name(to)])
      end
      
      def command_list
        @commands.keys
      end
      
      def callback name, &block
        @callbacks[name] = block
      end
      
      def normalize_command_name name
        name.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-+|-+$/, '')
      end
      
      def priority; 1; end
      def has_command? command
        if command.to_s[0] == "\x01"
          @callbacks.has_key? command[1..-1].to_sym
        else
          @commands.has_key? normalize_command_name(command)
        end
      end
      
      def help command
        @command_docs[normalize_command_name(command)]
      end
      
      # namespacing helper method
      def helpers &block
        class_eval(&block)
      end
      def inherited subclass
        subclass.init
      end
    end
    
    init
    
    class DatabaseProxy
      def initialize name, val={}, inqueue, outqueue
        @name = name
        @inqueue = inqueue
        @outqueue = outqueue
        action :init, val
      end
      
      def [] key
        action :fetch_key, key
      end
      def []= key, value
        action :set_key, key, value
      end
      def fetch_all
        action :fetch_all
      end
      alias fetch fetch_all
      def replace value
        action :replace, value
      end
      
      private
      def action name, *args
        @outqueue.send DatabaseAction.new(name, [@name, *args])
        @inqueue.receive
      end
    end
  end
  
  module CommandSetHelper
    def command_set name, &block
      pkg = Class.new(CommandSet, &block)
      Yoleaux.command_sets << [name, pkg]
      pkg.name = name
    end
  end
  
  class CommandHaltStackJump < Exception; end
  class NoSuchCommand < Exception; end
end


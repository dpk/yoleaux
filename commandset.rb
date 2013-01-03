
# do you like my artworks? i call this one: WORLD'S WORST HAX

class Yoleaux
  class CommandSet
    def self.call *a, &b
      self.new.call *a, &b
    end
    
    def initialize
      @commands = self.class.commands
      @callbacks = self.class.callbacks
    end
    
    attr_reader :env
    def call env
      @env = env
      command = env.command
      if command[0] == "\x01"
        cbname = command[1..-1].to_sym
        callback = @callbacks[cbname]
        instance_exec *(@env.args), &callback
      else
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
        respond docs
        halt
      end
    end
    def require_argtext
      if argtext.empty?
        respond docs
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
    def core_eval code
      @env.out.send CoreEval.new(@env.command_id, code)
      @env.in.receive
    end
    
    def schedule time, callback, *args
      @env.out.send ScheduledTask.new time, nil, callback, args
    end
    def on_next_message to, callback, *args
      @env.out.send Tell.new to, callback, args
    end
    
    def db name
      DatabaseProxy.new(name, @env.in, @env.out)
    end
    
    def normalize_command_name *a; self.class.normalize_command_name *a; end
    
    class << self
      def init
        @commands = {}
        @command_docs = {}
        @callbacks = {}
      end
      
      attr_reader :commands, :command_docs, :callbacks
      
      def command name, docs=nil, &block
        @commands[normalize_command_name(name)] = block
        @command_docs[normalize_command_name(name)] = docs if docs
      end
      def alias_command from, to
        @commands[normalize_command_name(from)] = normalize_command_name(to)
        @command_docs[normalize_command_name(from)] = @command_docs[normalize_command_name(to)]
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
      def initialize name, inqueue, outqueue
        @name = name
        @inqueue = inqueue
        @outqueue = outqueue
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
      Yoleaux.command_sets << [name, Class.new(CommandSet, &block)]
    end
  end
  
  class CommandHaltStackJump < Exception; end
  class NoSuchCommand < Exception; end
end


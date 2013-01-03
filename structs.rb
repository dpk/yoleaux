
# various data structures that get passed between processes;
# most of these could be replaced by Structs

class Yoleaux
  class Command
    attr_accessor :id, :command, :args, :user, :channel, :handler_process, :started, :extra
    def initialize id, command, args, user, channel, extra={}
      @id = id
      @command = command
      @args = args
      @user = user
      @channel = channel
      @extra = extra
      @done = false
    end
    
    def started?; not not @started; end
    def started!; @started = Time.now; end
    def done?; @done; end
    def done!; @done = true; end
  end
  class CommandStatus
    attr_reader :status, :command_id
    def initialize status, command_id
      @status = status
      @command_id = command_id
    end
  end
  class Message < Struct.new(:channel, :message); end
  class RawMessage < Struct.new(:command, :params, :text); end
  class CoreEval < Struct.new(:command_id, :code); end
  class ScheduledTask
    attr_reader :time, :command_set, :callback, :args
    def initialize time, command_set, callback, args
      @time = time
      @command_set = command_set
      @callback = callback
      @args = args
    end
  end
  class DatabaseAction
    attr_reader :action, :args
    def initialize action, args
      @action = action
      @args = args
    end
  end
  class Tell
    attr_reader :to, :callback, :args
    def initialize to, callback, args
      @to = to
      @callback = callback
      @args = args
    end
  end
end

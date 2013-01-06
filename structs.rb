
# various data structures that get passed between processes;
# most of these could be replaced by Structs

class Yoleaux
  class Dispatchable < OpenStruct
    def initialize id, other
      super({:id => id, :done => false, :started => nil, :handler_process => nil}.merge(other))
    end
    
    def started?; not not self.started; end
    def started!; self.started = Time.now; end
    def done?; self.done; end
    def done!; self.done = true; end
  end
  class Command < Dispatchable
  end
  class Callback < Dispatchable
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

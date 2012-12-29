
class Yoleaux
  class Worker
    attr_reader :pid, :inqueue, :outqueue
   
    def initialize pid, inqueue, outqueue
      @pid = pid
      @inqueue = inqueue
      @outqueue = outqueue
      @busy = false
    end
   
    def stop
      if @pid == $$
        if @busy
          @stopasap = true
        else
          finishup
        end
      else
        ::Process.kill 'TERM', @pid
      end
    end
    def kill
      if @pid == $$
        exit 1
      else
        ::Process.kill 'KILL', @pid
      end
    end
   
    def loop
      @inqueue.each do |command|
        begin
          @busy = true
          @outqueue.send CommandStatus.new :started, command.id
          
          if command.command.downcase == 'help'
            command.command = command.args.to_s
            help = true
          else
            help = false
          end
          
          namespace, cname = (command.command.include?('.') ? command.command.split('.') : [nil, command.command])
          command_set = nil
          
          Yoleaux.command_sets.sort {|a,b| b[1].priority <=> a[1].priority }.each do |set|
            sname, set = set
            
            if namespace and sname.to_s == namespace
              command_set = set
              break
            elsif set.has_command? cname
              command_set = set
            end
          end
          
          if help
            if command_set
              @outqueue.send Message.new(command.channel, (command_set.help(cname) or "#{command.user}: Sorry, no help is available for #{command.command}."))
            elsif not command.command.empty?
              @outqueue.send Message.new(command.channel, "#{command.user}: Sorry, no help is available for #{command.command}.")
            else
              @outqueue.send Message.new(command.channel, "I'm yoleaux.")
            end
          else
            if command_set and command_set.has_command? cname
              env = OpenStruct.new command.extra.merge({:nick => command.user,
                                   :command => cname,
                                   :out => @outqueue,
                                   :in => @inqueue,
                                   :channel => command.channel,
                                   :args => command.args,
                                   :command_id => command.id})
              command_set.call env
            end
          end
          
          @outqueue.send CommandStatus.new :done, command.id
        ensure
          @busy = false
          stop if @stopasap
        end
      end
    end
    
    def finishup
      return nil unless @pid == $$
      @inqueue.close_read
      @outqueue.close_write
      exit 0
    end
  end
end


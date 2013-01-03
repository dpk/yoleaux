
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
          command_name = command.command.downcase
          
          case command_name
          when 'help'
            argstr = command.args.to_s.strip
            if argstr.empty?
              @outqueue.send Message.new command.channel, "#{command.user}: I'm yoleaux. Type #{command.extra[:prefix]}commands to get a list of all the things I can do."
            elsif set = set_for(argstr) and help=set.help(cname(argstr))
              @outqueue.send Message.new command.channel, "#{help}"
            else
              @outqueue.send Message.new command.channel, "#{command.user}: Sorry, no help is available for #{argstr}."
            end
          when 'commands'
            argstr = command.args.to_s.strip
            if argstr.empty?
              @outqueue.send Message.new command.channel, "Commands are divided into categories: #{Yoleaux.command_sets.map(&:first).join ', '}. Use #{command.extra[:prefix]}commands <category> to get a list of the commands in each."
            else
              set = nil
              Yoleaux.command_sets.sort {|a,b| b[1].priority <=> a[1].priority }.each do |s|
                if s.first.to_s == argstr.downcase
                  set = s[1]
                  break
                end
              end
              
              if set.nil?
                @outqueue.send Message.new command.channel, "There's no category called #{argstr}."
              else
                @outqueue.send Message.new command.channel, "Commands in #{argstr.downcase}: #{set.command_list.join ', '}. Use .help to get information about them."
              end
            end
          else
            command_set = set_for command_name
            if command_set and command_set.has_command? cname(command_name)
              env = OpenStruct.new command.extra.merge({:nick => command.user,
                                   :command => cname(command_name),
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
    
    def cname command_name
      namespace, cname = (command_name.include?('.') ? command_name.split('.') : [nil, command_name])
      cname
    end
    
    def set_for command_name
      namespace, cname = (command_name.include?('.') ? command_name.split('.') : [nil, command_name])
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
      command_set
    end
   
    def finishup
      return nil unless @pid == $$
      @inqueue.close_read
      @outqueue.close_write
      exit 0
    end
  end
end


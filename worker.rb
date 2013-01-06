
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
      @inqueue.each do |input|
        begin
         @busy = true
         @outqueue.send CommandStatus.new :started, input.id
          case input
          when Command
            handle_command input
          when Callback
            handle_callback input
          end
          @outqueue.send CommandStatus.new :done, input.id
        ensure
          @busy = false
          stop if @stopasap
        end
      end
    end
    
    def handle_command command
      command_name = command.name.downcase
    
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
            @outqueue.send Message.new command.channel, "Commands in #{argstr.downcase}: #{set.command_list.map(&:to_s).sort.join ', '}. Use .help to get information about them."
          end
        end
      else
        command_set = set_for command_name
        if command_set and command_set.has_command? cname(command_name)
          env = OpenStruct.new :nick => command.user,
                               :command => cname(command_name),
                               :last_url => command.last_url,
                               :admin => command.admin,
                               :prefix => command.prefix,
                               :out => @outqueue,
                               :in => @inqueue,
                               :channel => command.channel,
                               :args => command.args,
                               :command_id => command.id
          begin
            command_set.call env
          rescue NoSuchCommand
            # hmm, what?! there was a command per has_command? but it didn't call. oh well ...
          end
        end
      end
    end
    
    def handle_callback callback
      command_set = nil
      if callback.name.is_a? Array
        setname, cbname = callback.name
        Yoleaux.command_sets.each do |set|
          if setname == set.first
            command_set = set[1]
          end
        end
      else
        Yoleaux.command_sets.each do |set|
          if set[1].has_callback? callback.name
            command_set = set[1]
          end
        end
      end
      # no command set? perhaps it was removed since the callback data was saved. continue:
      (puts "no command set for #{callback.name} ..."; return) if not command_set
      cbname = (callback.name.is_a?(Array) ? callback.name[1] : callback.name)
      env = OpenStruct.new :callback => cbname,
                           :args => callback.args,
                           :nick => (callback.user if callback.respond_to? :user),
                           :channel => (callback.channel if callback.respond_to? :channel),
                           :out => @outqueue,
                           :in => @inqueue
      
      command_set.call env
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


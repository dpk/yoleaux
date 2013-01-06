
command_set :admin do
  command :join, 'Get the bot to join a channel and auto-join it on startup' do
    admin_only
    require_argstr
    raw_send 'JOIN', [], argstr
    core_eval <<-EOF
      @channels << command.args
      write_config
    EOF
  end
  command :visit, 'Get the bot to join a channel, but do not auto-join it' do
    admin_only
    require_argstr
    raw_send 'JOIN', [], argstr
  end
  
  command :part, 'Get the bot to part a channel and remove from the auto-join list' do
    admin_only
    raw_send 'PART', [(argstr.empty? ? env.channel : argstr)], "#{env.nick} asked me to leave."
    core_eval <<-EOF
      @channels.delete command.args
      write_config
    EOF
  end
  command :leave, 'Get the bot to part a channel, but do not remove it from auto-join' do
    admin_only
    raw_send 'PART', [(argstr.empty? ? env.channel : argstr)], "#{env.nick} asked me to leave."
  end
  
  command :nick, "Change the bot's nick" do
    admin_only
    require_argstr
    raw_send 'NICK', [], argstr
    core_eval <<-EOF
      @nick = command.args
      write_config
    EOF
  end
  
  command :processes, 'List the processes the bot is currently running' do
    admin_only
    sender, scheduler, workers = core_eval '[@sender.pid, @scheduler.pid, @workers.map(&:pid)]'
    respond "Processes: sender: #{sender}; scheduler: #{scheduler}; workers: #{workers.join ', '}"
  end
  command :prefix, "Set the bot's command prefix" do
    admin_only
    require_argstr
    respond "#{env.nick}: Set prefix to '#{argstr}'"
    core_eval <<-EOF
      @prefix = command.args.to_s
      write_config
    EOF
  end
  
  command :private, 'Mark this channel as private' do
    admin_only
    if argstr.empty?
      channel = env.channel
    else
      channel = argstr
    end
    ispriv = core_eval ({:channel => channel}), <<-EOF
      if @privacy.has_key? channel
        @privacy[channel]['private'] = (not @privacy[channel]['private'])
      else
        @privacy[channel] = {}
        @privacy[channel]['private'] = true
      end
      write_config
      @privacy[channel]['private']
    EOF
    puts ispriv.inspect
    respond "#{env.nick}: #{channel} is now marked as #{(ispriv ? 'private' : 'public')}."
  end
  command :private_prefix, 'Set a prefix for a channel for which messages will not be logged to .seen' do
    admin_only
    require_argtext
    if argtext[0] == '#'
      channel, prefix = argtext.split ' ', 2
    else
      channel = env.channel
      prefix = argtext
    end
    log_time = (not %w{pr priv private pa para paranoid}.include? switches.first)
    privopt = core_eval ({:channel => channel, :prefix => prefix, :log_time => log_time}), <<-EOF
      @privacy[channel] = {} if not @privacy.has_key? channel
      if prefix.nil? or prefix.empty?
        @privacy[channel].delete 'noseen_prefix'
        @privacy[channel].delete 'noseen_log_time'
      else
        @privacy[channel]['noseen_prefix'] = prefix
        @privacy[channel]['noseen_log_time'] = log_time
      end
      write_config
      @privacy[channel]
    EOF
    if privopt['noseen_prefix']
      respond "#{env.nick}: OK, private-prefix for #{channel} set to '#{prefix}' with paranoid mode #{privopt['noseen_log_time'] ? 'off' : 'on'}."
    else
      respond "#{env.nick}: OK, disabled the private-prefix for #{channel}."
    end
  end
  # not admin-only; all users can query privacy options:
  command :privacy, 'Find out what privacy options are set in this channel' do
    privopt = core_eval({:channel => env.channel}, '@privacy[channel]')
    if not privopt or (not privopt['private'] and not privopt['noseen_prefix'])
      respond "#{env.nick}: This channel is public: I will record the things you say and repeat them when I am asked when I last saw you."
    elsif privopt['private']
      respond "#{env.nick}: This channel is private: I will not record anything you say in here, nor the times you have been active."
    elsif privopt['noseen_prefix']
      respond "#{env.nick}: This channel is public: If I am asked when I last saw you, I will repeat the last thing you said, but if you prefix lines with '#{privopt['noseen_prefix']}' then I will #{privopt['noseen_log_time'] ? 'only mention the time you last spoke' : 'not'}."
    end
  end
  
  command :quit, 'Tell the bot to shut down' do
    admin_only
    core_eval 'stop command.user'
  end
  
  command :reload, 'Reload the commands by restarting all workers' do
    admin_only
    core_eval <<-EOF
      @reloading = OpenStruct.new :started => Time.now, :channel => command.channel, :old_workers => @workers.dup, :reloader => command.user
      stop_workers
      true
    EOF
  end
  
  command :core_eval, 'Evaluate some Ruby code in the bot core' do
    admin_only
    require_argstr
    respond core_eval("(#{argstr}).inspect").to_s
  end
end


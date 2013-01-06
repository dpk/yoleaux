
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


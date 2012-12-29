
## ADMIN COMMANDS ARE HANDLED SPECIALLY! ##
## Do *not* mess with the commands in this file unless you *really* know
## what you're doing. The commands here behave *very* differently from
## other commands:
##
## * They are handled in main process; thus, if they crash, the whole
##   bot crashes, and if they take too long, the whole bot is blocked from
##   doing anything.
## * They're evaled in the context of the main Yoleaux object, instead of
##   the CommandSet. Therefore, you can't define helpers in this package.
##   You can mess up the bot pretty good, though.
## * They're not reloaded when you do 'reload.
## * Nobody can use these commands except admins.
##
## I *highly* recommend using admin_only in a regular package instead of
## changing this file.

command_set :admin do
  command :join, 'Get the bot to join a channel and auto-join it on startup' do |command|
    @channels << command.args
    send 'JOIN', [], command.args
    write_config
  end
  command :visit, 'Get the bot to join a channel, but do not auto-join it' do |command|
    send 'JOIN', [], command.args
  end
  
  command :part, 'Get the bot to part a channel and remove from the auto-join list' do |command|
    @channels.delete command.args
    send 'PART', [command.args], "#{command.user} asked me to leave."
    write_config
  end
  command :leave, 'Get the bot to part a channel, but do not remove it from auto-join' do |command|
    send 'PART', [command.args], "#{command.user} asked me to leave."
  end
  
  command :nick, "Change the bot's nick" do |command|
    @nick = command.args
    send 'NICK', [], command.args
    write_config
  end
  
  command :processes, 'List the processes the bot is currently running' do |command|
    send 'PRIVMSG', [command.channel], "Processes: sender: #{@sender.pid}; scheduler: #{@scheduler.pid}; workers: #{@workers.map(&:pid).join ', '}"
  end
  command :prefix, "Set the bot's command prefix" do |command|
    @prefix = command.args.to_s
    send 'PRIVMSG', [command.channel], "#{command.user}: Set prefix to '#@prefix'"
    write_config
  end
  
  command :quit, 'Tell the bot to shut down' do |command|
    stop command.user
  end
  
  command :reload, 'Reload the commands by restarting all workers' do |command|
	@reloading = OpenStruct.new :started => Time.now, :channel => command.channel, :old_workers => @workers.dup, :reloader => command.user
	stop_workers
  end
end


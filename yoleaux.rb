# encoding: utf-8

require 'socket'
require 'time'
require 'securerandom'
require 'ostruct'
require 'yaml'

require './commandset'
require './scheduler'
require './structs'
require './database'
require './worker'
require './queue'
require './sender'

class Yoleaux
  @@linere = /(?::([^ ]+) +)?((?:.(?! :))+.)(?: +:?(.*))?/
  @@command_sets = []
  @@uri_regexp = %r@(?i)\b((?:[a-z][\w-]+:(?:/{1,3}|[a-z0-9%])|www\d{0,3}[.]|[a-z0-9.\-]+[.][a-z]{2,4}/)(?:[^\s()<>]+|\(([^\s()<>]+|(\([^\s()<>]+\)))*\))+(?:\(([^\s()<>]+|(\([^\s()<>]+\)))*\)|[^\s`!()\[\]{};:'".,<>?«»“”‘’]))@
  
  BASE = "#{ENV['HOME']}/.yoleaux"
  
  STOPSIG = "\x01"
  CHLDSIG = "\x02"
  
  def self.command_sets; @@command_sets; end
  
  def initialize
    read_config
    @log = STDOUT
    # self-pipe
    @spr, @spw = IO.pipe
  end
  
  def start
    @sent_times = []
    @last_msgs = []
    @stopasap = false
    @reloading = false
    @socket = TCPSocket.new @server, @port
    start_processes
    send 'NICK', [], @nick
    send 'USER', [@user, '0', '*'], @realname
    
    @last_url = {}
    @seendb = Database.new :seen, {}
    @telldb = Database.new :tell, {}
    
    trap('INT')  { @spw.write_nonblock STOPSIG }
    trap('CHLD') { @spw.write_nonblock CHLDSIG }
    
    handle_loop
  end
  
  def stop who=nil
    stop_processes
    @stopasap = true
    @stopblame = who
  end
  
  def join channel
    send 'JOIN', [], channel
  end
  
  def handle_loop
    @commands = {}
    @command_ctr = 0
    loop do
      rsocks = []
      rsocks << @socket
      rsocks << @spr
      rsocks << @scheduler.outqueue
      (rsocks << @sender.outqueue) if @sender
      rsocks << @workers.map(&:outqueue)
      rsocks.flatten!
      selected = Queue.select(rsocks, [], [], 2)
      if selected
        rs, ws, es = selected
        rs.each do |r|
          if r == @socket
            line = recv
            event = parse_line line
            handle_event event
            if command = parse_command(event)
              if @stopasap
                privmsg command.channel, "#{command.user}: Sorry, I can't take any more commands because I'm about to quit."
              else
                dispatch_command command
              end
            end
          elsif r == @spr
            sig = @spr.read_nonblock(1)
            case sig
            when STOPSIG
              stop ENV['USER']
            when CHLDSIG
              while (pid, stat = ::Process.wait2(-1, ::Process::WNOHANG) rescue nil)
                @log.puts "stopped process: #{pid}: #{stat.exitstatus}"
                @workers.reject! {|p| p.pid == pid }
                if @stopasap
                  if @workers.empty?
                    send 'QUIT', [], "#@stopblame made me do it!"
                    @socket.close
                    @socket = nil
                    return
                  end
                elsif @reloading
                  @log.puts "reloading worker #{pid} ..."
                  start_worker
                  @commands.each do |id, comm|
                    if not comm.started? and not comm.done? and comm.handler_process.pid == pid
                      dispatch_command comm
                    end
                  end
                  if (@reloading.old_workers & @workers).empty?
                    privmsg @reloading.channel, "#{@reloading.reloader}: Reload done (took #{'%.3f' % (Time.now - @reloading.started)}s)."
                    @reloading = false
                  end
                elsif not stat.exitstatus.zero?
                  @log.puts "restarting crashed worker #{pid} ..."
                  start_worker
                  @commands.each do |id, comm|
                    # there's some kind of race condition-y heisenbug here (bug: reloadcrash), which is why we check that there is a handler before comparing pids
                    if comm.handler_process and comm.handler_process.pid == pid
                      if comm.started? and not comm.done?
                        privmsg comm.channel, "#{comm.user}: Sorry, that command (#@prefix#{comm.command}) crashed."
                        comm.done!
                      elsif not comm.started?
                        dispatch_command comm
                      end
                    end
                  end
                end
              end
            end
          elsif r == @scheduler.outqueue
            begin
              time, task = r.receive
            rescue EOFError
              next
            end
            case task
            when ScheduledTask
              cbcomm = Command.new(@command_ctr += 1, "\x01#{task.callback}", task.args, nil, nil)
              @commands[cbcomm.id] = cbcomm
              dispatch_command cbcomm
            end
          elsif @sender and r == @sender.outqueue
            begin
              @log.puts 'SENT:' + r.receive.inspect
            rescue EOFError => err
            end
          elsif r.is_a? Queue
            begin
              response = r.receive
            rescue EOFError => err
            end
            case response
            when CommandStatus
              command = @commands[response.command_id]
              if response.status == :started
                command.started!
              else response.status == :done
                command.done!
              end
            when Message
              privmsg response.channel, response.message
            when RawMessage
              send response.command, response.params, response.text
            when CoreEval
              result = (proc do
                command = @commands[response.command_id]
                begin
                  eval response.code
                rescue Exception => e
                  e
                end
              end).call
              inqueue = (@workers.select {|w| w.outqueue == r }.first or next).inqueue
              inqueue.send result
            when DatabaseAction
              inqueue = (@workers.select {|w| w.outqueue == r }.first or next).inqueue
              case response.action
              when :init
                name, value = response.args
                Database.new name, value
                inqueue.send true
              when :fetch_all
                name = response.args.first
                inqueue.send Database.new(name).value
              when :fetch_key
                name, key = response.args
                inqueue.send Database.new(name).value[key]
              when :replace
                name, value = response.args
                Database.new(name).value = value
                inqueue.send true
              when :set_key
                name, key, value = response.args
                Database.new(name)[key] = value
                inqueue.send true
              end
            when ScheduledTask
              @scheduler.inqueue.send [response.time, response]
            when Tell
              @telldb[response.to.downcase] = @telldb[response.to.downcase].to_a + [response]
            end
          end
        end
      else
        @commands.each do |id, command|
          if command.started? and not command.done? and (Time.now - command.started) >= @timeout
            deal_with_runaway command
          elsif command.done? # to prevent this process taking longer as the bot gets older
            @log.puts "GC: reaped #{id}"
            @commands.delete id
          end
        end
        @sent_times = @sent_times[0..3]
        @last_msgs = @last_msgs[0..10]
      end
    end
  end
  
  def parse_line line
    event = OpenStruct.new
    m = @@linere.match line.chomp
    event.user = m[1]
    type, *args = m[2].split ' '
    event.type = type; event.args = args # argh Ruby
    event.text = (m[3].is_a?(String) ? fix_encoding(m[3]) : m[3])
    event.nick = event.user.split('!').first rescue nil
    event
  end
  
  def handle_event event
    case event.type
    when 'PRIVMSG'
      channel = (event.args[0] == @nick ? event.nick : event.args[0])
      if event.text.downcase == "#{@nick.downcase}!"
        privmsg channel, "#{event.nick}!"
      elsif event.text.match(/^#{Regexp.quote @nick}[,:] ping[!?\u203D]*$/i)
        running = @commands.count {|id, command| command.started? and not command.done? }
        queued = @commands.count {|id, command| not command.started? }
        privmsg channel, "#{event.nick}: pong! (#{queued} queued, #{running} running)"
      elsif m=event.text.match(@@uri_regexp)
        @last_url[channel] = m[1]
      end
      
      @seendb[event.nick.downcase] = [DateTime.now, event.nick, channel, event.text]
      if @telldb[event.nick.downcase] and not @telldb[event.nick.downcase].empty?
        begin
          @telldb[event.nick.downcase].each do |tell|
            cbcomm = Command.new(@command_ctr+=1, "\x01#{tell.callback}", tell.args, event.nick, channel)
            @commands[cbcomm.id] = cbcomm
            dispatch_command cbcomm
          end
        ensure
          @telldb[event.nick.downcase] = []
        end
      end
    when 'PING'
      send 'PONG', [@nick], event.text
    when '251'
      @channels.each {|channel| join channel }
    end
  end
  
  def parse_command event
    if event.type == 'PRIVMSG' and event.text[0...(@prefix.length)] == @prefix
      command, args = event.text.split(' ', 2)
      command = command[(@prefix.length)..-1]
      channel = (event.args[0] == @nick ? event.nick : event.args[0])
      id = (@command_ctr += 1)
      @commands[id] = Command.new(id, command, args, event.nick, channel, {:last_url => @last_url[channel], :admin => @admins.include?(event.nick), :prefix => @prefix, :bot_nick => @nick})
      return @commands[id]
    end
  end
  
  def dispatch_command command, id=nil
    process = @workers[(id or command.id) % @workers.length]
    @log.puts "#{(command.handler_process ? "moving" : "dispatching")} #{command.id} to #{process.pid}"
    command.handler_process = nil # if we're re-dispatching this command, don't dump IOs
    process.inqueue.send command
    command.handler_process = process
  end
  
  def read_config
    @config = YAML.load_file "#{Yoleaux::BASE}/config.yaml"
    @server = (@config['server'] or raise 'no server option in config')
    @port = (@config['port'] or 6667)
    @nick = (@config['nick'] or raise 'no nick option in config')
    @user = (@config['user'] or @nick)
    @realname = (@config['realname'] or 'Yoleaux L. Only-Once')
    @nworkers = (@config['workers'] or 4)
    @prefix = (@config['prefix'] or '.')
    @channels = (@config['channels'] or [])
    @timeout = (@config['command_timeout'] or 30)
    @admins = (@config['admins'] or [])
  end
  def write_config
    @config['server'] = @server
    @config['port'] = @port
    @config['nick'] = @nick
    @config['user'] = @user
    @config['realname'] = @realname
    @config['workers'] = @nworkers
    @config['prefix'] = @prefix
    @config['channels'] = @channels
    @config['command_timeout'] = @timeout
    @config['admins'] = @admins
    File.write "#{Yoleaux::BASE}/config.yaml", @config.to_yaml
  end
  
  private
  
  def fix_encoding str
    # Ruby sucks
    str = str.dup
    str.force_encoding('utf-8')
    if str.valid_encoding?
      str
    else
      str.force_encoding('iso-8859-1').encode('utf-8')
    end
  end
  
  def privmsg channel, msg
    msg = msg.to_s
    # loop prevention. a mechanism like Delivered-To would be useful here, IRC!
    if @last_msgs.count([channel, msg]) > 4
      if @last_msgs.count([channel, '...']) > 2
        @log.puts "A loop-prevention loop happened in #{channel}! There is probably some funny business going on!"
        return
      else
        msg = '...'
      end
    end
    if m=msg.match(@@uri_regexp)
      @last_url[channel] = m[1]
    end
    @last_msgs.unshift [channel, msg]
    send 'PRIVMSG', [channel], msg
  end
  def send command, params=[], text=nil
    tosend = "#{command.upcase} #{params.join ' '}#{" :#{text}" if text}\r\n"
    if @sender
      @sender.inqueue.send tosend
    else
      @socket.write tosend
      @log.puts "SENT:#{tosend.inspect} (imm)"
    end
  end
  def recv
    line = @socket.gets
    @log.puts 'RECV:' + line.inspect
    line
  end
  
  def deal_with_runaway command
    @log.puts "**RUNAWAY COMMAND!** #{command.command} for #{command.user} on #{command.channel} in process #{command.handler_process.pid}"
    command.done!
    movecomms = []
    @commands.each do |id, oc|
      if not oc.done? and oc.handler_process == command.handler_process
        movecomms << oc
      end
    end
    @log.puts "#{movecomms.length} queued command(s) need moving to another worker."
    
    privmsg command.channel, "#{command.user}: Sorry, that command (#@prefix#{command.command}) took too long to process."
    command.handler_process.kill
    ::Process.wait2 command.handler_process.pid
    @workers.delete command.handler_process
    @log.puts "#{command.handler_process.pid} killed"
    start_worker
    moven = 0
    movecomms.each do |mc|
      dispatch_command mc, moven
      moven += 1
    end
  end
  
  def start_processes
    @log.puts "Starting processes ..."
    start_workers
    start_sender
    start_scheduler
  end
  def stop_processes
    @log.puts "Stopping processes ..."
    stop_workers
    stop_sender
    stop_scheduler
  end
  
  def start_workers
    @log.puts "Starting workers ..."
    @workers = []
    @nworkers.times do
      start_worker
    end
  end
  def stop_workers
    @log.puts "Stopping workers ..."
    @workers.each(&:stop)
  end
  
  def start_process kind, message, *args, &block
    inqueue = Queue.new
    outqueue = Queue.new
    pid = fork do
      inqueue.close_write
      outqueue.close_read
    
      process = kind.new $$, inqueue, outqueue
      block.call(process, inqueue, outqueue) if block_given?
      outqueue.send true
      process.method(message).call(*args)
    end
    inqueue.close_read
    outqueue.close_write
    
    outqueue.receive or return @log.puts "something went wrong with starting #$$ ..."
    @log.puts "Started #{kind}: #{pid}"
    return Worker.new(pid, inqueue, outqueue)
  end
  
  def start_worker
    @workers << (start_process Worker, :loop do |process|
      trap('INT') { }
      trap('TERM') { process.stop }
      require './commands'
    end)
  end
  def start_scheduler
    @scheduler = start_process Scheduler, :run
  end
  def stop_scheduler
    @log.puts "Stopping scheduler ..."
    Process.kill :TERM, @scheduler.pid
    pid, stat = Process.wait2 @scheduler.pid
    @log.puts "scheduler (#{pid}) stopped: #{stat.exitstatus}"
  end
  
  def start_sender
    @sender = start_process Sender, :run do |process|
      process.socket = @socket
    end
  end
  def stop_sender
    @log.puts "Stopping sender ..."
    Process.kill :TERM, @sender.pid
    pid, stat = Process.wait2 @sender.pid
    @log.puts "sender (#{pid}) stopped: #{stat.exitstatus}"
    @sender = nil
  end
end


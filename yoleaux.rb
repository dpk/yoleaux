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
    @log.sync = true if @log.respond_to? :sync=
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
    
    @next_dispatch = Hash.new { Array.new }
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
  
  def join channels
    send 'JOIN', [], channels.join(',')
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
                isworker = @workers.any? {|p| p.pid == pid }
                @workers.reject! {|p| p.pid == pid }
                if @stopasap
                  if @workers.empty?
                    send 'QUIT', [], "#@stopblame made me do it!"
                    @socket.close
                    @socket = nil
                    return
                  end
                elsif @reloading and isworker
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
                elsif stat.exitstatus.nil? or (not stat.exitstatus.zero?)
                  if isworker
                    @log.puts "restarting crashed worker #{pid} ..."
                    start_worker
                    @commands.each do |id, comm|
                      # there's some kind of race condition-y heisenbug here, which is why we check that there is a handler before comparing pids
                      if comm.handler_process and comm.handler_process.pid == pid
                        if comm.started? and not comm.done?
                          privmsg comm.channel, "#{comm.user}: Sorry, that command (#@prefix#{comm.name}) crashed." unless comm.is_a? Callback
                          comm.done!
                        elsif not comm.started?
                          dispatch_command comm
                        end
                      end
                    end
                  elsif @scheduler.pid == pid
                    @log.puts "restarting crashed schedular ..."
                    start_scheduler
                  elsif @sender.pid == pid
                    @log.puts "restarting crashed sendar ..."
                    start_sender
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
              callback = Callback.new (@command_ctr += 1), :name => task.callback,
                                                           :args => task.args
              @commands[callback.id] = callback
              dispatch callback
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
                if not @next_dispatch[response.command_id].empty?
                  nxt = @next_dispatch[response.command_id].shift
                  @next_dispatch[nxt.id] = @next_dispatch[response.command_id]
                  @next_dispatch[response.command_id] = []
                  dispatch nxt
                end
              end
            when Message
              command = @commands.values.select do |cmd|
                cmd.started? and not cmd.done? and cmd.handler_process.outqueue == r
              end.first
              resp_prefix = (command.respond_to?(:response_prefix) ? command.response_prefix : nil)
              privmsg response.channel, command.response_prefix, response.message
            when RawMessage
              send response.command, response.params, response.text
            when CoreEval
              result = (proc do
                command = @commands[response.command_id]
                begin
                  assignments = response.vars.map {|k, v| "#{k} = response.vars[:#{k}];\n" }.join
                  eval "#{assignments}#{response.code}"
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
              @telldb[Yoleaux.nick(response.to)] = @telldb[Yoleaux.nick(response.to)].to_a + [response]
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
        # prevent the queue from memory-leaking
        @next_dispatch.each {|id, queue| @next_dispatch.delete(id) if queue.empty? }
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
      if Yoleaux.nick(event.text) == "#{Yoleaux.nick(@nick)}!"
        privmsg channel, "#{event.nick}!"
      elsif Yoleaux.nick(event.text).match(/^#{Regexp.quote Yoleaux.nick @nick}[,:] ping[!?\u203D]*$/)
        running = @commands.count {|id, command| command.started? and not command.done? }
        queued = @commands.count {|id, command| not command.started? }
        privmsg channel, "#{event.nick}: pong! (#{queued} queued, #{running} running)"
      elsif Yoleaux.nick(event.text).match(/^#{Regexp.quote Yoleaux.nick @nick}[,:] prefix\??$/)
        privmsg channel, "#{event.nick}: My current prefix is \"#@prefix\"."
      elsif m=event.text.match(@@uri_regexp)
        @last_url[channel] = m[1]
      end
      
      if not private_msg? channel, event.nick, event.text
        @seendb[Yoleaux.nick(event.nick)] = [DateTime.now, event.nick, channel, event.text]
      elsif time_loggable? channel
        @seendb[Yoleaux.nick(event.nick)] = [DateTime.now, event.nick, channel]
      end
      if @telldb[Yoleaux.nick(event.nick)] and not @telldb[Yoleaux.nick(event.nick)].empty?
        begin
          # a hack to get tells to be delivered in order
          tellcbs = @telldb[Yoleaux.nick(event.nick)].map do |tell|
            dispatchable Callback, :name => tell.callback,
                                   :args => tell.args,
                                   :user => event.nick,
                                   :channel => channel
          end
          @next_dispatch[tellcbs.first.id] = tellcbs[1..-1]
          dispatch tellcbs.first
        ensure
          @telldb[Yoleaux.nick(event.nick)] = []
        end
      end
    when 'PING'
      send 'PONG', [@nick], event.text
    when '251'
      @channels.each_slice(3) {|channels| join channels }
      if @nickpass
        privmsg 'NickServ', "IDENTIFY #@nickpass"
      end
    end
  end
  
  def parse_command event
    if event.type == 'PRIVMSG'
      channel = (event.args[0] == @nick ? event.nick : event.args[0])
      message = event.text
      response_prefix = nil
      if @privacy[channel] and @privacy[channel]['noseen_prefix'] and
         message[0...(@privacy[channel]['noseen_prefix'].length)] == @privacy[channel]['noseen_prefix']
        response_prefix = @privacy[channel]['noseen_prefix']
        message = message[@privacy[channel]['noseen_prefix'].length..-1].lstrip
      end
      
      if message[0...(@prefix.length)] == @prefix and
         message[@prefix.length].to_s.match(/\A[a-z0-9]\Z/i)
        command, args = message.split(' ', 2)
        command = command[(@prefix.length)..-1]
        dispatchable Command, :name => command,
                              :args => args,
                              :user => event.nick,
                              :channel => channel,
                              :last_url => @last_url[channel],
                              :admin => @admins.include?(event.nick),
                              :prefix => @prefix,
                              :bot_nick => @nick,
                              :response_prefix => response_prefix
      end
    end
  end
  
  def dispatch_command command, id=nil
    process = @workers[(id or command.id) % @workers.length]
    @log.puts "#{(command.handler_process ? "moving" : "dispatching")} #{command.id} to #{process.pid}"
    command.handler_process = nil # if we're re-dispatching this command, don't dump IOs
    process.inqueue.send command
    command.handler_process = process
  end
  alias dispatch dispatch_command
  
  def dispatchable klass, other
    id = (@command_ctr += 1)
    obj = klass.new id, other
    @commands[id] = obj
  end
  
  def read_config
    @config = YAML.load_file "#{Yoleaux::BASE}/config.yaml"
    @server = (@config['server'] or raise 'no server option in config')
    @port = (@config['port'] or 6667)
    @nick = (@config['nick'] or raise 'no nick option in config')
    @nickpass = (@config['nick_password'] or nil)
    @user = (@config['user'] or @nick)
    @realname = (@config['realname'] or 'Yoleaux L. Only-Once')
    @nworkers = (@config['workers'] or 4)
    @prefix = (@config['prefix'] or '.')
    @channels = (@config['channels'] or [])
    @timeout = (@config['command_timeout'] or 30)
    @admins = (@config['admins'] or [])
    @privacy = (@config['privacy'] or {})
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
    @config['privacy'] = @privacy
    File.write "#{Yoleaux::BASE}/config.yaml", @config.to_yaml
  end
  
  def private_msg? channel, nick, msg
    if channel == nick
      true
    elsif @privacy.has_key? channel
      privopt = @privacy[channel]
      if privopt['private'] or
        (privopt['noseen_prefix'] and
           msg[0...(privopt['noseen_prefix'].length)] == privopt['noseen_prefix'])
        true
      else
        false
       end
    else
      false
    end
  end
  def time_loggable? channel
    not not (@privacy.has_key? channel and @privacy[channel]['noseen_log_time'])
  end
  
  # normalises a nick according to IRC's casefolding rules
  def self.nick nick
    nick.downcase.tr('{}^\\', '[]~|')
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
  
  def privmsg channel, prefix=nil, msg
    msg = fix_encoding msg
    msg = "#{"#{prefix} " if prefix}#{msg.to_s}"
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
    
    # break lines
    msgs = [msg]
    # todo: configurable max line length
    while msgs.last.bytesize > 460
      lastline = msgs.last
      pieces = lastline.split(/\b/)
      newline = ''
      
      lasti = 0
      pieces.each_with_index do |piece, i|
        lasti = i
        if (newline.bytesize + piece.bytesize) >= 455
          break
        end
        newline << piece
      end
      if lasti == 0
        newline = lastline.force_encoding('binary')[0...455].force_encoding('utf-8') + " \u2026"
        lastline = lastline.force_encoding('utf-8')[455..-1]
        msgs[-1] = newline
        msgs << lastline
      elsif lasti < pieces.length - 1
        lastline = lastline[newline.length..-1]
        newline << " \u2026"
        msgs[-1] = newline
        msgs << lastline
      else
        # hum
      end
    end
    msgs.each do |msg|
      send 'PRIVMSG', [channel], msg
    end
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
    @log.puts "**RUNAWAY COMMAND!** #{command.name} for #{command.user} on #{command.channel} in process #{command.handler_process.pid}"
    command.done!
    movecomms = []
    @commands.each do |id, oc|
      if not oc.done? and oc.handler_process == command.handler_process
        movecomms << oc
      end
    end
    @log.puts "#{movecomms.length} queued command(s) need moving to another worker."
    
    privmsg command.channel, "#{command.user}: Sorry, that command (#@prefix#{command.name}) took too long to process." unless command.is_a? Callback
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


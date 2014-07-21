module Yoleaux
  class Bot
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
      @address = "#@nick!#@user@yoleaux/default"
      @socket = TCPSocket.new @server, @port
      start_processes
      send 'NICK', [], @nick
      send 'USER', [@user, '0', '*'], @realname
      
      @last_url = {}
      
      trap('INT')  { stop }
      trap('TERM') { stop }
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
      loop do
        rsocks = []
        rsocks << @socket
        rsocks << @spr
        (rsocks << @sender.outqueue) if @sender
        rsocks.flatten!
        selected = Queue.select(rsocks, [], [], 2)
        if selected
          rs, ws, es = selected
          rs.each do |r|
            if r == @socket
              line = recv
              event = parse_line line
              handle_event event
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
              when Message
                command = @commands.values.select do |cmd|
                  cmd.started? and not cmd.done? and cmd.handler_process.outqueue == r
                end.first
                resp_prefix = (command.respond_to?(:response_prefix) ? command.response_prefix : nil)
                privmsg response.channel, command.response_prefix, response.message
              when RawMessage
                send response.command, response.params, response.text
              end
            end
          end
        else
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
        elsif m=event.text.scan(@@uri_regexp).last
          @last_url[channel] = m.first
        end
      when 'PING'
        send 'PONG', [@nick], event.text
      when 'JOIN'
        if Yoleaux.nick(event.nick) == Yoleaux.nick(@nick)
          @address = event.user
        end
      when '251'
        @channels.each_slice(3) {|channels| join channels }
        if @nickpass
          privmsg 'NickServ', "IDENTIFY #@nickpass"
        end
      end
    end
    
    def read_config
      @config = YAML.load_file "#{BASE}/config.yaml"
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
      File.write "#{BASE}/config.yaml", @config.to_yaml
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
      # loop prevention. a mechanism like Delivered-To would be useful here, IRC!
      if @last_msgs.count([channel, msg]) > 4
        if @last_msgs.count([channel, '...']) > 2
          @log.puts "A loop-prevention loop happened in #{channel}! There is probably some funny business going on!"
          return
        else
          msg = '...'
        end
      end
      if m=msg.scan(@@uri_regexp).last
        @last_url[channel] = m.first
      end
      @last_msgs.unshift [channel, msg]
    
      # break lines
      msgs = [msg]
      maxlen = 498 - @address.length - channel.length - (prefix ? (prefix.bytesize + 1) : 0)
      # todo: configurable max line length
      while msgs.last.bytesize > maxlen
        lastline = msgs.last
        pieces = lastline.split(/\b/)
        newline = ''
      
        lasti = 0
        pieces.each_with_index do |piece, i|
          lasti = i
          if (newline.bytesize + piece.bytesize) >= (maxlen - 5)
            break
          end
          newline << piece
        end
        if lasti == 0
          len = 0
          newline = lastline.each_char.take_while {|c| (len += c.bytesize) <= (maxlen - 20) }.join + " \u2026"
          lastline = lastline[(newline.length-2)..-1]
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
        send 'PRIVMSG', [channel], "#{"#{prefix} " if prefix}#{msg}"
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
      start_sender
    end
    def stop_processes
      @log.puts "Stopping processes ..."
      stop_sender
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
end

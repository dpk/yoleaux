
require 'digest/sha2'
require 'time'

command_set :general do
  helpers do
    def parse_time_interval time
      abbrs = {'y' => 31536000,
               'mo' => 2419200,
               'w' => 604800,
               'd' => 86400,
               'h' => 3600,
               'm' => 60,
               's' => 1}
      units = abbrs.keys
      unitsre = "(?i:#{units.join '|'})"
      secs = 0.0
      time.scan(/(\d+(?:\.\d+)?)(#{unitsre})/).each do |match|
        scalar, unit = match
        scalar = scalar.to_f
        secs += (scalar * (abbrs[unit.downcase] || 0))
      end
      secs
    end
    
    def set_reminder &parser
	  require_argstr
	  time, message = argstr.split(' ', 2)
	  time = parser.call time
	  schedule time, :remind, env.channel, env.nick, message
	  alerttime = (time.is_a?(Numeric) ? (Time.now + time) : time)
	  respond "#{env.nick}: I'll remind you #{(alerttime.to_date != Time.now.to_date) ? 'on' : 'at'} #{format_time alerttime}"
    end
    
    def format_time time
      [((time.to_date != Time.now.to_date) ? time.strftime('%e %b %Y') : nil), time.strftime('%H:%M %Z')].compact.join(' ').sub(' +00:00', 'Z').strip
    end
  end
  
  command :ping, 'There is no ping command' do
    respond "#{docs}; nor can this be construed as a response."
  end
  
  command :to, 'Relay a telegram to someone' do
    require_argstr
    to, message = argstr.split(' ', 2)
    halt(respond "#{env.nick}: I don't know what you want me to say to #{to}.") unless message
    
    if nick(env.nick) == nick(to)
      halt respond "#{env.nick}: Talking to yourself is the first sign of madness."
    elsif nick(env.bot_nick) == nick(to)
      halt respond "#{env.nick}: Thanks for the message."
    end
    
    on_next_message to, :relay_message, env.channel, DateTime.now, env.nick, message
    respond "#{env.nick}: I'll pass your message to #{to}."
  end
  alias_command :tell, :to
  alias_command :ask,  :to
  callback :relay_message do |channel, msgtime, from, message|
    send env.channel, "#{format_time msgtime} <#{from}> #{env.nick}: #{message}"
  end
  
  command(:botsnack, 'Give me a snack pls') { respond ':D' }
  
  command :msg, 'Send a message to a channel' do
    admin_only
    require_argstr
    channel, message = argstr.split ' ', 2
    send channel, message
  end
  
  command :t, 'Get the current time' do
    respond DateTime.now.rfc2822
  end
  
  command :supercombiner, 'TEH SUPARCOMBINOR' do
    admin_only # to prevent spam
    respond ("u\xCC\x80\xCC\x81\xCC\x82\xCC\x83\xCC\x84\xCC\x85"+
              "\xCC\x86\xCC\x87\xCC\x88\xCC\x89\xCC\x8A\xCC\x8B"+
              "\xCC\x8C\xCC\x8D\xCC\x8E\xCC\x8F\xCC\x90\xCC\x91"+
              "\xCC\x92\xCC\x93\xCC\x94\xCC\x95\xCC\x96\xCC\x97"+
              "\xCC\x98\xCC\x99\xCC\x9A\xCC\x9B\xCC\x9C\xCC\x9D"+
              "\xCC\x9E\xCC\x9F\xCC\xA0\xCC\xA1\xCC\xA2\xCC\xA3"+
              "\xCC\xA4\xCC\xA5\xCC\xA6\xCC\xA7\xCC\xA8\xCC\xA9"+
              "\xCC\xAA\xCC\xAB\xCC\xAC\xCC\xAD\xCC\xAE\xCC\xAF"+
              "\xCC\xB0\xCC\xB1\xCC\xB2\xCC\xB3\xCC\xB4\xCC\xB5"+
              "\xCC\xB6\xCC\xB7\xCC\xB8\xCC\xB9\xCC\xBA\xCC\xBB"+
              "\xCC\xBC\xCC\xBD\xCC\xBE\xCC\xBF\xCD\x80\xCD\x81"+
              "\xCD\x82\xCD\x83\xCD\x84\xCD\x85\xCD\x86\xCD\x87"+
              "\xCD\x88\xCD\x89\xCD\x8A\xCD\x8B\xCD\x8C\xCD\x8D"+
              "\xCD\x8E\xCD\x8F\xCD\x90\xCD\x91\xCD\x92\xCD\x93"+
              "\xCD\x94\xCD\x95\xCD\x96\xCD\x97\xCD\x98\xCD\x99"+
              "\xCD\x9A\xCD\x9B\xCD\x9C\xCD\x9D\xCD\x9E\xCD\x9F"+
              "\xCD\xA0\xCD\xA1\xCD\xA2\xCD\xA3").force_encoding('utf-8')
  end
  
  command :bytes, 'Show bytes of the input string' do
    type = (switches.first or 'hex')
    fmtmap = {'hex' => '%02x', 'oct' => '%04o', 'dec' => '%d'}
    respond argtext.bytes.map {|b| sprintf (fmtmap[type] or "%02x"), b }.join ' '
  end
  
  command :seen, 'Ask me when I last saw a user speaking' do
    require_argstr
    seen = db(:seen)[nick(argstr)]
    if nick(argstr) == nick(env.nick)
      respond "You're right there."
    elsif nick(argstr) == nick(env.bot_nick)
      respond "I'm right here."
    elsif seen.nil?
      respond "I haven't seen #{argstr} around."
    else
      time, nick, channel, message = seen
      if message
		if m=message.match(/\A\x01ACTION (.*)\x01\Z/)
		  message = ": * #{nick} #{m[1]}"
		else
		  message = ": <#{nick}> #{message}"
		end
	  else
	    message = '.'
	  end
      respond "I saw #{nick} #{format_time time} in #{channel}#{message}"
    end
  end
  
  command :pick, 'Makes a decision from multiple options for you. (The author of this bot cannot be held liable for the consequences of using this command)' do
    require_argstr
    choices = argstr.split(argstr.include?(';') ? ';' : ',').map {|opt| opt.strip }.uniq.sort
    halt respond "#{env.nick}: You must provide at least two options." unless choices.length > 1
    hash = Digest::SHA256.hexdigest(choices.map(&:downcase).join("\x00")).to_i(16)
    respond choices[hash % choices.length]
  end
  alias_command :choose, :pick
  
  command :at, 'Set a reminder for yourself at a certain date and/or time' do
    set_reminder do |tstr|
      begin
        raise ArgumentError unless tstr.include?(':') or tstr.include?('-')
        time = DateTime.iso8601(tstr.dup) # fuck Ruby
      rescue ArgumentError
        halt respond "#{env.nick}: Sorry, I don't understand that date/time."
      end
      if not tstr.include? ':'
        time += (DateTime.now - Date.today)
      elsif not tstr.include? '-' and time < DateTime.now
        time += 1
      end
      if time < DateTime.now
        halt respond "#{env.nick}: Sorry, I can't deliver reminders to the past."
      end
      time
    end
  end
  alias_command :on, :at
  command :in, 'Set a reminder for yourself in a certain amount of time' do
    set_reminder do |tstr|
      time = parse_time_interval tstr
	  if time.zero?
		halt respond "#{env.nick}: Sorry, I don't understand your duration. Try using units: 1h30m, 1d, etc."
	  end
	  time
    end
  end
  callback :remind do |channel, nick, message|
    send channel, (if message
      "#{nick}: #{message}"
    else
      "#{nick}!"
    end)
  end
  
  command :buck, 'Is it BUCK yet?' do
    today = Date.today
    start = Date.new(2013,8,23)
    stops = Date.new(2013,8,25)
    if today < start
      respond "Not yet! Only #{(Date.new(2013,8,23) - Date.today).to_i} days to go!"
    elsif (today > start) and (today < stops)
      respond "It's here! Check't out! http://buckcon.org/"
    else
      respond "It's gone for 2013! What about 2014 ...?"
    end
  end
  
  # command(:o, ':O') { respond ':O' }
end


require 'socket'
require 'date'
require 'tzinfo'

module Yoleaux
  module Helpers
    module Temporal
      def self.format_time time, tz=nil
        if tz == nil
          tz = TZInfo::Timezone.get('UTC')
        end
        
        (if tz.now.to_date == tz.utc_to_local(time).to_date
          tz.strftime("%H:%M %Z", time)
        else
          tz.strftime("%e %b %Y %H:%M %Z", time).strip
        end).sub(/ (?:UTC|GMT)$/, 'Z')
      end
      
      def self.npl_time
        servers = %w{ntp1.npl.co.uk ntp2.npl.co.uk}
        server = servers.sample
        client = UDPSocket.new
        client.send("\x1B"+("\0"*47), 0, server, 123)
        data, address = client.recvfrom(1024)
        
        if data
          buf = data.unpack('C*')
          d = 0
          (0..8).each {|i| d += (buf[32+i] * (2 ** ((3 - i) * 8))) }
          d -= 2208988800
          OpenStruct.new :time => Time.at(d).to_datetime, :server => server
        else
          return nil
        end
      end
    end
  end
end

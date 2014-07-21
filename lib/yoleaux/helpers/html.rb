require 'httparty'
require 'nokogiri'

module Yoleaux
  module Helpers
  	module HTML
  	  def self.page_title url
  	    resp = HTTParty.get url
  	    if not resp.headers['Content-Type'].downcase.include? 'text/html'
  	      return nil
  	    end
  	    return (Nokogiri::HTML(resp.body).title or return '').gsub(/[[:space:]]+/, ' ').strip
  	  end
  	  
  	  def self.entities text
        # not thread-safe
        lookup = Nokogiri::HTML::EntityLookup.new
        text.gsub(/&(#(?:x[0-9a-f]+|[0-9]+)|[a-z0-9]+);/i) do
          '' << (if $1[0] == '#'
            if $1[1] == 'x'
              $1[2..-1].to_i(16)
            else
              $1[1..-1].to_i(10)
            end
          else
            lookup[$1] or $&
          end)
        end
  	  end
  	  
      def self.validate url
        out = OpenStruct.new
        out.source = "http://html5.validator.nu/?doc=#{URI.encode url, /[^a-z0-9\/.\-_]|/i}"
        src = Net::HTTP.get(URI out.source)
        h = Nokogiri::HTML(src)
        if e=(h % 'p.failure')
          # No, I wasn't prepared for this ...
          out.valid = false
        elsif e=(h % 'p.success')
          # Turns out you were prepared for this!
          out.valid = true
        else
          out.valid = nil
        end
        if e
          out.message = e.inner_text.strip
        end
        return out
      end
  	end
  end
end

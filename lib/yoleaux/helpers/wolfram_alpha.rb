require 'httparty'
require 'nokogiri'

module Yoleaux
  module Helpers
    module WolframAlpha
      def self.wolfram_alpha query
        htmlsrc = Net::HTTP.get(URI "http://www.wolframalpha.com/input/?asynchronous=false&i=#{URI.encode(query, /./)}")
        subpodns = Hash.new(0)
        pods = htmlsrc.lines.grep(/"stringified":/).map do |psrc|
          pod_id = psrc.match(/jsonArray\.popups\.([^.]+)\./)[1]
          subpodn = subpodns[pod_id]
          subpodns[pod_id] += 1
          [pod_id, (WolframAlpha.cleanup JSON.parse(psrc[psrc.index('{"stringified":')..-4])['stringified']), subpodn]
        end
        h = Nokogiri::HTML(htmlsrc)
        pods.map do |pod|
          id, data, subpodn = pod
          podh = (h % "##{id}") # ugh, nokogiri. why no get_element_by_id?
          podtitles = podh.search('h2').inner_text.lines.map(&:strip).reject(&:empty?)
          title = podtitles[subpodn % podtitles.length].strip[0..-2]
          if data.empty?
            data = ShortURL.shorten podh.search('img')[subpodn]['src']
          end
          [title, data]
        end
      end
      
      def self.cleanup str
        WolframAlpha.subsup HTML.entities(str).gsub(" \u00B0", "\u00B0").gsub(/[[:space:]]{2,}/, ' ').gsub(/~~\s+/, '~').gsub(/\(\s+/,'(').gsub(/\s+\)/,')').gsub(' | ', ': ').gsub("\n", '; ')
      end
      
      def self.subsup str
        sup_base = 0x2070
        sub_base = 0x2080
        # grr, Unicode
        sup_special = {'1' => "\u00B9", '2'=>"\u00B2", '3' => "\u00B3"}
        str.gsub(/([\^_])(-?\d+|\(-?\d+\))/) do |m|
          base = (m[0] == '^' ? sup_base : sub_base)
          str = ''.force_encoding('utf-8')
          m[1..-1].each_char do |digit|
            if digit == '-'
              str << (base + 11)
            elsif digit == '('
              str << (base + 13)
            elsif digit == ')'
              str << (base + 14)
            elsif base == sup_base and sup_special.has_key? digit
              str << sup_special[digit]
            else
              str << (base + digit.to_i)
            end
          end
          str
        end
      end
    end
  end
end

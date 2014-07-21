require 'uri'
require 'httparty'
require 'nokogiri'
require 'execjs'

module Yoleaux
  module Helpers
    module Google
      def self.search query
        resp = HTTParty.get "https://www.google.com/search?&q=#{URI.encode(query)}&btnI=",
                            follow_redirects: false,
                            headers: {'User-Agent' => 'Mozilla/5.0', 'Referer' => 'https://www.google.com/'}
        resp.headers['Location']
      end
      
      def self.count query, kinds=[:site, :api]
        counts = {}
        if kinds.include? :site
          resp = HTTParty.get "https://www.google.com/search?&q=#{URI.encode(query)}&nfpr=1&filter=0",
                 headers: {'User-Agent' => 'Mozilla/5.0'}
          h = Nokogiri::HTML resp.body
          if (h % 'div.e') and (h % 'div.e').inner_text.include? 'No results found'
            counts[:site] = 0
          else
            counts[:site] = (h % '#resultStats').inner_text.gsub(/[^0-9]/,'').to_i
          end
        end
        if kinds.include? :api
          resp = HTTParty.get "http://ajax.googleapis.com/ajax/services/search/web?v=1.0&q=#{URI.encode(query)}"
          response = JSON.parse resp.body
          if response['responseData'] and response['responseData']['cursor'] and
             response['responseData']['cursor'] and
             response['responseData']['cursor']['estimatedResultCount']
            counts[:api] = response['responseData']['cursor']['estimatedResultCount'].to_i
          end
        end
        counts
      end
      
      def self.translate from='auto', to='en', text
        from = from.downcase; to = to.downcase
        resp = HTTParty.get "https://translate.google.com/translate_a/t",
                            query: {
                              'client' => 't',
                              'hl' => 'en',
                              'sl' => from,
                              'tl' => to,
                              'multires' => '1',
                              'otf' => '1',
                              'ssel' => '0',
                              'tsel' => '0',
                              'sc' => '1',
                              'text' => text
                            },
                            headers: {'User-Agent' => 'Mozilla/5.0', 'Referer' => 'https://translate.google.com/'},
                            parser: Class.new(HTTParty::Parser) { def parse; ExecJS.eval body; end }
        
        
        from = resp[2]
        translation = resp[0].map {|trpart| trpart[0] }.join
        return OpenStruct.new translation: translation, from: from, to: to
      end
    end
  end
end

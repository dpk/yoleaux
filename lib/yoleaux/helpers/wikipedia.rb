require 'httparty'
require 'nokogiri'

module Yoleaux
  module Helpers
    module Wikipedia
      def self.search lang='en', search
        maxlen = 350
      
        resp = HTTParty.head "https://#{lang}.wikipedia.org/w/index.php?search=#{URI.encode search}&title=Special%3ASearch", follow_redirects: false
        article_url = (resp.headers['Location'] or Google.search("site:#{lang}.wikipedia.org/wiki #{search}"))
        return nil if article_url.nil?
        
        article_slug = article_url.match(%r{\.wikipedia\.org/wiki/(.*)}i)[1]
        if Wikipedia.disambiguation? article_slug
          return OpenStruct.new :url => article_url, :gist => "Disambiguation: #{categories['query']['pages'].first[1]['title']}"
        else
          j = HTTParty.get("https://#{lang}.wikipedia.org/w/api.php?action=mobileview&page=#{article_slug}&format=json&sections=0")
          
          html_src = j['mobileview']['sections'][0]['text']
          h = Nokogiri::HTML(html_src)
          
          firstp = h.css('body > p').reject {|p| p % '#coordinates' }.first
          if firstp
            firstp = firstp.inner_text.gsub(/\[(?:(?:nb )?\d+|citation needed|unreliable source\?)\]/, '')
            gist = (Format.sentence_truncate(firstp, maxlen) or j['mobileview']['normalizedtitle'])
          else
            gist = j['mobileview']['normalizedtitle']
          end
        
          return OpenStruct.new :url => article_url, :gist => gist
        end
      end
      
      def self.disambiguation? article_slug
        categories = HTTParty.get("https://en.wikipedia.org/w/api.php?action=query&prop=categories&titles=#{article_slug}&format=json")
        return categories['query']['pages'].first[1]['categories'].to_a.map{|x| x['title'] }.include? 'Category:Disambiguation pages'
      end
    end
  end
end

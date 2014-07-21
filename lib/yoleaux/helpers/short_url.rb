require 'net/http'

module Yoleaux
  module Helpers
    module ShortURL
      def self.shorten url
        Net::HTTP.get(URI "http://is.gd/create.php?format=simple&url=#{URI.encode(url, /./)}")
      end
    end
  end
end

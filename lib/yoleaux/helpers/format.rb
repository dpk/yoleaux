module Yoleaux
  module Helpers
    module Format
      def self.number_with_commas number
        number.to_s.reverse.split(/(...)/).reject(&:empty?).join(',').reverse
      end
      
      def self.superscript str
        base = 0x2070
        special = {
          '1' => "\u00B9",
          '2'=>"\u00B2",
          '3' => "\u00B3",
          '(' => "\u207D",
          ')' => "\u207E",
          '-' => "\u207B",
          '+' => "\u207A"
        }
        
        supstr = ''
        str.each_char do |c|
          supstr << (
            if special.has_key?(c)
              special[c]
            elsif c.to_i <= 9
              (base + c.to_i)
            else
              c
            end
          )
        end
        supstr
      end
      
      def self.sentence_truncate text, maxlen=250
        begin
          gist = ''
          abbrs = ["cf", "lit", "etc", "Ger", "Du", "Skt", "Rus", "Eng", "Amer.Eng",
                   "Sp", "Fr", "N", "E", "S", "W", "L", "Gen", "J.C", "dial", "Gk",
                   "19c", "18c", "17c", "16c", "St", "Capt", "obs", "Jan", "Feb",
                   "Mar", "Apr", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec", "c", "tr",
                   "e", "g"]
          re = /(?<=(?<!#{abbrs.map {|a| "\\b#{Regexp.quote a}" }.join '|'})\. )/
          sentences = text.split(re)
          if sentences.first.length > maxlen
            gist = sentences.first.match(/^(.{,#{maxlen-10}}\W)/)[1] + " \u2026"
          else
            sentences.each do |sentence|
              break if gist.length + sentence.length >= maxlen
              gist << sentence
            end
          end
          gist.strip
        rescue
          nil
        end
      end
    end
  end
end

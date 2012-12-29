# encoding: utf-8

require 'net/https'
require 'json'
require 'nokogiri' # RIP Hpricot

command_set :api do
  helpers do
    def google query
      uri = URI "http://www.google.com/search?&q=#{URI.encode(query)}&btnI="
      http = Net::HTTP.new(uri.host)
      response = http.request_get(uri.path+'?'+uri.query, {'User-Agent' => 'Mozilla/5.0', 'Referer' => 'http://www.google.com/'})
      response['Location']
    end
    
    def google_count query, kinds=[:site, :api]
      counts = {}
      if kinds.include? :site
        uri = URI "http://www.google.com/search?&q=#{URI.encode(query)}"
        http = Net::HTTP.new(uri.host)
        response = http.request_get(uri.path+'?'+uri.query, {'User-Agent' => 'Mozilla/5.0'})
        h = Nokogiri::HTML(response.body)
        counts[:site] = (h % '#resultStats').inner_text.gsub(/[^0-9]/,'').to_i
      end
      if kinds.include? :api
        uri = URI "http://ajax.googleapis.com/ajax/services/search/web?v=1.0&q=#{URI.encode(query)}"
        response = JSON.parse Net::HTTP.get uri
        if response['responseData'] and response['responseData']['cursor'] and
           response['responseData']['cursor'] and
           response['responseData']['cursor']['estimatedResultCount']
          counts[:api] = response['responseData']['cursor']['estimatedResultCount'].to_i
        end
      end
      counts
    end
    def number_digit_delimit number
      number.to_s.reverse.split(/(...)/).reject(&:empty?).join(',').reverse
    end
    
    # Nokogiri replacement for Hpricot.uxs
    def entities text
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
    
    def google_calculator query
      result = YAML.load Net::HTTP.get URI "http://www.google.com/ig/calculator?q=#{URI.encode query, /./}"
      result['lhs'] = entities result['lhs'].force_encoding('iso-8859-1')
      result['rhs'] = entities result['rhs'].force_encoding('iso-8859-1')
      result['rhs'] = result['rhs'].gsub(%r{<sup>(.*)</sup>}) do
        superscript $1
      end
      result
    end
    def superscript str
      base = 0x2070
      special = {'1' => "\u00B9", '2'=>"\u00B2", '3' => "\u00B3", '(' => "\u207D", ')' => "\u207E", '-' => "\u207B", '+' => "\u207A"}
      supstr = ''
      str.each_char {|c| supstr << (special.has_key?(c) ? special[c] : (base + c.to_i)) }
      supstr
    end
    
    def tweet_with_id id
      uri = URI "http://api.twitter.com/1/statuses/show/#{id}.json?include_entities=t"
      src = Net::HTTP.get(uri)
      tweet = JSON.parse src
    end
    def tweet_from_user name
      uri = URI "http://api.twitter.com/1/statuses/user_timeline.json?screen_name=#{URI.encode name}&count=1&include_entities=t"
      src = Net::HTTP.get(uri)
      tweet = JSON.parse(src).first
    end
    
    def expand_twitter_links text, entities
      text = text.dup
      entities['urls'].each do |url|
        text[url['indices'][0]..url['indices'][1]] = url['expanded_url']
      end
      text.gsub!('pic.twitter.com/', 'http://pic.twitter.com/')
      text
    end
    
    def does_follow who, whom
      h = Nokogiri::HTML Net::HTTP.get URI "http://doesfollow.com/#{URI.encode who}/#{URI.encode whom}"
      if h % '.yup'
        true
      elsif h % '.nope'
        false
      end
    end
    
    def page_title url
      resp = http_get_follow(url)
      return nil unless resp['Content-Type'].downcase.include? 'text/html'
      (Nokogiri::HTML(resp.body).title or return nil).gsub(/[[:space:]]+/, ' ').strip
    end
    
    def http_get url
      uri = URI url
      http = Net::HTTP.new uri.host, uri.port
      sslify uri, http
      http.request_get "#{uri.path.empty? ? '/' : uri.path}#{'?'+uri.query if uri.query}"
    end
    def http_get_follow url
      resp = http_get url
      followedcount = 0
      while resp['Location'] and followedcount <= 10
        resp = http_get resp['Location']
        followedcount += 1
      end
      resp
    end
    def sslify uri, http
      if uri.scheme.downcase == 'https'
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
    end
    
    # considered an API function because it relies on UnicodeData
    def unigrep str
      File.open('./data/UnicodeData.txt', 'r') do |f|
        matches = []
        f.each_line do |line|
          char = line.chomp.split(';')
          codepoint, name, category, ccc, direction, decomp, dec, digit, num, mirror, oldname, comment, upcase, downcase, tcase = char
          
          # THIS IS NOT THREAD-SAFE
          # (but then again, nothing is ...)
          match = (case str
          when /\A(?:U\+)?([0-9a-f]{4,})\Z/i
            codepoint.to_i(16) == $~[1].to_i(16)
          when /\A(?:U\+)?([0-9a-f]{4,})\s?-\s?(?:U\+)?([0-9a-f]{4,})\Z/i
            mincp = $~[1].to_i(16)
            maxcp = $~[2].to_i(16)
            (mincp..maxcp).include? codepoint.to_i(16)
          when /\A[a-z0-9 \-]+\Z/i
            name[0] != '<' and name.match(/\b#{Regexp.quote str.downcase}\b/i)
          else
            str.include? ('' << codepoint.to_i(16))
          end)
          
          if match
            matches << char
          end
        end
        
        matches
      end
    end
    def unicode_display char
      disp = ''
      codepoint, name, category, ccc, direction, decomp, dec, digit, num, mirror, oldname, comment, upcase, downcase, tcase = char
      cpnum = codepoint.to_i(16)
      
      if category[0] == 'M'
        disp << "\u25CC"
        disp << cpnum
      elsif category[0] == 'C' and not category[1] == 'o'
        if (0..31).include? cpnum
          disp << (cpnum + 0x2400)
        else
          disp << '<control>'
        end
      else
        disp << cpnum
      end
      disp
    end
    
    def translate from='auto', to='en', text
      uri = URI "http://translate.google.com/translate_a/t"
      http = Net::HTTP.new(uri.host)
      params = {
        "client" => "t",
        "hl" => "en",
        "sl" => from.downcase,
        "tl" => to.downcase,
        "multires" => "1",
        "otf" => "1",
        "ssel" => "0",
        "tsel" => "0",
        "uptl" => "en",
        "sc" => "1",
        "text" => text
      }
      uri.query = URI.encode_www_form(params)
      response = http.request_get(uri.path+'?'+uri.query, {'User-Agent' => 'Mozilla/5.0'})
      src = response.body
      src.gsub!(',,', ',null,') while src.include? ',,'
      jsonsrc = JSON.parse(src)
      if jsonsrc.length > 2
        from = jsonsrc[2]
      else
        from = '?'
      end
      translation = jsonsrc[0].map(&:first).join.gsub(' ,', ',')
      return OpenStruct.new :from => from, :to => to, :translation => translation
    end
    
    def npl
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
    
    def dict term
      resp = Net::HTTP.get_response(URI "http://oxforddictionaries.com/search/english/?direct=1&multi=1&q=#{URI.encode term}")
      if resp['Location'].include? '.com/spellcheck/'
        return nil
      end
      src = Net::HTTP.get(URI resp['Location'])
      h = Nokogiri::HTML(src)
      content = (h % '#mainContent')
      out = OpenStruct.new
      out.url = resp['Location']
      out.entry = (content % 'h1.entryTitle').inner_text
      out.pronunciation = (content % 'div.entryPronunciation a').inner_text.strip
      out.senses = []
      content.search('section.senseGroup').each do |sg|
        sense = OpenStruct.new
        sense.word_type = (sg % 'span.partOfSpeech').inner_text
        sense.inflections = sg.search('span.inflection').map(&:inner_text)
        sense.meanings = []
        sg.search('ul.sense-entry').each do |se|
          entry = OpenStruct.new
          entry.definition = (se % 'li.sense span.definition').inner_text
          entry.examples = se.search('li.sense em.example').map {|ex| ex.inner_text.strip }
          entry.subsenses = se.search('li.subSense').map {|ss| OpenStruct.new(:definition => (ss % 'span.definition').inner_text, :examples => ss.search('em.example').map(&:inner_text)) }
          sense.meanings << entry
        end
        out.senses << sense
      end
      out
    end
    
    def normalize_url url
      if url.match(/^[a-z][\w-]+:/i)
        url
      else
        "http://#{url}"
      end
    end
    
    def shorten_url url
      Net::HTTP.get(URI "http://tinyurl.com/api-create.php?url=#{URI.encode(url)}")
    end
    
    def wikipedia lang='en', search
      maxlen = 250
      
      article_url = google("#{search} site:#{lang}.wikipedia.org/wiki")
      return nil if article_url.nil?
      article_slug = article_url.match(%r{\.wikipedia\.org/wiki/(.*)}i)[1]
      categories = Net::HTTP.get(URI("http://en.wikipedia.org/w/api.php?action=query&prop=categories&titles=#{article_slug}&format=json"))
      categories = JSON.parse categories
      disambig = categories['query']['pages'].first[1]['categories'].map{|x| x['title'] }.include? 'Category:Disambiguation pages'
      if disambig
        return OpenStruct.new :url => article_url, :gist => "Disambiguation: #{categories['query']['pages'].first[1]['title']}"
      else
        json_src = Net::HTTP.get(URI("http://#{lang}.wikipedia.org/w/api.php?action=mobileview&page=#{article_slug}&format=json&sections=0"))
        html_src = JSON.parse(json_src)['mobileview']['sections'][0]['text']
        h = Nokogiri::HTML(html_src)
        firstp = (h % 'p').inner_text.gsub(/\[\d+\]/, '')
        gist = ''
        sentences = firstp.split(/(?<=\. )/)
        if sentences.first.length > maxlen
          gist = sentences.first.match(/^(.{,240}\W)/)[1] + " \u2026"
        else
          sentences.each do |sentence|
            break if gist.length + sentence.length >= maxlen
            gist << sentence
          end
        end
        gist.strip!
      
        return OpenStruct.new :url => article_url, :gist => gist
      end
    end
    
    def etymology phrase
      out = OpenStruct.new
      uri = URI "http://etymonline.com/index.php?search=#{URI.encode phrase}"
      out.source = uri.to_s
      src = Net::HTTP.get uri
      h = Nokogiri::HTML(src)
      text = ((h % 'dd.highlight') or return nil).inner_text
      sentences = text.split(/(?<=\. )/)
      gist = ''
      sentences.each {|sentence| (gist << sentence) unless (gist.length + sentence.length) > 250 }
      out.gist = gist
      out
    end
    
    def wolfram_alpha query
      htmlsrc = Net::HTTP.get(URI "http://www.wolframalpha.com/input/?asynchronous=false&i=#{URI.encode(query, /./)}")
      subpodns = Hash.new(0)
      pods = htmlsrc.lines.grep(/"stringified":/).map do |psrc|
        pod_id = psrc.match(/jsonArray\.popups\.([^.]+)\./)[1]
        subpodn = subpodns[pod_id]
        subpodns[pod_id] += 1
        [pod_id, (wa_cleanup JSON.parse(psrc[psrc.index('{"stringified":')..-4])['stringified']), subpodn]
      end
      h = Nokogiri::HTML(htmlsrc)
      pods.map do |pod|
        id, data, subpodn = pod
        podh = (h % "##{id}") # ugh, nokogiri. why no get_element_by_id?
        podtitles = podh.search('h2').inner_text.lines.map(&:strip).reject(&:empty?)
        title = podtitles[subpodn % podtitles.length].strip[0..-2]
        if data.empty?
          data = shorten_url podh.search('img')[subpodn]['src']
        end
        [title, data]
      end
    end
    def wa_cleanup str
      wa_subsup entities(str).gsub(" \u00B0", "\u00B0").gsub(/[[:space:]]{2,}/, ' ').gsub(/~~\s+/, '~').gsub(/\(\s+/,'(').gsub(/\s+\)/,')').gsub(' | ', ': ').gsub("\n", '; ')
    end
    def wa_subsup str
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
  
  command :c, 'Query Google Calculator' do
    require_argstr
    result = google_calculator(argstr)
    if not result['error'].empty?
      respond "#{env.nick}: Sorry, no results!"
    else
      respond "#{result['lhs']} = #{result['rhs']}"
    end
  end
  
  command :chars, 'Search for Unicode characters' do
    require_argstr
    results = unigrep(argstr)
    halt respond('No characters found') if results.empty?
    response = []
    results.each_with_index do |char, i|
      break if ((response.reduce(0) {|acc, c| acc + c.bytesize }) + response.length) > 450
      response << unicode_display(char)
    end
    respond response.join(' ')
  end
  
  command :decode, 'Decode HTML entities' do
    require_argstr
    respond entities argstr
  end
  
  command :ety, 'Look up the etymology of a word or phrase' do
    require_argstr
    result = etymology(argstr)
    if result
      respond "\"#{result.gist.strip}\" \u2014 #{result.source}"
    else
      respond "Sorry, I couldn't find the etymology of that."
    end
  end
  
  command :follows, 'See if one Twitter user follows another' do
    require_argstr
    who, whom = argstr.split(' ')
    result = does_follow(who, whom)
    if result == true
      respond "Yes, #{who} follows #{whom}."
    elsif result == false
      respond "No, #{who} doesn't follow #{whom}."
    else
      respond "(an error occurred while processing this directive)"
    end
  end
  
  command :g, 'Search Google' do
    require_argstr
    respond (google(argstr) or "No results found.")
  end
  
  command :gc, 'Count the number of Google results for a phrase' do
    require_argstr
    counts = google_count(argstr)
    halt respond("Couldn't count results.") if counts == {}
    responses = []
    counts.each do |source, count|
      responses << "#{number_digit_delimit count} (#{source})"
    end
    respond responses.join(', ')
  end
  command :gcs, 'Compare the number of Google results for different phrases' do
    require_argtext
    source = :site
    source = switches[0].to_sym if switches[0] and %w{site api}.include?(switches[0])
    terms = argtext.scan(/\+?"[^"\\]*(?:\\.[^"\\]*)*"|\[[^\]\\]*(?:\\.[^\]\\]*)*\]|\S+/).map do |src|
      term = src.gsub(/^\[|\]$/,'')
      count = google_count(term, [source])[source]
      [count, "#{term} (#{number_digit_delimit count})"]
    end.sort_by(&:first).reverse.map {|a| a[1] }
    respond "[#{source}] #{terms.join ', '}"
  end
  
  command :head, 'Get header information for a page' do
    require_argstr
    uri, header = argstr.split(' ')
    unless uri.match(/[.:\/]/)
      header, uri = uri, header
    end
    uri = URI uri
    http = Net::HTTP.new(uri.host, uri.port)
    sslify(uri, http)
    path = "#{uri.path.empty? ? '/' : uri.path}#{'?'+uri.query if uri.query}"
    resp = http.request_head(path)
    if header
      respond (resp[header] or "Sorry, there was no #{header} header in the response.")
    else
      summary = [resp.code]
      if resp['Content-Type']
        summary << resp['Content-Type']
      end
      if resp['Content-Length']
        summary << "#{resp['Content-Length']} bytes"
      end
      respond summary.join(', ')
    end
  end
  
  command :npl, 'Get the current time from the National Physical Laboratory NTP servers' do
    reply = npl
    respond "#{reply.time.iso8601(6).sub('+00:00', 'Z')} \u2014 #{reply.server}"
  end
  
  command :py, 'Evaluate an expression in Python' do
    require_argstr
    respond Net::HTTP.get(URI "http://tumbolia.appspot.com/py/#{URI.encode argstr}")
  end
  
  command :title, 'Get the title of a web page' do
    title = page_title normalize_url (if argstr.empty?
      env.last_url
    else
      argstr
    end)
    
    if title
      respond title
    else
      respond "#{env.nick}: Sorry, that doesn't appear to be an HTML page."
    end
  end
  
  command :tr, 'Translate some text between languages' do
    require_argtext
    from, to = switches
    from ||= 'auto'
    to ||= 'en'
    text = argtext
    result = translate from, to, text
    respond "#{result.translation} (#{result.from} \u2192 #{result.to})"
  end
  
  command :tw, 'Show a tweet by ID or URL; or get the latest tweet from a user' do
    require_argstr
    tweet = (
      if argstr.match(/^\d+$/)
        tweet_with_id argstr
      elsif argstr.match(/^https?:/)
        tweet_with_id argstr.match(/(\d+)\/?$/)[1]
      else argstr
        tweet_from_user argstr.sub('@', '')
      end
    )
    
    text = expand_twitter_links tweet['text'], tweet['entities']
    respond "#{text} (@#{tweet['user']['screen_name']})"
  end
  
  command :u, 'Search for a Unicode character by codepoint, name, or raw character' do
    require_argstr
    results = unigrep(argstr)
    halt respond('No characters found') if results.empty?
    results.each_with_index do |char, i|
      break if i > 2
      codepoint, name, category, ccc, direction, decomp, dec, digit, num, mirror, oldname, comment, upcase, downcase, tcase = char
      response = "U+#{codepoint} #{((name[0]=='<' and not (oldname.nil? or oldname.empty?)) ? oldname : name)} [#{category}]"
      response << ' ('
      response << unicode_display(char)
      response << ')'
      respond response
      break if name.downcase == argstr.downcase # exact name match? only show one
    end
  end
  
  command :w, 'Look up a word in the Oxford Dictionary of English (not to be confused with the Oxford English Dictionary)' do
    require_argstr
    maxlen = 475
    maxsenselen = 120
    result = dict argstr
    halt respond("Sorry, I couldn't find a definition for '#{argstr}'.") if result.nil?
    url = result.url.gsub(/\?q=(.+)$/, '')
    maxlen -= url.length
    
    senseabbrs = {'noun' => 'n.', 'verb' => 'v.', 'adjective' => 'adj.', 'adverb' => 'adv.', 'exclamation' => 'excl.', 'preposition' => 'prep.'}
    
    response = "#{result.entry} (#{result.pronunciation}): "
    senseresps = []
    result.senses.each do |sense|
      senseresp = (senseabbrs.has_key?(sense.word_type) ? senseabbrs[sense.word_type] : sense.word_type)+' '
      unless sense.inflections.empty?
        senseresp << "(#{sense.inflections.join ', '}) "
      end
      sense.meanings.each_with_index do |meaning, i|
        meaningresp = "#{"#{i+1}." if sense.meanings.length > 1}#{meaning.definition} \"#{meaning.examples.first}\"; "
        if (senseresp.length + meaningresp.length) > maxsenselen
          break
        else
          senseresp << meaningresp
        end
      end
      
      if (response.length + senseresp.length) > maxlen
        break
      else
        response << senseresp
      end
    end
    
    respond "#{response[0..-3]} \u2014 #{url}"
  end
  alias_command :d, :w
  
  command :wa, 'Query Wolfram Alpha' do
    require_argstr
    maxlen = 450
    answer = ''
    lasttitle = ''
    wolfram_alpha(argstr).each do |pod|
      title, data = pod
      part = (if ['Result', 'Results', 'Exact result'].include? title or title == lasttitle
        "#{data}; "
      elsif ['Input', 'Input interpretation'].include? title
        "#{data}: "
      elsif title == 'Interpretations'
        ''
      else
        lasttitle = title
        "#{title}: #{data}; "
      end)
      break if (answer.length + part.length) > maxlen
      answer << part
      answer.gsub!(/[[:space:]]{2,}/, ' ')
    end
    if answer.empty?
      respond "#{env.nick}: Sorry, no result!"
    else
      respond answer[0..-3]
    end
  end
  
  command :wik, 'Search for an article on Wikipedia' do
    require_argtext
    lang = (switches.first or 'en')
    search = argtext
    
    article = wikipedia lang, search
    if article
      respond "\"#{article.gist}\" \u2014 #{article.url}"
    else
      respond "#{env.nick}: Sorry, I couldn't find an article."
    end
  end
end


# encoding: utf-8

require 'net/https'
require 'json'
require 'nokogiri' # RIP Hpricot
require 'bigdecimal'

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
        uri = URI "http://www.google.com/search?&q=#{URI.encode(query)}&nfpr=1&filter=0"
        http = Net::HTTP.new(uri.host)
        response = http.request_get(uri.path+'?'+uri.query, {'User-Agent' => 'Mozilla/5.0'})
	if response.is_a? Net::HTTPRedirection
          response = http.request_get(response['location'], {'User-Agent' => 'Mozilla/5.0'})
        end
        h = Nokogiri::HTML(response.body)
        if (h % 'div.e') and (h % 'div.e').inner_text.include? 'No results found'
          counts[:site] = 0
        else
          counts[:site] = (h % '#resultStats').inner_text.gsub(/[^0-9]/,'').to_i
        end
      end
      if kinds.include? :end and counts[:site] != 0
        lasturi = URI 'http://www.google.com/'
        uri = URI "http://www.google.com/search?&q=#{URI.encode(query)}&nfpr=1&filter=0&start=90"
        h = nil
        10.times do
          http = Net::HTTP.new(uri.host)
          response = http.request_get(uri.path+'?'+uri.query, {'User-Agent' => 'Mozilla/5.0', 'Referer' => lasturi.to_s})
          h = Nokogiri::HTML(response.body)
          
          pagemover = h.xpath('//div[@id="foot"]/table[@id="nav"]/tr[@valign="top"]/td[not(@class="b")]').last
          if pagemover and pagemover % 'a'
            lasturi = uri
            uri = URI "http://www.google.com#{(pagemover % 'a')['href']}"
          else
            break
          end
        end
        if h
          counts[:end] = (h % '#resultStats').inner_text.match(/([\d,]+) res/)[1].gsub(',','').to_i
        end
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
      counts.delete(:end) if counts[:site] == counts[:end]
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
    
    def superscript str
      base = 0x2070
      special = {'1' => "\u00B9", '2'=>"\u00B2", '3' => "\u00B3", '(' => "\u207D", ')' => "\u207E", '-' => "\u207B", '+' => "\u207A"}
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
        location = resp['Location']
        puri = URI(url) # 'parsed uri'
        location = "#{puri.scheme}://#{puri.host}#{":#{puri.port}" if puri.port != puri.default_port}#{location}" if location[0] == '/'
        url = location
        resp = http_get url
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
      cjk_blocks = [0x4E00..0x9FFF, 0x3400..0x4DBF, 0x20000..0x2A6DF, 0x2A700..0x2B73F, 0x2B740..0x2B740]
      File.open('./data/UnicodeData.txt', 'r') do |f|
        matches = []
        f.each_line do |line|
          char = line.chomp.split(';')
          codepoint, name, category, ccc, direction, decomp, dec, digit, num, mirror, oldname, comment, upcase, downcase, tcase = char
          next if (0xD800..0xDFFF).include? codepoint.to_i(16)
          
          # THIS IS NOT THREAD-SAFE
          # (but then again, nothing is ...)
          match = (case str
          when /\A(?:U\+)?([0-9a-f]{4,})\Z/i
            codepoint.to_i(16) == $~[1].to_i(16)
          when /\A(?:U\+)?([0-9a-f]{4,})\s?-\s?(?:U\+)?([0-9a-f]{4,})\Z/i
            mincp = $~[1].to_i(16)
            maxcp = $~[2].to_i(16)
            (mincp..maxcp).include? codepoint.to_i(16)
          when /\A[a-z0-9 \-]{2,}\Z/i
            words = str.split(/\W+/).map(&:downcase)
            re = /#{words.map {|w| "\\b#{Regexp.quote w}\\w*?" }.join '\W(?:\w*?\W)?'}/i
            name[0] != '<' and name.match(re) or (oldname and oldname.match(re))
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
      uri = URI "https://translate.google.com/"
      http = Net::HTTP.new(uri.host)
      sslify(uri, http)
      params = {
        "sl" => from.downcase,
        "tl" => to.downcase,
        "js" => "n",
        "prev" => "_t",
        "hl" => "en",
        "ie" => "UTF-8",
        "text" => text
      }
      response = http.request_post(uri.path, URI.encode_www_form(params), {'User-Agent' => 'Mozilla/5.0'})
      puts response.body
      h = Nokogiri::HTML response.body
      translation = (h % '#result_box').inner_text
      from = (h % '#nc_dl')['value']
      from = (h % '#nc_sl')['value'] if from.empty?
      to = (h % '#nc_tl')['value']
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
      resp = Net::HTTP.get_response(URI "http://www.oxforddictionaries.com/search/english/?direct=1&multi=1&q=#{URI.encode term}")
      if resp['Location'].include? '.com/spellcheck/'
        return nil
      end
      src = Net::HTTP.get(URI resp['Location'])
      h = Nokogiri::HTML(src)
      content = (h % '.entryPageContent')
      out = OpenStruct.new
      out.url = resp['Location']
      out.entry = (content % '.pageTitle').inner_text
      out.homograph = ((content % '.pageTitle span.homograph').inner_text.strip rescue nil)
      if out.homograph
        out.entry = out.entry[0...-(out.homograph.length)]
      end
      out.pronunciation = ((content % 'div.headpron').inner_text.strip[15..-1].gsub("\u00A0", ' ').gsub(/\s{2,}/, '').gsub(' ,', ', ').gsub(' /', '/') rescue nil)
      # see http://www.phon.ucl.ac.uk/home/wells/ipa-english-uni.htm
      out.pronunciation = out.pronunciation.gsub('əː', 'ɜː').gsub(/a(?!ʊ)/, 'æ').gsub('ʌɪ', 'aɪ').gsub('ɛː', 'eə')
      
      out.senses = []
      content.search('section.senseGroup').each do |sg|
        sense = OpenStruct.new
        sense.word_type = ((sg % 'span.partOfSpeech').inner_text rescue nil).strip
        sense.inflections = sg.search('span.inflection').map(&:inner_text)
        sense.meanings = []
        sg.search('div.sense').each do |se|
          entry = OpenStruct.new
          entry.definition = (se % 'span.definition').inner_text.strip
          entry.examples = se.search('li.sense em.example').map {|ex| ex.inner_text.strip }
          entry.subsenses = se.search('li.subSense').map {|ss| OpenStruct.new(:definition => (ss % 'span.definition').inner_text, :examples => ss.search('em.example').map(&:inner_text)) }
          sense.meanings << entry
        end
        out.senses << sense
      end
      out
    end
    def dict_truncate text
      if text.length >= 190
        text.gsub(/\A(.{,190}\W).+\Z/, "\\1\u2026")
      else
        text
      end
    end
    
    def normalize_url url
      if url.match(/^[a-z][\w-]+:/i)
        url
      else
        "http://#{url}"
      end
    end
    
    def validate url
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
    
    def shorten_url url
      Net::HTTP.get(URI "http://is.gd/create.php?format=simple&url=#{URI.encode(url, /./)}")
    end
    
    def wikipedia lang='en', search
      maxlen = 350
      
      uri = URI "https://#{lang}.wikipedia.org/w/index.php?search=#{URI.encode search}&title=Special%3ASearch"
      http = Net::HTTP.new(uri.host, uri.port)
      sslify(uri, http)
      path = "#{uri.path.empty? ? '/' : uri.path}#{'?'+uri.query if uri.query}"
      resp = http.request_head(path)
      article_url = (resp['Location'] or google("site:#{lang}.wikipedia.org/wiki #{search}"))
      return nil if article_url.nil?
      article_slug = article_url.match(%r{\.wikipedia\.org/wiki/(.*)}i)[1]
      categories = http_get("https://en.wikipedia.org/w/api.php?action=query&prop=categories&titles=#{article_slug}&format=json").body
      categories = JSON.parse categories
      disambig = categories['query']['pages'].first[1]['categories'].to_a.map{|x| x['title'] }.include? 'Category:Disambiguation pages'
      if disambig
        return OpenStruct.new :url => article_url, :gist => "Disambiguation: #{categories['query']['pages'].first[1]['title']}"
      else
        json_src = http_get("https://#{lang}.wikipedia.org/w/api.php?action=mobileview&page=#{article_slug}&format=json&sections=0").body
        j = JSON.parse(json_src)
        html_src = j['mobileview']['sections'][0]['text']
        h = Nokogiri::HTML(html_src)
        firstp = h.css('body > p').reject {|p| p % '#coordinates' }.first
        if firstp
          firstp = firstp.inner_text.gsub(/\[(?:(?:nb )?\d+|citation needed|unreliable source\?)\]/, '')
          gist = (sentence_truncate(firstp, maxlen) or j['mobileview']['normalizedtitle'])
        else
          gist = j['mobileview']['normalizedtitle']
        end
        
        return OpenStruct.new :url => article_url, :gist => gist
      end
    end
    
    def etymology phrase
      out = OpenStruct.new
      uri = URI "http://etymonline.com/index.php?search=#{URI.encode phrase}&searchmode=term"
      src = Net::HTTP.get uri
      h = Nokogiri::HTML(src)
      out.headword = ((h % 'dt.highlight > a') or return nil).inner_text.strip
      text = ((h % 'dd.highlight') or return nil).inner_text
      out.gist = sentence_truncate text, 250
      out.source = URI.join(uri.to_s, (h % 'dt.highlight > a')['href']).to_s.sub('&allowed_in_frame=0', '')
      out
    end
    
    def sentence_truncate text, maxlen=250
      begin
        gist = ''
        abbrs = ["cf", "lit", "etc", "Ger", "Du", "Skt", "Rus", "Eng", "Amer.Eng",
                 "Sp", "Fr", "N", "E", "S", "W", "L", "Gen", "J.C", "dial", "Gk",
                 "19c", "18c", "17c", "16c", "St", "Capt", "obs", "Jan", "Feb",
                 "Mar", "Apr", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec", "c", "tr",
                 "e", "g"]
        re = /(?<=(?<!#{abbrs.map {|a| Regexp.quote a }.join '|'})\. )/
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
  
  command :c, 'Query Wolfram Alpha for a calculator result' do
    require_argstr
    result = wolfram_alpha(argstr)
    
    relevant_pods = result.select {|pod| ['Result', 'Results', 'Exact result', 'Input', 'Input interpretation'].include? pod[0] }.map {|pod| pod[1] }
    approx = result.select {|pod| pod[0] == 'Decimal approximation' }[0]
    
    if (relevant_pods.length < 2) and not (relevant_pods.length == 1 and approx)
      respond "I don't know"
    else
      answer = relevant_pods.join(' = ')
      if approx
        approx = approx[1]
        if m = approx.match(/\d+(\.\d+)/)
          approx = BigDecimal.new(m[0]).round(15).to_s('F')
        end
        answer << " \u2248 #{approx}"
      end
      respond answer
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
  
  alias_command :d, :w
  
  command :decode, 'Decode HTML entities' do
    require_argstr
    respond entities argstr
  end
  
  command :ety, 'Look up the etymology of a word or phrase' do
    require_argstr
    result = etymology(argstr)
    if result
      respond "#{result.headword}: \"#{result.gist.strip}\" \u2014 #{result.source}"
    else
      respond "Sorry, I couldn't find the etymology of that."
    end
  end
  
  command :g, 'Search Google' do
    require_argstr
    respond (google(argstr) or "No results found.")
  end
  
  command :gc, 'Count the number of Google results for a phrase' do
    require_argtext
    allkinds = %w{site end api}
    if not switches.empty?
      kinds = switches.map {|kind| kind.to_sym if allkinds.include? kind }.compact
    else
      kinds = allkinds.map(&:to_sym)
    end
    counts = google_count(argtext, kinds)
    halt respond("Couldn't count results.") if counts.empty?
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
    
    if not uri.index('://')
      uri = "http://#{uri}"
    end
    
    uri = URI uri
    http = Net::HTTP.new(uri.host, uri.port)
    sslify(uri, http)
    path = "#{uri.path.empty? ? '/' : uri.path}#{'?'+uri.query if uri.query}"
    resp = http.request_head(path)
    if header
      respond (resp[header] or "Sorry, there was no #{header} header in the response.")[0...512]
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
  
  alias_command :ietf, :rfc
  
  alias_command :i_love_the_w3c, :val
  
  # todo: make a general "google api call" function for this and .news
  command :img, 'Search for an image with Google image search' do
    if argstr.downcase.include? 'lily' and argstr.downcase.include? 'cole' # for Noah
      halt respond "#{env.nick}: Sorry, this command cannot be used to search for photos of Lily Cole."
    end
    src = Net::HTTP.get URI("http://ajax.googleapis.com/ajax/services/search/images?q=#{URI.encode argstr}&v=1.0&safe=off")
    result = JSON.parse src
    if result.has_key? 'responseData' and
       result['responseData'].has_key? 'results' and
       not result['responseData']['results'].empty? and
       result['responseData']['results'].first.has_key? 'unescapedUrl'
      url = result['responseData']['results'].first['unescapedUrl']
      respond "#{url} (more: #{shorten_url result['responseData']['cursor']['moreResultsUrl']})"
    else
      respond "#{env.nick}: Sorry, no image search result!"
    end
  end
  
  command :mangle, 'Put a phrase through the multiple-translation mangle' do
    require_argstr
    phrase = argstr
    prevlang = 'en'
    %w{la sr ta sw ht en}.each do |lang|
      phrase = translate(prevlang, lang, phrase).translation
      prevlang = lang
    end
    respond phrase
  end
  
  command :news, 'Search for a recent news article' do
    src = Net::HTTP.get URI("http://ajax.googleapis.com/ajax/services/search/news?q=#{URI.encode argstr}&v=1.0&safe=off")
    result = JSON.parse src
    if result.has_key? 'responseData' and
       result['responseData'].has_key? 'results' and
       not result['responseData']['results'].empty? and
       result['responseData']['results'].first.has_key? 'unescapedUrl'
      url = result['responseData']['results'].first['unescapedUrl']
      respond "#{page_title url}: #{url}"
    else
      respond "#{env.nick}: Sorry, no news search result!"
    end
  end
  
  command :npl, 'Get the current time from the National Physical Laboratory NTP servers' do
    reply = npl
    respond "#{reply.time.iso8601(6).sub('+00:00', 'Z')} \u2014 #{reply.server}"
  end
  
  command :py, 'Evaluate an expression in Python' do
    require_argstr
    respond Net::HTTP.get(URI "http://tumbolia.appspot.com/py/#{URI.encode argstr, /./}")[0...400]
  end
  
  command :rfc, 'Get a link and title for an RFC or another IETF document' do
    require_argstr
    if m=argstr.match(/^(?:rfc ?)?(\d+)$/i)
      url = "http://tools.ietf.org/html/rfc#{m[1]}"
    elsif m=argstr.match(/^(?:bcp ?)(\d+)$/i)
      url = "http://tools.ietf.org/html/bcp#{m[1]}"
    else
      url = google "site:tools.ietf.org/html #{argstr}"
    end
    title = page_title url
    if url.nil? or title.nil?
      respond "Sorry, no document found."
    else
      respond "#{title}: #{url}"
    end
  end
  
  command :title, 'Get the title of a web page' do
    title = page_title normalize_url (if argstr.empty?
      env.last_url
    else
      argstr
    end)
     
    if title
      respond title[0...512]
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
      break if name == argstr.upcase or oldname == argstr.upcase # exact name match? only show one
    end
  end
  
  command :val, 'Validate the source of a web page' do
    result = validate (argstr.empty? ? env.last_url : argstr)
    if result.valid.nil?
      halt respond "NOT SURE IF INVALID / OR VALIDATOR SCREWED UP"
    end
    
    respond "#{result.message} \u2014 #{result.source}"
  end
  
  command :w, 'Look up a word in the Oxford Dictionary of English (not to be confused with the Oxford English Dictionary)' do
    require_argstr
    maxlen = 430
    maxsenselen = 200
    result = dict argstr
    halt respond("Sorry, I couldn't find a definition for '#{argstr}'.") if result.nil?
    url = shorten_url result.url.gsub(/\?q=(.+)$/, '')
    maxlen -= url.length
    
    senseabbrs = {'noun' => 'n.', 'verb' => 'v.', 'adjective' => 'adj.', 'adverb' => 'adv.', 'exclamation' => 'excl.', 'preposition' => 'prep.', 'abbreviation' => 'abbr.'}
    
    response = "#{result.entry}#{superscript result.homograph if result.homograph}#{" (#{result.pronunciation})" if result.pronunciation}: "
    senseresps = []
    result.senses.each do |sense|
      senseresp = "#{(senseabbrs.has_key?(sense.word_type) ? senseabbrs[sense.word_type] : sense.word_type)} "
      unless sense.inflections.empty?
        senseresp << "(#{sense.inflections.join ', '}) "
      end
      sense.meanings.each_with_index.map do |meaning, i|
        example = ": #{meaning.examples.first}" unless (meaning.examples.empty? or (meaning.definition.length + (meaning.examples.first || '').length) >= (maxsenselen - 4))
        if example and result.entry.length > 3
          example = example.gsub(/\b#{Regexp.quote result.entry}/, "\u2053")
        end
        meaningresp = "#{"#{i+1}. " if sense.meanings.length > 1}#{dict_truncate meaning.definition.gsub(/[\.:]$/, '')}#{example}; "
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
      respond "#{env.nick}: Sorry, I couldn't find article."
    end
  end
end

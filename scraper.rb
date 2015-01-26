#!/usr/bin/env ruby

require 'digest/md5'
require 'logger'
require 'open-uri'
require 'pstore'
require 'rss'
require 'net/smtp'
require 'time'


#-----------------------------------------------------------------------
# Setup
#-----------------------------------------------------------------------
Dir.mkdir 'logs' unless Dir.exists? 'logs'
@log = Logger.new('logs/log.txt', 'daily')

filename      = 'feeds.txt'

@db_feeds     = PStore.new('feeds.db', thread_safe = true)
@db_parsed    = PStore.new('parsed.db', thread_safe = true)
EMAIL_ADDR    = ENV['EMAIL_ADDRESS']
EMAIL_PASS    = ENV['EMAIL_PASSCODE']
EMAIL_DOMAIN  = ENV['EMAIL_DOMAIN']
EMAIL_SERVER  = ENV['EMAIL_SERVER']

@new_items   = []

#-----------------------------------------------------------------------
# Functionality
#-----------------------------------------------------------------------

def handle_item item, feed
  case feed.feed_type  # Normalise a couple of fields
  when 'rss'
    t = Time.parse item.pubDate.to_s
    entry = {
      :title     => item.title.to_s,
      :published => t,
      :link      => item.link.to_s,
      :summary   => item.description.to_s
    }
  when 'atom'
    t = Time.parse item.updated.content.to_s
    entry = {
      :title     => item.title.content.to_s,
      :published => t,
      :link      => item.link.href.to_s,
      :summary   => item.content.content.to_s
    }
  else
    return
  end

  md5 = Digest::MD5.hexdigest entry[:link]
  @log.debug "md5: #{md5} for #{entry[:link]}"

  @db_parsed.transaction do
    return if @db_parsed.root? md5  # Have we seen this already?
    @db_parsed[md5] = ''
  end

  @new_items << entry
end


def get_feed feed
  @log.debug "Opening: #{feed[:url]}"
  begin
    open(feed[:url],
         "If-None-Match" => feed[:etag],
         "If-Modified-Since" => feed[:last_modified].rfc2822) do |rss|

      feed[:etag]         = rss.meta['etag'].to_s
      feed[:last_checked] = Time.now

      @db_parsed.transaction {@db_parsed[feed[:md5] = feed]}
      parsed = RSS::Parser.parse rss, false
      parsed.items.each do |item|
        handle_item item, parsed
      end
    end

  rescue OpenURI::HTTPError => error
    @log.debug "#{error.io.status}"
  end
end


def send_mail items
  msg = <<MESSAGE_END
MIME-Version: 1.0
Content-type: text/html
Subject: #{items.length} New items

<h1>New Items:</h1>
<ul>
MESSAGE_END

  items.each do |item|
    msg << "<li><a href=\"#{item[:link]}\">#{item[:title]}</a></li>"
  end
  msg << '</ul></body></html>'

  smtp = Net::SMTP.new EMAIL_SERVER, 587
  smtp.enable_starttls
  smtp.start(EMAIL_DOMAIN, EMAIL_ADDR, EMAIL_PASS, :login) { smtp.send_message(msg, EMAIL_ADDR, EMAIL_ADDR) }
end


#-----------------------------------------------------------------------
# Get things going
#-----------------------------------------------------------------------

# First insure the urls in feeds.txt are in the tracking db
File.open(filename, 'r').each_line do |url|
  #get the md5
  md5 = Digest::MD5.hexdigest url
  @db_feeds.transaction do
    next if @db_feeds.root? md5

    @db_feeds[md5] = {:url => url.strip,
                      :md5 => md5,
                      :etag => '',
                      :last_modified => Time.new(2014)}
  end
  # TODO: Check any feeds have not been removed (or rather, remove any
  #       that have)
end

# Retrive the the feeds
@db_feeds.transaction do
  @db_feeds.roots.each do |feed|
    get_feed @db_feeds[feed]
  end
end


# Send an email with anything new
if @new_items.length > 0
  send_mail @new_items
  @new_items.each do |item|
    puts item[:title]
  end
end

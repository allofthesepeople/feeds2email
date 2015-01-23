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

filename     = 'feeds.txt'

@db          =  PStore.new('existing.db', thread_safe = true)
EMAIL_ADDR   = ENV['EMAIL_ADDRESS']
EMAIL_PASS   = ENV['EMAIL_PASSCODE']
EMAIL_DOMAIN = ENV['EMAIL_DOMAIN']
EMAIL_SERVER = ENV['EMAIL_SERVER']

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

  @db.transaction do
    return if @db.root? md5  # Have we seen this already?
    @db[md5] = ''
  end

  @new_items << entry
end


def get_feed url
  @log.debug "Opening: #{url}"
  open(url) do |rss|
    feed = RSS::Parser.parse rss, false
    feed.items.each do |item|
      handle_item item, feed
    end
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


def maybe_add_feed url

end

#-----------------------------------------------------------------------
# Get things going
#-----------------------------------------------------------------------

# Retrive the the feeds
File.open(filename, 'r').each_line do |url|
    get_feed url if url
end

# Send an email with anything new
if @new_items.length > 0
  send_mail @new_items
  @new_items.each do |item|
    puts item[:title]
  end
end

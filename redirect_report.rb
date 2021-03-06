#!/usr/bin/env ruby

require 'zlib'
require 'ostruct'
require 'bundler/setup'

Bundler.require(ENV.fetch('RUBY_ENVIRONMENT', 'development'))

$config = OpenStruct.new(
  nginx_redirect_files: '/etc/nginx/conf.d/*redirects.map',
)


Redirect = Struct.new("Redirect", :public, :syndication, :google, :bing) do
  def <=>(other)
    [self.public, syndication, google, bing] <=>
      [other.public, other.syndication, other.google, other.bing]
  end
end


class LogLine
  attr_reader :source_ip, :path, :user_agent, :status

  def initialize(source_ip, path, user_agent, status)
    @source_ip = source_ip
    @path = path
    @user_agent = user_agent
    @status = status
  end

  def bing_bot?
    @user_agent.match(/bingbot/)
  end

  def google_bot?
    @user_agent.match(/Googlebot/)
  end

  def syndication?
    @source_ip == '66.235.132.38'
  end

  def redirect?
    (300..308).include?(status)
  end

  class << self
    def from_line(line)
      line_bits = line.split(/\s/)
      # Logs on the central server have some extra info (source and time/date)
      # appended to each line, so we'll the bits of the line we want relative
      # to the '-' marker on each line.
      log_offset = line_bits.index('-')
      source_ip = line_bits[log_offset - 1]
      path = line_bits[log_offset + 5].sub(/\?.*/, '')
      user_agent = line_bits[11..-1].join(' ')
      status = line_bits[log_offset + 7].to_i
      LogLine.new(source_ip, path, user_agent, status)
    end
  end
end


module RedirectReport
  module_function

  def load_redirects_from_file redirects_file
    File.foreach(redirects_file) do |line|
      case line
      when /^~(\*)?(\S+)/
        source_url = Regexp.new($2, $1 ? Regexp::IGNORECASE : 0)
        $redirects[source_url] = Redirect.new(0, 0, 0, 0)
      end
    end
  end

  def process_line(log_line)
    return if log_line.path == '/' || log_line.source_ip == '10.50.6.148'

    matched_redirect = $redirects.keys.find { |r| log_line.path.match(r) }
    count_redirect(log_line, matched_redirect) if matched_redirect
  end

  def count_redirect(log_line, matched_redirect)
    if log_line.syndication?
      $redirects[matched_redirect].syndication += 1
    elsif log_line.google_bot?
      $redirects[matched_redirect].google += 1
    elsif log_line.bing_bot?
      $redirects[matched_redirect].bing += 1
    else
      $redirects[matched_redirect].public += 1
    end
  end

  def run(args)
    redirects_files = Dir[$config.nginx_redirect_files]
    log_files = args

    $redirects = {}

    redirects_files.each do |redirects_file|
      load_redirects_from_file(redirects_file)
    end

    log_files.each do |log_file|
      if log_file == '-'
        file = STDIN
      elsif File.extname(log_file) == '.gz'
        file = Zlib::GzipReader.open(log_file)
      else
        file = File.new(log_file)
      end
      file.each_line do |line_text|
        line = LogLine.from_line(line_text)
        process_line(line) if line.redirect?
      end
    end

    puts %w{public syndication google bing path}.join("\t")
    $redirects.keys.sort { |a, b| $redirects[b] <=> $redirects[a] }
      .each do |redirect|
      puts [$redirects[redirect].public,
            $redirects[redirect].syndication,
            $redirects[redirect].google,
            $redirects[redirect].bing,
            redirect.source].join("\t")
    end
  end
end

if File.basename($0) == __FILE__
  RedirectReport.run(ARGV)
end


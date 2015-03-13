#!/usr/bin/env ruby

require 'bundler/setup'
require 'zlib'
require 'ostruct'
require 'mail'
require 'optparse'

Bundler.require(ENV.fetch('RUBY_ENVIRONMENT', 'development'))

$config = OpenStruct.new(
  nginx_redirect_files: '/etc/nginx/conf.d/*redirects.map',
)


class Redirect
  attr :regexp, :public, :syndication, :google, :bing

  def initialize(regexp)
    @regexp = regexp
    @public = @syndication = @google = @bing = 0
  end

  def <=>(other)
    [self.public, syndication, google, bing] <=>
      [other.public, other.syndication, other.google, other.bing]
  end

  def count_log_line(log_line)
    if log_line.syndication?
      @syndication += 1
    elsif log_line.google_bot?
      @google += 1
    elsif log_line.bing_bot?
      @bing += 1
    else
      @public += 1
    end
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

  def parse_options(args)
    OptionParser.new do |opts|
      opts.banner = "Usage: #{File.basename($0)} [options]"

      opts.on("-m", "--mail=ADDRESS", "Mail report to ADDRESS") do |address|
        $config.mail_to_address = address
      end

      opts.on_tail("-h", "--help", "Show this message") do
        puts opts
        exit
      end
    end.parse!(args)

    args
  end

  def load_redirects_from_file(redirects_file)
    File.foreach(redirects_file) do |line|
      case line
      when /^~(\*)?(\S+)/
        pattern = $2
        regexp = Regexp.new(pattern, $1 ? Regexp::IGNORECASE : 0)
        $redirects[pattern] = Redirect.new(regexp)
      end
    end
  end

  def process_line(log_line)
    return if log_line.path == '/' || log_line.source_ip == '10.50.6.148'

    matched_redirect = $redirects.keys.find do |pattern|
      log_line.path.match $redirects[pattern].regexp
    end
    $redirects[matched_redirect].count_log_line(log_line) if matched_redirect
  end

  def run(args)
    log_files = parse_options args
    redirects_files = Dir[$config.nginx_redirect_files]

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

    redirects_sorted = $redirects.values.sort
    if $config.mail_to_address
      report_file = StringIO.new
      format_output redirects_sorted, report_file, ','
      mail_redirects_report $config.mail_to_address, report_file.string
    else
      format_output redirects_sorted, $stdout
    end
  end

  def format_output(redirects, stream, delimit="\t")
    stream.puts %w{public syndication google bing path}.join(delimit)
    redirects.each do |redirect|
      stream.puts [redirect.public,
                   redirect.syndication,
                   redirect.google,
                   redirect.bing,
                   redirect.regexp.source].join(delimit)
    end
  end

  def mail_redirects_report(to_address, report_contents)
    Mail.deliver do
      from 'development.team@moneyadviceservice.org.uk'
      to to_address
      subject "Redirects Report"
      add_file filename: "Redirects Report #{Date.today.to_s}.csv",
               content: report_contents
    end
  end
end

if $0 == __FILE__
  RedirectReport.run(ARGV)
end


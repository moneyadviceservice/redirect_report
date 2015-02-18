require 'rspec'

$: << '.'
require 'redirect_report'

class FakeFS::File
  def self.foreach(name)
    File.readlines(name).each { |line| yield line }
  end
end


RSpec.describe RedirectReport do
  describe '.run' do
    before do
      FakeFS.activate!
      FileUtils.mkdir_p('/etc/nginx/conf.d')
      File.write(
        '/etc/nginx/conf.d/test-redirects.map',
        "~*^/article/?$ /en/article;\n"
      )
      File.write('production.log', log_line)
    end

    after do
      FakeFS.deactivate!
    end

    context 'when a public ip is matched' do
      let :log_line do
        '5.148.140.228 - - [16/Feb/2015:15:39:36 +0000] "GET /article/ HTTP/1.1" 302 178 "-" "-" 0.000 0.000 [-] [-]'
      end

      it 'outputs the number of matches' do
        expect {
          RedirectReport.run(['production.log'])
        }.to output(<<EOD).to_stdout
public	syndication	google	bing	path
1	0	0	0	^/article/?$
EOD
      end
    end

    context 'when a bingbot user agent is matched' do
      let :log_line do
        '5.148.140.228 - - [16/Feb/2015:15:39:36 +0000] "GET /article/ HTTP/1.1" 302 178 "-" "Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)" 0.000 0.000 [-] [-]'
      end

      it 'outputs the number of matches' do
        expect {
          RedirectReport.run(['production.log'])
        }.to output(<<EOD).to_stdout
public	syndication	google	bing	path
0	0	0	1	^/article/?$
EOD
      end
    end

    context 'when a googlebot user agent is matched' do
      let :log_line do
        '5.148.140.228 - - [16/Feb/2015:15:39:36 +0000] "GET /article/ HTTP/1.1" 302 178 "-" "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)" 0.000 0.000 [-] [-]'
      end

      it 'outputs the number of matches' do
        expect {
          RedirectReport.run(['production.log'])
        }.to output(<<EOD).to_stdout
public	syndication	google	bing	path
0	0	1	0	^/article/?$
EOD
      end
    end

    context 'when a syndication source ip is matched' do
      let :log_line do
        '66.235.132.38 - - [16/Feb/2015:15:39:36 +0000] "GET /article/ HTTP/1.1" 302 178 "-" "-" 0.000 0.000 [-] [-]'
      end

      it 'outputs the number of matches' do
        expect {
          RedirectReport.run(['production.log'])
        }.to output(<<EOD).to_stdout
public	syndication	google	bing	path
0	1	0	0	^/article/?$
EOD
      end
    end

    context 'when the log line comes from the central server' do
      let :log_line do
        'Feb 16 15:39:36 416516-nginx1 production-frontend: 5.148.140.228 - - [16/Feb/2015:15:39:36 +0000] "GET /article/ HTTP/1.1" 302 178 "-" "-" 0.000 0.000 [-] [-]'
      end

      it 'outputs the number of matches' do
        expect {
          RedirectReport.run(['production.log'])
        }.to output(<<EOD).to_stdout
public	syndication	google	bing	path
1	0	0	0	^/article/?$
EOD
      end
    end

    context 'when not a redirect' do
      let :log_line do
        '5.148.140.228 - - [16/Feb/2015:15:39:36 +0000] "GET /article/ HTTP/1.1" 200 178 "-" "-" 0.000 0.000 [-] [-]'
      end

      it 'outputs the number of matches' do
        expect {
          RedirectReport.run(['production.log'])
        }.to output(<<EOD).to_stdout
public	syndication	google	bing	path
0	0	0	0	^/article/?$
EOD
      end
    end

    context 'when does not match path' do
      let :log_line do
        '5.148.140.228 - - [16/Feb/2015:15:39:36 +0000] "GET /something/ HTTP/1.1" 302 178 "-" "-" 0.000 0.000 [-] [-]'
      end

      it 'outputs the number of matches' do
        expect {
          RedirectReport.run(['production.log'])
        }.to output(<<EOD).to_stdout
public	syndication	google	bing	path
0	0	0	0	^/article/?$
EOD
      end
    end
  end
end


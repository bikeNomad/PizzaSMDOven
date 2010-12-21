# $Id$
# Web server (using Sinatra framework) for GC29 tester
require 'rubygems'
require 'cgi'
require 'fileutils'
require 'pp'
require 'config' 
require 'sinatra/base'

$webroot ||= config(:WebRootDirectory)
$webroot ||= File.expand_path(File.join(File.dirname(__FILE__), '../webserver'))

# webauth is array of 2 strings: user/password
if $webauth.nil?
  pwfile = File.join($webroot, 'basicauth.yaml')
  unless File.exist?(pwfile)
    File.open(pwfile,'w+') { |f| f.print( ['zeno','password'].to_yaml ) }
  end
  $webauth = YAML::load_file(pwfile)
end

require 'graphViewerServer'

if $calibrator.nil?
  require 'test/webmock'
  $calibrator = MockCalibrator.new
end

module Webserver
class GC29Tester < Sinatra::Base

  # To require auth on every request:

  # use Rack::Auth::Basic do |username, password|
  #   [username, password] == ['zeno', 'password']
  # end

  %w(public views css).each do |d|
    dfull = File.join($webroot, d)
    FileUtils.mkdir_p(dfull) unless File.directory?(dfull)
  end

  set :root, $webroot
  $webpublic = File.join($webroot, 'public')
  set :public, $webpublic
  set :app_file, __FILE__
  set :environment, :production
  disable :run, :sessions
  enable :logging, :dump_errors, :clean_trace, :lock, :static

  helpers do
    def protected!
      response['WWW-Authenticate'] = %(Basic realm="Testing HTTP Auth") and \
      throw(:halt, [401, "Not authorized\n"]) and \
      return unless authorized?
    end

    def authorized?
      @auth ||=  Rack::Auth::Basic::Request.new(request.env)
      @auth.provided? && @auth.basic? && @auth.credentials && @auth.credentials == $webauth
    end

    def logout
      @auth = nil
    end

    def notWrittenYet
      "<pre>not written yet!</pre>"
    end

    def dutNamed(dutname)
      calibrator.deviceNamed( params[dutname] ) 
    end

    def addRefresh
      refr = params[:refresh] || params['refresh']
      if refr
        headers('refresh' => params['refresh'].to_s)
      end
    end

    def calibrator
      return @calibrator if @calibrator
      @calibrator = $calibrator
    end

    def logView(this_page, log_name, view = :debugLog)
      erb(view, :locals => {
        :log_name => log_name,
        :this_page => this_page,
        :refresh => (params['refresh'] || 10),
        :follow => (params['follow'] == 'true') } )
    end

    def dumpVars(_binding = binding())
      io = StringIO.new
      io.puts "self:", eval('self.pretty_inspect', _binding)
      io.puts "Locals:"
      lvars = eval('local_variables', _binding).sort
      io.puts(lvars.collect { |v| "#{v} = " + eval("#{v}.pretty_inspect", _binding) })
      io.puts "Globals:", global_variables.sort.pretty_inspect
      io.rewind
      "<pre>" + CGI.escapeHTML(io.string) + "</pre>"
    end

    def getSummary(html=false)
      filename = Configuration.batchLogFilename
      return nil if filename.nil?
      $stderr.puts("summarizing batch log #{filename}")
      heads = Hash.new { |h,k| h[k] = 0 }
      rundata = File.open(filename) do |file|
        yaml = YAML::load_stream(file)
        yaml.nil? ? nil : yaml.documents
      end
      return nil if rundata.nil?
      $stderr.puts("size = #{rundata.size}")
      # tally heads and convert data
      sortedHeads = %w{ started serialNumber passed mean prescale meanT2 min max pwmVOffset meanDiscTemp meanBlockTemp meanCalTip discRatio failedAt error }
      data = []
      rundata.each do |h|
        h.keys.each { |k| heads[k] += 1 }
        data << sortedHeads.collect do |head|
          val = h[head]
          case val
            when Float
              if html
                '<td class="ioval">%.2f</td>' % val
              else
                '%.2f' % val
              end
            when Time, DateTime
              if html
                val.strftime('<td class="timestamp">%m/%d/%Y %H:%M:%S</td>')
              else
                val.strftime('%m/%d/%Y %H:%M:%S')
              end
            when String
              if html
                if head == "error"
                  "<td class=\"errormessage\">#{val}</td>"
                else
                  "<td>#{val}</td>"
                end
              else
                val.tr(',', ';')
              end
            else
              if html
                "<td>#{val.to_s}</td>"
              else
                val.to_s
              end
          end 
        end
      end
      return [heads, sortedHeads, data]
    end

    NumberPattern = %r( [-+]? \d* \.? \d+ (?:e[-+]?\d+)? )xi
    RangePattern = %r( #{NumberPattern} \s* \.\.\.? \s* #{NumberPattern} )x
    StringPattern = %r(" (?: \\" | [^"] )* ")x
    BoolPattern = %r(true|false)
    NilPattern = %r(nil)
    ScalarPattern = %r(#{NumberPattern}|#{BoolPattern}|#{StringPattern}|#{RangePattern})x
    ArrayPattern = %r(\[ ((\s*#{ScalarPattern}\s*)(\s*,\s*#{ScalarPattern}\s*)*) \])x
    ParsePattern = %r(#{ArrayPattern}|#{ScalarPattern})x

    Parser = {
      "TrueClass" => BoolPattern,
      "FalseClass" => BoolPattern,
      "Array" => ArrayPattern,
      "Range" => RangePattern,
      "String" => StringPattern,
      "Float" => NumberPattern,
      "Fixnum" => NumberPattern
    }

    # classname -- the name of the original value's class (a String)
    # stringval -- the new value as entered in the form
    def evalConfigParam(classname, stringval)
      # missing value?
      if stringval.nil? && /(True|False)Class/.match(classname)
        return false
      end
      pattern = Parser[classname]
      if pattern.nil?
        $stderr.puts "error parsing #{classname} #{stringval}"
        return
      end
      m = pattern.match(stringval)
      if m && m.pre_match.length.zero? && m.post_match.length.zero?
        return eval(m.string)
      else
        raise SyntaxError.new("#{classname} error parsing \"#{stringval}\"")
      end
    end

    # Return hash of changed values
    def convertParamsToConfig
      # convert params to config hash
      kinds, avals = params.to_a.partition { |a| a[0].end_with?('_kind') }
      vals = {}
      avals.each { |k,v| vals[k] = v }
      kinds.each do |k,clname|
        nm = k.sub(/_kind$/, '')
        vals[nm] = evalConfigParam(clname, vals[nm]) # could raise SyntaxError
      end
      vals
    end

    def processConfigParams
      bad = []
      vals = {}
      begin
        vals = convertParamsToConfig
      rescue SyntaxError
        bad << $!.message
      end
      # everything converted OK: incorporate config
      if bad.empty?
        vals.each_pair { |k,v| config(k, v) }
        stored, deleted = Configuration.saveLocalConfig
        "<pre>Non-default values saved:\n#{stored.pretty_inspect}\n</pre>" +
        "<pre>Values reset to default values:\n#{deleted.pretty_inspect}\n</pre>"
      else
        "<pre>bad: #{bad.join(", ")}\n#{params.pretty_inspect}</pre>"
      end
    end

  end

  # Home screen
  get '/' do
    erb :homeScreen, :locals => { :request => '3+4', :calibrator => calibrator }
  end

  # Prior screen
  get '/back' do
    redirect '/' 
  end

  # View debug log
  get "/log" do
    addRefresh
    logView("/log", $logname || $webserverLogFileName)
  end

  # View debug log
  get "/serverlog" do
    addRefresh
    logView("/serverlog", $webserverLogFileName)
  end

  get "/docs" do
    filenames = Dir.glob($webpublic + "/docs/*.*")
    erb :docs, :locals => { :files => filenames }
  end

  # Eval text expression
  post '/eval' do
    protected!
    originalStdout = $stdout
    originalDebugLog = calibrator.debugLog
    $stdout = StringIO.new
    calibrator.debugLog = $stdout
    request = (params['request'] || '3+4').gsub("%([0-9a-fA-F][0-9a-fA-F])") { |s| s.hex }
    result = begin
      calibrator.instance_eval(request).pretty_inspect
    rescue
      [ $!.message, "stack:", $!.backtrace ].flatten.join("\n")
    ensure
      calibrator.debugLog = originalDebugLog
      $stdout = originalStdout
    end
    if params['plain'] == 'true'
      result
    else
      erb :eval, :locals => { :request => request, :result => result, :title => 'Eval' }
    end
  end

  # View DUT summary
  get '/dut/:dut' do
    dut = dutNamed(:dut)
    erb :dut, :locals => { :dut => dut, :calibrator => calibrator, :pattern => ".*-#{ dut.name }.csv" }
  end

  # Download DUT unit log
  get '/dut/:dut/log/download' do
    dut = dutNamed(:dut)
    attachment(File.split(dut.unitLog.path)[-1])
    File.open(dut.unitLog.path).read
  end

  # Download DUT historical unit log
  # /download/log/P10110/FT03
  get '/download/log/:serial/:dut' do
    filename = "#{params[:serial]}-#{params[:dut]}.csv"
    attachment(filename)
    File.open(File.join(Configuration.csvDirectory, filename)).read
  end

  # View log of a given DUT
  get '/dut/:dut/log' do
    addRefresh
    if params['follow'] == "true"
      unless params.include? 'atend'
        params['atend'] = true
        redirect "#{request.url}&atend=true#endofpage"
      end
    end
    dut = dutNamed(:dut)
    logView("/dut/#{params['dut']}/log", dut.unitLog.path, :csvLog)
    # + dumpVars()
  end

  # View IO status (all DUTs and Calibrator)
  get '/iostatus' do
    params['refresh'] ||= '10'
    addRefresh
    erb :iostatus, :locals => { :calibrator => calibrator(), :refresh => params['refresh'] }
  end

  # IO status change
  post '/iostatus' do
    protected!
    params['refresh'] ||= '10'
    params['refresh'] = '10' if params['refresh'].empty?
    addRefresh
$stderr.puts params.inspect
    # DUT outputs
    calibrator.devices.each_with_index do |dut,i|
      stat = dut.ioStatus
      if params["powerRelay#{i}"] == "on" && !stat["powerRelay"]
        # turn it on
        dut.setPowerRelayState(true)
      elsif !params["powerRelay#{i}"] && stat["powerRelay"]
        # turn it off
        dut.setPowerRelayState(false)
      end

      if params["deviceHighPower#{i}"] == "on" && !stat["deviceHighPower"]
        # turn it on
        dut.gc29.enableHighPower
      elsif !params["deviceHighPower#{i}"] && stat["deviceHighPower"]
        # turn it off
        dut.gc29.enableLowPower
      end
    end

    # Global outputs
    %w(cylindersUp blocksBack coolingValveOn failLamp).each do |k|
      now = calibrator.instance_eval("#{k}.state")
      if params[k] == "on" && !now
        # turn it on
        calibrator.instance_eval("#{k}.state= true")
      elsif !params[k] && now
        # turn it off
        calibrator.instance_eval("#{k}.state= false")
      end
    end

    redirect "#{request.url}?refresh=#{params['refresh']}"
  end

  get '/mode' do
    erb :mode
  end

  post '/mode' do
    processConfigParams + erb(:mode)
  end

  # Machine Configuration view
  get '/config' do
    erb :config
  end

  # Machine Configuration change
  post '/config' do
    protected!
    processConfigParams + erb(:config)
  end

  # Download run summary as CSV file
  get "/summary/download" do
    heads, sortedHeads, data = getSummary()
    attachment('summary.csv')
    return "no data" if data.nil?
    io = StringIO.new
    io.puts(sortedHeads.join(","))
    data.each { |run| io.puts(run.join(",")) }
    io.string
  end

  # View run summary
  get "/summary" do
    heads, sortedHeads, data = getSummary(true)
    return "no data" if data.nil?
    erb :summary, :locals => { :heads => heads, :sortedHeads => sortedHeads, :rundata => data }
  end

  # program reset
  post '/reset' do
    protected!
    system("vncserver -kill :1")
    Thread.new { sleep 5; exit 2 }
    '<h1>Dying in 5 seconds</h1><br><h2>Goodbye, cruel world!</h2><br><a href="/">Home screen</a>'
  end

  get '/discCalHistory' do
    erb :discCalHistory, :locals => { :calibrator => calibrator }
  end

  get '/vnc' do
    protected!
    cmd = config(:VNCServerCommand) || "env USER=zeno vncserver :1 -geometry 1000x750 -depth 8"
    system(cmd)
    "<h3>Started VNC server.</h3>
    Command line: \"#{cmd}\"
    <a href=\"vnc://#{`hostname --fqdn`}:5901\">Click here to view</a><br>
    <a href=\"/\">Home Screen</a>"
  end

  get '/login' do
    protected!
    redirect '/'
  end

end # Webserver::GC29Tester
end # module Webserver

def Webserver::start
  app = Rack::Builder.app do

    map "/" do
      run Webserver::GC29Tester
    end

    map "/gv" do
      run GraphViewerServer
    end

  end

  
  Rack::Handler.get('webrick').run(app, :Host=>'0.0.0.0', :Port=>config(:WebServerPort) || 8080) do |server|
    # trap(:INT) { server.stop }
  end

end

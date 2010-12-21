#!/usr/bin/env ruby
# $Id$

# GET /data.csv => (xhr? ? CSV data for amcharts : CSV data for download)
# GET /chart/*
# 	displays amline chart
# GET /amline_settings.xml
# 	return XML for amcharts
# 	data comes from /data.csv
# GET /dir/*
# GET /dualchart/*
#
#
# NOTE: if you use Rackup's map command:
#     request.path_info has post-map part
#     request.script_name has pre-map part

require 'rubygems'
require 'cgi'
require 'find'
require 'set'
require 'pp'
require 'utils'
require 'config'

$webroot ||= config(:WebRootDirectory)
$webroot ||= File.expand_path(File.join(File.dirname(__FILE__), '../webserver'))

BEGIN {
  $gvroot = File.expand_path(File.join($webroot, 'graph_viewer'))
}

require 'graphviewer'
require 'sinatra/base'

$guide = ::GraphViewer::Guide.new("treatment", config(:TreatmentWindow))

class GraphViewerServer < Sinatra::Base
  TempChannels = %w(loadedTipTemperature t2Temperature calTip GC29Tip T1 T3 Tip filteredLoadedTipTemperature)
  RightChannels = %w(power)

  set :root, $gvroot
  enable :logging, :static
  disable :run
  $stderr.sync= true

  helpers do

    def getFilename
      filename = File.expand_path(([""] + params[:splat]).join('/'))
      filename.sub(/^([^\/])/, '/\\1')
    end

    def getFile(filename = getFilename())
      file = ::GraphViewer::CSVFile.runNamed(filename)
      error 500, "<pre>can't read #{filename.inspect};" +
        " seen files:\n" +
        ::GraphViewer::CSVFile.runs.keys.join("\n") +
        "</pre>" unless file
      file.selectFields(TempChannels + RightChannels) if file.headers.any? { |h| TempChannels.include? h }
      file.selectedGraphs.each { |g| g.axis = 'right' if RightChannels.include? g.name  }
      file
    end

    def getData(filename = getFilename())
      file = getFile(filename)
      last_modified(file.mtime) if file.mtime
      file.csvData
    end

    # prepend new since
    def getNewData(since, filename = getFilename())
      file = getFile(filename)
      newData = file.getNewData(since)
      if newData
        newSince = file.lastFullLineTime.to_i
        newSince.to_s + "\n" + file.csvData(newData)
      else
        file.mtime
      end
    end

    def mtimeString(filename = getFilename())
      file = getFile(filename)
      return 'nil' if file.nil?
      file.mtime.to_f
    end

    # return array of dirnames sorted by recentness
    def csvDirsBelow(dirname)
      dirs = Hash.new { |h,k| h[k] = [] }
      Find.find(dirname) do |path|
        if File.directory?(path)
          Find.prune if path =~ %r(/.svn$)
        elsif path =~ /.csv$/
          dirs[File.dirname(path)] << File.mtime(path)
        end
      end
      now = Time.now
      dirs.keys.sort_by { |k| now - dirs[k].sort[-1] }
    end

    # return array of [file, mtime]
    def csvFilesBelow(dirname)
      return nil unless File.directory? dirname
      files = []
      csvDirsBelow(dirname).each do |path|
        Dir.glob(File.join(path, '*.csv')).each do |csvfile|
          files << [csvfile, File.mtime(csvfile)]
        end
      end
      now = Time.now
      files.sort_by { |a| now - a[1] }
    end

  end

  get '/amline_settings.xml/*' do
    file = getFile
    last_modified(file.mtime) if file.mtime
    # reload, graphs, guides
    content_type 'application/xml'
    erb :amline_settings, :layout => false, :locals => {
      :reload => (params[:reload] || 0),
      :graphs => file.selectedGraphs,
      :filename => getFilename(),
      :guides => [$guide] }
  end

  # return the data for all the displayed graphs
  # for the amchart module
  get '/data/*' do
    since =
      if params['since']
        Time.at(params['since'].to_f)
      elsif params['latest']
        getFile().lastFullLineTime
      end

    wait = (params['wait'] || 1.0).to_f

    if since
      response['Cache-Control'] = 'no-cache'
      sleep(wait)
      newData = getNewData(since)
      halt 304, "No new data" if newData.empty?
      newData
    else
      getData
    end
  end

  # return the data for all the displayed graphs
  # for download
  get '/data.csv/*' do
    attachment
    getData
  end

  get '/amcharts_key.txt' do
    last_modified(Time.at(0))
    ''
  end

  get '/chart/*' do
    file = getFile
    last_modified(file.mtime) if file.mtime
    erb(:chart, :locals => { :chartid => '', :heightpct => 70, :filename => getFilename(), :follow => params[:follow], :more => file.pos, :since => file.mtime.to_i, :wait => params[:wait], :pattern => params[:pattern] })
  end

  get '/dualchart/*' do
    file = getFile
    last_modified(file.mtime) if file.mtime
    erb(:dualchart, :locals => { :filename => getFilename(), :follow => false })
  end

  get '/dir/*' do
    dirname = getFilename
    files = []
    Dir.glob(dirname).each do |dn|
      if File.directory?(dn)
        files.concat(csvFilesBelow(dn))
      else
        if File.readable_real?(dn)
          files << [dn, File.mtime(dn)]
        end
      end
    end
    error unless files
    if params[:pattern]
      pattern = Regexp.new(params[:pattern])
      files = files.select { |fa| pattern.match(fa[0]) }
    end
    erb(:dir, :locals => { :dirname => dirname, :files => files, :pattern => params[:pattern] })
  end

  get '/refresh/chart/*' do
    file = getFilename
    run = ::GraphViewer::CSVFile.refreshRunNamed(file)
$stderr.puts("refreshing #{file} => #{run.name}")
    redirect "#{ request.script_name }/chart/#{ run.name.sub(/ run (\d+)$/, "%20run%20\\1") }"
  end

end # class GraphViewerServer

# vim: ai

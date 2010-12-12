# $Id$

require 'csvProcessor'
require 'cgi'
require 'time'

module GraphViewer
  class CSVFile
    # "<filename> run ##" => CSVFile
    @runs = {}

    def self.runs
      @runs
    end

    def self.runNames
      @runs.keys.sort_by { |f| (f =~ /run (\d+)$/) ? $1.to_i : 0 }
    end

    def self.latestRunNamedLike(_name)
      pattern = Regexp.new(_name + ' run \d+$')
      latestName = runNames.reverse.find { |nm| pattern.match(nm) }
      @runs[latestName]
    end

    def self.validFileNameFrom(_name)
      basename = _name.sub(/ run \d+$/, '')
      File.readable_real?(basename) ? basename : nil
    end

    def self.runNamed(_name)
      @runs.fetch(_name) do |k|
        fn = validFileNameFrom(k)
        return nil unless fn
        readFile(fn)
        @runs.fetch(_name) { |k| latestRunNamedLike(fn) }
      end
    end

    def self.forgetRunNamed(_name)
      @runs.delete(_name)
    end

    def self.refreshRunNamed(_name)
      run = runNamed(_name)
      return nil unless run
      run.getNewData
      run
    end

    def self.readFile(_name)
      begin
        mtime = File.mtime(_name)
        startTime = Time.now
        File.open(_name) do |f|
          allData = f.read_csv do |rec|
            if rec.size == 1 && rec[0] =~ /^#/
              nil
            else
              rec
            end
          end
          i = 0
          lastFile = nil
          dut = nil
          timestamp = nil
          allData.each_chunk do |chunk|
            next if chunk.empty?
            serialNumber = nil
            runname = "#{_name} run #{i + 1}"
            headers = chunk.shift
            nfields = headers.size
            if nfields <= 2 && chunk.size < 2 # run header
              timestamp = Time.parse(headers[1])
              timestamp = nil if (timestamp - Time.now).abs < 1
              if headers[0] =~ /#\s*(\S*)-([A-Z0-9]+\d)\s*$/
                serialNumber = $1
                dut = $2
              elsif headers[0] =~ /#\s*([^-]+)\s*$/
                serialNumber = $1
                dut = 'DUT?'
              else
                $stderr.puts [ "unrecognized data around line #{lines - chunk.size}", headers ].inspect
              end
              next
            end
            next if chunk.empty?
            i += 1
            newFile = self.new(runname, headers)
            newFile.useData(chunk)
            newFile.createGraphs
            newFile.mtime= mtime
            newFile.originalFilename= _name
            newFile.timestamp = timestamp || mtime
            newFile.dut = dut
            lastFile = newFile
            @runs[runname] = newFile
          end
          if lastFile
            lastFile.pos = f.pos
          end
        end
      rescue
        nil
      end
    end

    def initialize(_name, _headers = [])
      @name = _name
      @headers = _headers
      @selectedFields = (0 .. (_headers.size - 1)).to_a
      @data = nil
      @xname = nil
      @graphs = {}
      @mtime = nil
      @rounding = '%.2f'
      @minima = Array.new(_headers.size, Float::MAX)
      @maxima = Array.new(_headers.size, Float::MIN)
      @originalFilename = nil
      @pos = nil  # position just after last full line read/returned
      # array of [@pos, Time] values
      @positions = []
      @timestamp = nil
      @dut = nil
    end

    attr_reader :name, :headers, :selectedFields, :comments, :graphs, :rounding
    attr_reader :minima, :maxima, :data, :pos
    attr_accessor :mtime, :originalFilename
    attr_accessor :timestamp, :dut

    def pos=(p, m = @mtime)
      @pos = p
      @mtime = m
      lastpos = @positions.last
      if lastpos.nil? || lastpos[0] < p
        @positions << [p, m]
      else
      end
    end

    def positionAt(time)
      pa = @positions.reverse.find { |p| time >= p[1] }
      return nil if pa.nil?
      pa[0]
    end

    def lastFullLineTime
      lastpos = @positions.last
      return nil if lastpos.nil?
      lastpos[1]
    end

    # assuming headers is set but data is not...
    def useData(data)
      @data = data.collect { |row| round(row) }
    end
    
    def round(fields)
      retval = []
      fields.each_with_index  do |f,i|
        if Numeric === f
          f = f.to_f
          @minima[i] = f if f < @minima[i]
          @maxima[i] = f if f > @maxima[i]
          retval << @rounding % f
        else
          retval << f
        end
      end
      retval
    end

    def createGraphs
      @selectedFields = []
      @headers.each_with_index do |h,i|
        unless i.zero?
          @graphs[h] = g = Graph.new(self, h, i)
          g.minval = @minima[i]
          g.maxval = @maxima[i]
        end
        @selectedFields << i
      end
    end

    def selectFields(selection = @headers)
      oldFields = @selectedFields
      @selectedFields = []
      @headers.each_with_index { |h,i| @selectedFields << i if i.zero? || selection.include?(h) }
      @mtime = Time.now if oldFields != @selectedFields
    end

    # Return a string with CSV representation of the given data records
    def csvData(_data = data)
      return '' unless _data
      io = StringIO.new
      _data.each do |a|
        io << a.values_at(*selectedFields).join(',') << "\n"
      end
      io.string
    end

    def selectedHeaders
      @headers.values_at(*selectedFields)
    end

    def selectedGraphs
      @graphs.values_at(*selectedHeaders).compact
    end

    # If there has been new data, return a seek position, else false
    def hasNewData(since = lastFullLineTime())
      return false if since.nil?
      whence = positionAt(since)
      return false if whence.nil?
      return whence if pos > whence
      return whence if mtime > since
      return whence if File.mtime(@originalFilename) > mtime
      false
    end

    # If there has been new data, return an Array, else nil
    def getNewData(since = lastFullLineTime())
      whence = hasNewData(since)
      return nil unless whence
      begin
        File.open(@originalFilename) do |f|
          newData = nil
          f.seek(whence, IO::SEEK_SET)
          newData = f.read_csv
          if newData && !newData.empty?
            newData.delete_if { |rec| rec.size == 1 && rec[0] =~ /^#/ }
            @data += newData.collect { |row| round(row) }
            @mtime = f.mtime
            self.pos= f.pos
          end
          newData
        end
      rescue
        @pos = 0
        @mtime = nil
        nil
      end
    end
  end

  class Graph
    def initialize(_file, _fieldname, _fieldnumber)
      @file = _file
      @name = _fieldname
      @fieldnumber = _fieldnumber
      @axis = 'left'
      @maxval = Float::MIN
      @minval = Float::MAX
    end
    attr_reader :name, :file, :fieldnumber
    attr_accessor :maxval, :minval, :axis
  end

  class Guide
    def initialize(_name, _range)
      @name = _name
      @range = _range
    end
    attr_reader :name, :range
  end

end


# $Id$

require 'time'

class Array
  def self.from_csv(str, sep=',')
    str.chomp.split(sep).collect { |s| s.csv_to_object }
  end

  # call the given block with each piece of myself where the number of fields match.
  def each_chunk
    return if empty?
    nfields = self[0].size
    chunk = []
    each do |rec|
      rsize = rec.size
      if rsize == nfields
        chunk << rec
      else
        yield chunk if block_given?
        chunk = [ rec ]
        nfields = rsize
      end
    end
    yield chunk if block_given?
  end
end

class String
  def csv_to_object
    case self
      when /^-?(?:[0-9]+\.)?[0-9]+(?:[efgEFG][+-]?[0-9]+)?$/
        self.to_f
      when /^"(.*)"$/
        $1.gsub(/\\"/, '"')
      when "true", "TRUE"
        true
      when "nil", "NIL", "NULL"
        nil
      when "false", "FALSE"
        false
#      when /^(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun) /
#        Time.parse(self) rescue self
      else
        self
    end
  end
end

class IO
  # enumerate over each csv record
  # leave file positioned at end of last full line
  def each_csv_record(sep=',')
    l = nil
    begin
      while l = readline
        if l.end_with?($/)
          yield Array.from_csv(l,sep) if block_given?
        else
          seek(- l.size, IO:: SEEK_CUR)
          return
        end
      end
    rescue EOFError
    end
  end
  # Return an array with the converted contents of the file
  # If an optional block is given, allow pre-processing of each record through it.
  def read_csv(sep=',')
    records = []
    each_csv_record(sep) do |rec|
      if block_given?
        rec = yield(rec)
      end
      records << rec unless rec.nil?
    end
    records
  end
end

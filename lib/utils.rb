# $Id$
# Date and Time conversion routines

require 'date'
require 'time'

class Time
  # Convert a Time object to a DateTime (from Ruby Cookbook):
  alias_method(:old_to_datetime, :to_datetime)

  def to_datetime
    # Convert seconds + microseconds into a fractional number of seconds
    seconds = sec + Rational(usec, 10**6)

    # Convert a UTC offset measured in minutes to one measured in a
    # fraction of a day.
    offset = Rational(utc_offset, 60 * 60 * 24)
    DateTime.new(year, month, day, hour, min, seconds, offset)
  end

  # Return the time in seconds required to run the given block
  def self.toRun
    started = Time.now
    retval = yield if block_given?
    ended = Time.now
    [ended - started, retval]
  end
end

class Date
  def to_gm_time
    to_time(new_offset, :gm)
  end

  def to_local_time
    to_time(new_offset(DateTime.now.offset-offset), :local)
  end

  private
  def to_time(dest, method)
    #Convert a fraction of a day to a number of microseconds
    usec = (dest.sec_fraction * 60 * 60 * 24 * (10**6)).to_i
    Time.send(method, dest.year, dest.month, dest.day, dest.hour, dest.min,
              dest.sec, usec)
  end
end

class Numeric
  def to_degC
    (self-32.0).to_deltaC
  end
  def to_degF
    self.to_deltaF + 32.0
  end
  def to_deltaC
    ((self * 5.0) / 9.0)
  end
  def to_deltaF
    ((self * 9.0) / 5.0)
  end
end

class Array
  # takes array of 2-element pairs; returns a hash
  def to_hash
    h = {}
    map { |a| h.store(*a) }
    h
  end
end

# Shut up Sinatra/Rack warnings on missing methods if in debugger
if $DEBUG
  class Object
    def extensions
      []
    end
  end
end

def timestamp
  now = Time.now
  now.strftime "%T.#{'%03d' % (now.usec / 1000) }"
end

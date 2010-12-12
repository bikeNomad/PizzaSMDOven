# $Id$
#
# Repeat a block at a fixed rate; report if it's impossible to do so
#

class TimedRepeat
  class MissedRepeat < Exception
    def initialize(_repeater, _rep, _lateBy)
      @repeater = _repeater
      @rep = _rep
      @lateBy = _lateBy
    end

    attr_reader :repeater, :rep, :lateBy

    def inspect
      "#<#{ self.class.name } repeater=#{@repeater.inspect} rep=#{@rep} lateBy=#{@lateBy}>"
    end
  end

  class StopRepeat < Exception
  end
end

class TimedRepeat
  include Enumerable

private
  InitialDelay = 0.001
  AllowableLateness = 0.001

  def nextRep
    @rep += 1
    @lastTime = @nextTime
    @nextTime = @start + @period * @rep
  end

public
  @@allowableLateness = AllowableLateness
  @@initialDelay = InitialDelay

  def self.stop
    raise TimedRepeat::StopRepeat
  end

  # one way to stop from within a loop
  # Also can use TimedRepeat.stop
  def stop
    self.class.stop
  end

  def reset
    @rep = 0
    @nextTime = @start = @lastTime = Time.now + InitialDelay
  end

  def timeSinceReset
    Time.now - @start
  end

  def timeSinceLast
    Time.now - @lastTime
  end

  def timeTillNext
    @nextTime - Time.now
  end

  # a possible response to a missed repeat
  # returns the repetitions that were skipped to catch up
  def catchUp
    oldLastTime = @lastTime
    now = Time.now
    skipped = []
    while now > @nextTime 
      skipped << @rep
      nextRep
    end
    @lastTime = oldLastTime 
    skipped
  end

  def inspect
    "#<#{ self.class.name } period=#{@period} initialDelay=#{@initialDelay} allowableLateness=#{@allowableLateness}>"
  end

  def initialize(_period, _allowableLateness = @@allowableLateness, _initialDelay = @@initialDelay)
    @period = _period.to_f
    @allowableLateness = _allowableLateness
    @initialDelay = _initialDelay
    reset
  end

  attr_reader :period, :rep, :start, :nextTime, :lastTime, :initialDelay
  attr_accessor :allowableLateness

  def each
    loop do
      # wait until next time
      now = Time.now
      sleepyTime = @nextTime - now
      if sleepyTime > 0
        sleep(sleepyTime)
      elsif sleepyTime < - @allowableLateness
        raise MissedRepeat.new(self, @rep, - sleepyTime)
      end
      yield @rep if block_given?
      nextRep
    end
  end
  
  # Repeat the given block until an exception or until stop is called
  # The block is passed the TimedRepeat instance
  # Returns the missed log when stopped.
  def self.repeatAt(_period, _allowableLateness=@@allowableLateness, _initialDelay=@@initialDelay)
    t = self.new(_period, _allowableLateness, _initialDelay)
    missed = []
    begin
      t.each do |rep|
        yield(t) if block_given?
      end
    rescue TimedRepeat::StopRepeat
      missed
    rescue TimedRepeat::MissedRepeat
      missed << $!
      t.catchUp
      retry
    end
  end

end

# test program
if __FILE__ == $0
  period = 0.2
  allowableLateness = 0.1
  done = []
  missed = TimedRepeat.repeatAt(period, allowableLateness) do |t|
    done << [t.rep, t.timeSinceReset, t.timeSinceLast, t.timeTillNext]
    case t.rep
    when 10
      t.stop
    when 3
      sleep(period + 0.05)
    when 6
      sleep(period * 2)
    end
  end
  puts "period=#{period}, allowableLateness=#{allowableLateness}"
  puts "Missed:"
  p missed
  puts "Done:"
  puts "rep timeSinceReset timeSinceLast timeTillNext"
  done.each { |d|  printf "%3d  %13.2f %13.2f %12.3f\n", *d }
end

# $Id$
# Mix-in for adding an updating thread and its control.

require 'timedRepeat'
require 'pp'

module Updating
public
  class Done < ::Exception
  end
  class Report < ::Exception
    def initialize(_log)
      @log = _log
    end
    attr_reader :log
  end

private
  def statusReportLabel
    respond_to?(:name) ? name : inspect
  end

  def statusReport(exc)
    exc.log.puts('===', "#{statusReportLabel} totalUpdates=#{totalUpdates} missedUpdates=#{missedUpdates.size}", '===')
  end

  # Start an update thread that will call the given block
  # at the desired period.
  def updater(period)
    repeater = TimedRepeat.new(period)
    @missedUpdates = []
    begin
      repeater.each do |rep|
        Thread.pass
        yield(rep, repeater.timeSinceReset, repeater.timeSinceLast) if block_given?
        @totalUpdates += 1
      end
    rescue Report
      statusReport($!)
      retry
    rescue TimedRepeat::MissedRepeat
      @missedUpdates << [ $! ]
      repeater.catchUp
      retry
    rescue Updating::Done
      @debugLog.puts "done signaled" if @debugLog
      true
    rescue Exception, StandardError
      logException($!)
      false
    end
  end

public
  attr_accessor :missedUpdates, :totalUpdates
  attr_reader :updateThread

  def initialize_updating
    @updateThread = nil
    @missedUpdates = []
    @totalUpdates = 0
  end

  def startUpdateThread(period, *args)
    endUpdateThread if @updateThread
    @totalUpdates = 0
    @updateThread = MonitoredThread.new(statusReportLabel, *args) do |*args|
      updater(period) do |rep,timeSinceReset,timeSinceLast|
        yield(rep,timeSinceReset,timeSinceLast,*args) if block_given?
        Thread.pass
      end
      @debugLog.puts("updater done") if @debugLog
    end
    Thread.pass
    @updateThread
  end

  # End the update thread, if any.
  # Do so gracefully, letting the thread clean up after itself first.
  def endUpdateThread(stuff=nil)
    begin
      return unless @updateThread
      @updateThread.raise(Updating::Done.new(stuff))
      @updateThread.join
      @updateThread = nil
    rescue
    end
  end

  def printStatusReport(_log=$stderr)
    return unless @updateThread
    @updateThread.raise(Updating::Report.new(_log))
  end

end

class Thread
  alias :orig_inspect :inspect
  def to_s
    "#<#{self[:name]}>#{orig_inspect}"
  end
end

# test program
if __FILE__ == $0

  class TestClass
    include Updating
  end

  t = TestClass.new
  t.startUpdateThread(1.0, 'a', 'b') do |rep,timeSinceReset,timeSinceLast,*args|
    $stderr.puts [ rep, timeSinceReset, timeSinceLast, args ].inspect
  end
  t2 = TestClass.new
  t2.startUpdateThread(1.0, 'c', 'd') do |rep,timeSinceReset,timeSinceLast,*args|
    $stderr.puts [ rep, timeSinceReset, timeSinceLast, args ].inspect
  end

  sleep(10.0)
  t.endUpdateThread
  t2.endUpdateThread
  pp t.missedUpdates
  pp t2.missedUpdates

end

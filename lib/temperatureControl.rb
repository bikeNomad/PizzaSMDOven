# $Id$
# Temperature controller that uses windowed PID and feedforward
require 'pid'

# sampling period = 0.2 sec
# sampling rate = 5 / sec
# kP = 50.0
# kI =  20.0 (20.0 * 0.2 = 4.0)
# kD = 100.0 (100.0 / 0.2 = 500.0)
#
# kP = 50.0
# tD = kD / kP = 2.0
# tI = kP / kI = 2.5

class FeedForwardTemperatureController

  def initialize(_pid, _feedForward, _window = nil)
    @pid = _pid
    @window = _window
    @feedForward = _feedForward
    @outOfWindowOutputs = [0.0, 100.0]
    @lastPidOutput = 0.0
  end

  attr_accessor :window, :outOfWindowOutputs, :feedForward
  attr_reader :pid

  def update(_error, _actual, _samplePeriod)
    if @window
      if _error > @window
        return @outOfWindowOutputs[1]
      elsif _error < - @window
        return @outOfWindowOutputs[0]
      end
    end
    @lastPidOutput = pid.update(_error, _actual, _samplePeriod)
    @lastPidOutput + feedForward
  end

  def reset(actual)
    pid.reset(actual)
    @lastPidOutput = 0.0
  end

end

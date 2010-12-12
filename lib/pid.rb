#!/usr/bin/env ruby
# $Id$
# Implementation of PID control algorithm
#
# standard form:
# kP * (error + 1/tI * integral(error) + tD * de/dt)
# tI = integral time
# tD = derivative time
#
# parallel form:
# kP * error + kI * integral(error) + kD * de/dt
# in terms of std form:
# kI = kP/tI
# kD = kP*tD
# tI = kP/kI
# tD = kD/kP

class PID
  def initialize(kp = 1.0, ti = 0.0, td = 0.0, ilimpos=nil, ilimneg=nil)
    @kP = kp.to_f
    @tI = ti.to_f
    @tD = td.to_f
    @integrator = 0.0
    @lastActual = nil
    @lastError = nil
    @lastOutput = 0.0
    @iLimits = [nil, nil]
    setILimits()
    # for debugging
    @pTerm = 0.0
    @iTerm = 0.0
    @dTerm = 0.0
  end

  attr_accessor :kP, :tD, :integrator, :iLimits
  attr_reader :lastActual, :lastError, :lastOutput
  attr_reader :pTerm, :iTerm, :dTerm, :tI

  def tI=(ti)
    @tI = ti.to_f
    setILimits
  end

  def setILimits(ilimpos=nil, ilimneg=nil)
    kI = kP / tI
    if kI > 0.0
      @iLimits[1] = (ilimpos || (100.0 / kI))
      @iLimits[0] = (ilimneg || -@iLimits[1])
    end
  end

  def reset(actual)
    @integrator = 0.0
    @lastActual = nil
    @lastError = @lastOutput = 0.0
    @pTerm = @iTerm = @dTerm = 0.0
  end

if false
  def inspect
    "#<PID lastErr=#{@lastError} lastActual=#{@lastActual} integ=#{@integrator} lastOut=#{@lastOutput}>"
  end
end

  # returns sum of PID terms
  # error=commanded-actual
  # sPeriod=time since last update
  def update(error, actual, sPeriod)
    sum = 0.0

    # P
    sum = @pTerm = error

    # I
    unless @tI.zero?
      # update integrator
      @integrator += error * sPeriod

      # apply limits to magnitude of integrator to avoid excessive wind-up
      if @iLimits[0] && (@integrator < @iLimits[0])
        @integrator = @iLimits[0]
      elsif @iLimits[1] && (@integrator > @iLimits[1])
        @integrator = @iLimits[1]
      end

      # divide (limited) integrator by tI
      # and add to sum
      @iTerm = @integrator / @tI
      sum += @iTerm
    end

    # D
    # NOTE using the derivative of actual vs. error.
    # This usually gives better stability and recovery time
    # with respect to changes in the setpoint.
    # Note also that since
    #    error = SP (setpoint) - PV (actual)
    # an increase in actual represents a *decrease* in error.
    # So de/dt will be negative when d(PV)/dt is positive.
    unless @tD.zero?
      if @lastActual.nil?
        @dTerm = 0.0
      else
        @dTerm = @tD * (@lastActual - actual) / sPeriod
        sum += @dTerm
      end
    end

    @lastError = error
    @lastActual = actual
    @lastOutput = sum * @kP # return value
  end

end

# test program
if __FILE__ == $0
  pid = PID.new(8.0, 0.125, 25.6)
  100.times do |i|
    out = pid.update(1, 20)
    p pid
    p out
  end
end

# error = command - actual

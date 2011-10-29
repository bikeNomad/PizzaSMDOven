# $Id$

## standard Ruby modules

require 'pp'
require 'forwardable'
require 'enumerator'

## external packages

# gem install serialport
require 'serialport'

# gem install rmodbus
require 'rmodbus'

## my code
# require 'rmodbus_fixes'

require 'timedRepeat'
require 'solo'

class SMDOven
  include SOLO
  extend Forwardable

  def initialize(_profile,
                 _portname,
                 _dataRate = self.class.defaultDataRate,
                 _slaveAddress = self.class.defaultSlaveAddress,
                 _opts = self.class.defaultSerialOptions)
    @client = TemperatureControllerClient.new(_portname, _dataRate, _opts)
    @slaveAddress = _slaveAddress
    @slave = @client.with_slave(_slaveAddress)
    @opts = _opts
    @temperatureLog = nil
    @temperatureLogOpened = nil
    @statusLog = $stderr
  end

  attr_reader :client, :slave, :temperatureLog
  attr_accessor :statusLog, :temperatureLogOpened, :slaveAddress

  def openTemperatureLog(file,headers=false)
    @temperatureLog.close if @temperatureLog
    @temperatureLog = file
    if @temperatureLog.nil?
      @temperatureLogOpened = nil
      return
    end
    logTemperatureHeaders if headers
    @temperatureLogOpened = Time.now
  end

  # delegate all SOLO register accessors to slave
  def_delegators(*(([:@slave] + RO_DATA_REGISTERS.keys.map(&:to_sym)).flatten))
  def_delegators(*(([:@slave] + RW_MULTI_PER_RS_PATTERN.keys.map(&:to_sym)).flatten))
  def_delegators(*(([:@slave] + RW_MULTI_PER_RS_STEP.keys.map(&:to_sym)).flatten))
  def_delegators(*(([:@slave] + RW_DATA_REGISTERS.keys.map { |k| [k, "#{k}="] }).flatten))
  def_delegators(*(([:@slave] + RW_BIT_REGISTERS.keys.map { |k| [k, "#{k}="] }).flatten))

  # delegate some other SOLO methods to client
  def_delegators(:@client,:debug,:debug=,:profile,:receive_pdu,:transmit_pdu,:debug_log=,:debug_log)
  def_delegators(:@client,:initial_response_timeout,:initial_response_timeout=)
  def_delegators(:@client,:inter_character_timeout,:inter_frame_timeout,:inter_character_timeout=,:inter_frame_timeout=)

  def processValue
    pv = slave.processValue
    while pv.nil?
      statusLog.puts("PV nil; retrying") if statusLog
      pv = slave.processValue
    end
    pv
  end

  def setpointValue
    sv = slave.setpointValue
    while sv.nil?
      statusLog.puts("SV nil; retrying") if statusLog
      sv = slave.setpointValue
    end
    sv
  end

  def goToTemperature(_temp, _epsilon=1.0)
    statusLog.puts("waiting for temperature to go within #{_epsilon} degC of #{_temp}") if statusLog
    slave.setpointValue= _temp
    while (processValue - _temp).abs > _epsilon
      logTemperature()
      sleep 1.0
    end
  end

  def waitForProfile
    while rampSoakControlStatus == 1
      logTemperature()
      sleep 1.0
    end
  end

  # wait until the temperature drops below _temp
  def goBelowTemperature(_temp)
    statusLog.puts("waiting for temperature to go below #{_temp}") if statusLog
    while processValue > _temp
      logTemperature()
      sleep 1.0
    end
  end

  # attempt to re-init the serial port after an error
  def reset
    statusLog.puts("attempting to reset client") if statusLog
    client.close
    sleep(5)
    @client = TemperatureControllerClient.new(client.port, client.baud, @opts)
    @slave = @client.with_slave(@slaveAddress)
  end

  def logTemperatureHeaders
    return if temperatureLog.nil?
    temperatureLog.puts("time,setpoint,process,output1,output2")
  end

  def logTemperature
    return if temperatureLog.nil?
    pv = processValue
    sv = setpointValue
    # timestamp = Time.now.strftime("%H:%M:%S")
    timestamp = (Time.now - temperatureLogOpened).to_s
    temperatureLog.printf("%s,%.1f,%.1f,%.1f,%.1f\n", timestamp, sv, pv, output1Level, output2Level)
    temperatureLog.fsync
  end

  def ramp(_from,_to,_time)
    temp = _from
    begin
      TimedRepeat.repeatAt(self.class.defaultSamplingPeriod, self.class.defaultAllowableLateness) do |t|
        if t.timeSinceReset >= _time
          t.stop
        end
        tdelta = t.timeSinceLast
        temp = _from + (_to-_from) * t.timeSinceReset / _time
        slave.setpointValue= temp
        logTemperature()
      end
    rescue TimedRepeat::MissedRepeat
      retry
    end
  end

  # profile is array of [temperature,time] values
  def doProfile(_profile,_startTemp=processValue)
    statusLog.puts(_profile.pretty_print_inspect) if statusLog
    startTemp = _startTemp
    _profile.each_with_index do |step,i|
      statusLog.puts "#{i} #{startTemp} => #{step[0]} over #{step[1]} secs" if statusLog
      endTemp = step[0]
      stepTime = step[1]
      ramp(startTemp, endTemp, stepTime)
      statusLog.puts "  waiting for temp to go from #{processValue} to #{endTemp}" if statusLog
      goToTemperature(endTemp)
      startTemp = endTemp
    end
  end

  # profile is array of [temperature,time] values
  def setPatternToProfile(_pattern,_profile,_startTemp=processValue)
    statusLog.puts("setting pattern #{_pattern} to #{_profile.pretty_print_inspect}") if statusLog
    values = _profile.map { |s| s[0] }
    rampSoakSetpointValues(_pattern, values)
    times = _profile.map { |s| [s[1], 60].max }
    rampSoakTimes(_pattern, times)
    nextPatternNumber(_pattern, NO_NEXT_PATTERN)
    startingRampSoakPattern= _pattern
    lastStepNumber(_pattern, _profile.size - 1)
    additionalCycles(_pattern, 0)
  end

  # dump contents of my registers to logfile
  def dumpRegisters(logfile=statusLog)
    return if logfile.nil?
    pidParameters = %w(targetSetpointValue proportionalBand integralTime derivativeTime integralOffset)

    cm = controlMode
    ppg = pidParameterGroup
    controlMode = CM_PID
    logfile.puts("pidParameterGroup = #{ppg}")
    logfile.puts("pidParameterGroup   " + pidParameters.join("  "))
    4.times do |g|
      pidParameterGroup= g
      vals = [pidParameterGroup] + pidParameters.collect { |p| self.send(p) }
      logfile.printf("%17s  %20s  %16s  %12s  %14s  %14s\n", *vals)
    end
    controlMode = controlMode
    pidParameterGroup= ppg

    (RO_DATA_REGISTERS.keys + RW_DATA_REGISTERS.keys + RW_BIT_REGISTERS.keys - pidParameters).sort.each { |k| logfile.puts "#{k} = #{self.send(k)}" }

    8.times do |n|
      logfile.puts("\npattern #{n}\n")
      lsn = lastStepNumber(n)
      RW_MULTI_PER_RS_STEP.keys.sort.each { |k| logfile.puts "#{k}[#{n}] = #{self.send(k,n).slice(0 .. lsn).inspect}" }
      RW_MULTI_PER_RS_PATTERN.keys.sort.each { |k| logfile.puts "#{k}[#{n}] = #{self.send(k,n).inspect}" }
    end

  end

  def dumpPDUs(logfile=statusLog)
    return if logfile.nil?
    logfile.printf("XMIT: %s\n", logging_bytes(client.transmit_pdu))
    logfile.printf("RCV: %s\n", logging_bytes(client.receive_pdu))
  end

  ### class-side configuration (as class instance variables)

  # for TimedRepeat
  @defaultSamplingPeriod = 1
  @defaultAllowableLateness = 0.3

  # RS-485 defaults for SOLO temperature controllers:
  @defaultDataRate = 9600
  @defaultSlaveAddress = 1
  @defaultSerialOptions = {
    :data_bits => 8,
    :stop_bits => 1,
    :parity => SerialPort::EVEN,
    # read_timeout is in msec, and is used by SerialPort instance
    :read_timeout => (1000.0 * (8 + 1 + 1) / @defaultDataRate).round.to_i
  }

  # define class-side accessors for class instance variables

  class << self
    attr_accessor :defaultSamplingPeriod, :defaultAllowableLateness,
      :defaultDataRate, :defaultSerialOptions, :defaultSlaveAddress
  end

end

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
require 'rmodbus_fixes'

require 'timedRepeat'
require 'solo'

class SMDOven
  include SOLO
  include ModBus::Common
  extend Forwardable

  def initialize(_profile,
                 _portname,
                 _dataRate = self.class.defaultDataRate,
                 _slaveAddress = self.class.defaultSlaveAddress,
                 _opts = self.class.defaultSerialOptions)
    @client = TemperatureControllerClient.new(_portname, _dataRate, _slaveAddress, _opts)
    @portname = _portname
    @opts = _opts
    @temperatureLog = nil
    @statusLog = $stderr
  end

  attr_reader :client, :portname, :temperatureLog
  attr_accessor :statusLog

  def temperatureLog=(file)
    @temperatureLog.close if @temperatureLog
    @temperatureLog = file
    return if @temperatureLog.nil?
    @temperatureLog.puts("time,setpoint,process")
  end

  # delegate all SOLO register accessors to client
  def_delegators(*(([:@client] + RO_DATA_REGISTERS.keys.map(&:to_sym)).flatten))
  def_delegators(*([:@client] + RW_DATA_REGISTERS.keys.grep(/s*0$/).map { |s| s.sub(/s*0$/, "s").to_sym }.flatten))
  def_delegators(*([:@client] + RW_DATA_REGISTERS.keys.map { |k| [k, "#{k}="] }.flatten))

  # delegate some other SOLO methods to client
  def_delegators(:@client,:debug,:debug=,:profile,:runMode,:receive_pdu,:transmit_pdu,:debug_log=,:debug_log)
  def_delegators(:@client,:initial_response_timeout,:initial_response_timeout=)
  def_delegators(:@client,:inter_character_timeout,:inter_frame_timeout,:inter_character_timeout=,:inter_frame_timeout=)

  def processValue
    pv = client.processValue
    while pv.nil?
      statusLog.puts("PV nil; retrying") if statusLog
      pv = client.processValue
    end
    pv
  end

  def setpointValue
    sv = client.setpointValue
    while sv.nil?
      statusLog.puts("SV nil; retrying") if statusLog
      sv = client.setpointValue
    end
    sv
  end

  def goToTemperature(_temp, _epsilon=1.0)
    statusLog.puts("waiting for temperature to go within #{_epsilon} degC of #{_temp}") if statusLog
    client.setpointValue= _temp
    while (processValue - _temp).abs > _epsilon
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
    @client = TemperatureControllerClient.new(@portname, client.baud, client.slave, @opts)
  end

  def logTemperature
    return if temperatureLog.nil?
    pv = processValue
    sv = setpointValue
    temperatureLog.printf("%s,%.1f,%.1f\n", Time.now.strftime("%H:%M:%S"), sv, pv)
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
        client.setpointValue= temp
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

  # dump contents of my registers to logfile
  def dumpRegisters(logfile=statusLog)
    return if logfile.nil?
    (RO_DATA_REGISTERS.keys + RW_DATA_REGISTERS.keys).sort.each { |k| logfile.puts "#{k} = #{self.send(k)}" }
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

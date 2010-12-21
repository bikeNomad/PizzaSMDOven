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
  extend Forwardable

  def initialize(_profile,
                 _portname,
                 _dataRate = class.defaultDataRate,
                 _slaveAddress = class.defaultSlaveAddress,
                 _opts = class.defaultSerialOptions)
    @client = TemperatureControllerClient.new(_portname, _dataRate, _slaveAddress, _opts)
    @portname = _portname
    @opts = _opts
    @temperatureLog = nil
  end

  attr_reader :client, :portname
  attr_accessor :temperatureLog

  def goToTemperature(_temp, _epsilon=1.0)
    @client.setpointValue= _temp
    while (processValue() - _temp).abs > _epsilon
      logTemperature()
      sleep 1.0
    end
  end

  # wait until the temperature drops below _temp
  def goBelowTemperature(_temp)
    while (processValue() > _temp)
      logTemperature()
      sleep 1.0
    end
  end

  # attempt to re-init the serial port after an error
  def reset
    @client.close
    sleep(5)
    @client = TemperatureControllerClient.new(@portname, @client.baud, @client.slave, @opts)
  end

  def logTemperature
    if temperatureLog
      pv = client.processValue || 0.0
      temperatureLog.printf("%s,%.1f,%.1f\n",
                            Time.now.strftime("%H:%M:%S"),
                            client.setpointValue,
                            pv )
      temperatureLog.fsync
    end
  end

  def ramp(_from,_to,_time)
    temp = _from
    begin
      TimedRepeat.repeatAt(class.defaultSamplingPeriod, class.defaultAllowableLateness) do |t|
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
    $stderr.puts(_profile.pretty_print_inspect)
    startTemp = _startTemp
    temperatureLog.puts("time,setpoint,process") if temperatureLog
    _profile.each_with_index do |step,i|
      $stderr.puts "#{i} #{startTemp} => #{step[0]} over #{step[1]} secs"
      endTemp = step[0]
      stepTime = step[1]
      ramp(startTemp, endTemp, stepTime)
      $stderr.puts "  waiting for temp to go from #{processValue} to #{endTemp}"
      goToTemperature(endTemp)
      startTemp = endTemp
    end
  end

  # delegate all SOLO register accessors to client
  def_delegators(*(([:@client] + SOLO::RO_DATA_REGISTERS.keys.map(&:to_sym)).flatten))
  def_delegators(*([:@client] + SOLO::RW_DATA_REGISTERS.keys.grep(/s*0$/).map { |s| s.sub(/s*0$/, "s").to_sym }.flatten))
  def_delegators(*([:@client] + SOLO::RW_DATA_REGISTERS.keys.map { |k| [k, "#{k}="] }.flatten))

  # delegate some other SOLO methods to client
  def_delegators(:@client,:debug,:debug=,:profile,:runMode,:receive_pdu,:transmit_pdu)
  def_delegators(:@client,:initial_response_timeout,:initial_response_timeout=)
  def_delegators(:@client,:inter_character_timeout,:inter_frame_timeout,:inter_character_timeout=,:inter_frame_timeout=)

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

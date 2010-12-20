#!/usr/bin/env ruby
# $Id$
#
BEGIN {
  srcdir = File.dirname(File.dirname(__FILE__))
  %w(lib ).each { |d| $: << File.join(srcdir, d) }
}

# gem install serialport
require 'serialport' # avoid "undefined method 'create' for class 'Class'" error
# gem install rmodbus
require 'rmodbus'
require 'forwardable'
require 'enumerator'

require 'pid'
require 'temperatureControl'
require 'timedRepeat'

require 'rmodbus_fixes'
require 'solo'

class SMDOven
  include SOLO
  extend Forwardable

  def_delegators(*(([:@client] + SOLO::RO_DATA_REGISTERS.keys.map(&:to_sym)).flatten))
  def_delegators(*([:@client] + SOLO::RW_DATA_REGISTERS.keys.grep(/s*0$/).map { |s| s.sub(/s*0$/, "s").to_sym }.flatten))
  def_delegators(*([:@client] + SOLO::RW_DATA_REGISTERS.keys.map { |k| [k, "#{k}="] }.flatten))
  def_delegators(:@client,:debug,:debug=,:profile,:runMode)

  # configuration
  @defaultSamplingPeriod = 1
  @defaultAllowableLateness = 0.1
  @defaultDataRate = 9600
  @defaultSlaveAddress = 1
  # read_timeout is in msec
  # and is used by SerialPort instance
  @defaultSerialOptions = {
    :data_bits => 8,
    :stop_bits => 1,
    :parity => SerialPort::EVEN,
    :read_timeout => (1000.0 * (8 + 1 + 1) / @defaultDataRate).round.to_i }

  class << self
    attr_accessor :defaultSamplingPeriod, :defaultAllowableLateness,
      :defaultDataRate, :defaultSerialOptions, :defaultSlaveAddress
  end

  def initialize(_profile, _port,
                 _dataRate=self.class.defaultDataRate,
                 _slaveAddress=self.class.defaultSlaveAddress,
                 _opts=self.class.defaultSerialOptions)
    @client = TemperatureControllerClient.new(_port, _dataRate, _slaveAddress, _opts)
    @opts = _opts
    @temperatureLog = nil
  end

  attr_reader :client
  attr_accessor :temperatureLog

  def goToTemperature(_temp, _epsilon=1.0)
    @client.setpointValue=(_temp)
    while (processValue() - _temp).abs > _epsilon
      sleep 1.0
    end
  end

  def reset
    @client.close
    sleep(5)
    sport = Dir.glob("/dev/cu.usbserial*").first
    @client = TemperatureControllerClient.new(sport, @client.baud, @client.slave, @opts)
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
        if temperatureLog
          pv = client.processValue || 0.0
          temperatureLog.printf("%s,%.1f,%.1f\n",
                                Time.now.strftime("%H:%M:%S"),
                                temp,
                                pv )
        end
      end
    rescue TimedRepeat::MissedRepeat
      retry
    end
  end

  # profile is array of [temperature,time] values
  def doProfile(_profile,_startTemp=processValue)
    controlMode= CM_PID
    startTemp = _startTemp
    temperatureLog.puts("time,setpoint,process") if temperatureLog
    _profile.each_with_index do |step,i|
      $stderr.puts "#{i} #{startTemp} => #{step[0]} over #{step[1]} secs"
      ramp(startTemp, step[0], step[1])
      startTemp = step[0]
    end
  end
end

# if __FILE__ == $0

include SOLO

sport = Dir.glob("/dev/cu.usbserial*").first
puts "using serial port #{sport}"
$oven = SMDOven.new([], sport)

$oven.runMode RUN_MODE_STOP
puts "PV=#{$oven.processValue}"
puts "SV=#{$oven.setpointValue}"

$oven.client.controlMode= CM_PID
$oven.setpointValue= 25.0
puts "SV=#{$oven.setpointValue}"


def catchErrorsWhile
  # $oven.runMode RUN_MODE_STOP
  # p $oven.profile(0)
  # $oven.debug= true
  $oven.temperatureLog= $stdout
  begin
    yield
  rescue Interrupt
    $oven.setpointValue= 25.0
    $stderr.puts("setpoint reset")
  rescue ModBus::Errors::ModBusException, Errno::ENXIO
    $stderr.puts $!.to_s
    $stderr.puts $!.message
    $stderr.puts $!.backtrace.join("\n")
    $stderr.puts("RESET")
    $oven.reset
    retry
  rescue
    $stderr.puts "ERROR!", $!.to_s, $!.message, $!.backtrace.join("\n")
  end
end

def dumpRegisters
  catchErrorsWhile do
    (RO_DATA_REGISTERS.keys + RW_DATA_REGISTERS.keys).sort.each { |k| puts "#{k} = #{$oven.send(k)}" }
  end
end

def testProfile
  catchErrorsWhile do
    $oven.runMode RUN_MODE_RUN
    $oven.doProfile([[40,120],[30,120]], 19)
  end
end

dumpRegisters
testProfile

# end

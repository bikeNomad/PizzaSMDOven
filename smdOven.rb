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

require 'pid'
require 'temperatureControl'
require 'timedRepeat'

module ModBus
  class RTUClient
    alias_method :old_initialize, :initialize

    def initialize(_port,_dataRate,_slaveAddress,_opts)
      old_initialize(_port,_dataRate,_slaveAddress,_opts)
      @character_delay = 
        (1.0 + @sp.data_bits +
        @sp.stop_bits +
        ((@sp.parity == SerialPort::NONE) ? 1 : 0)) / _dataRate
      @initial_response_timeout = 0.01
    end

    attr_accessor :character_delay, :initial_response_timeout

    # return false if no read data is available for me yet
    # timeout is in seconds
    def read_data_available?(timeout = 0)
      (rh, wh, eh) = IO::select([@sp], nil, nil, timeout)
      ! rh.nil?
    end

    def read_all_available_bytes(timeout =0, max = 1000)
      if read_data_available?(timeout)
        @sp.sysread(max)
      else
        ''
      end
    end

    def wait_for_characters(n)
      if (n > 0)
        sleep(@character_delay * n)
      end
    end

    def read_pdu
        # initial delay for some bytes to be available
        sleep(@initial_response_timeout)

        msg = ''

        # get first 2 bytes to check for error
        while msg.size < 2
          wait_for_characters(2 - msg.size)
          msg += read_all_available_bytes
        end

        if msg.getbyte(0) != @slave
          log "Ignore package: don't match slave ID"
          msg = ''
        else
          # ensure that we have count of remaining bytes
          while msg.size < 3
            wait_for_characters(3 - msg.size)
            msg += read_all_available_bytes
          end
          # now get rest of the bytes
          # expect 2+1+<payload>+2 bytes
          expected_bytes = msg.getbyte(2) + 5
          while msg.size < expected_bytes
            wait_for_characters(expected_bytes - msg.size)
            msg += read_all_available_bytes
          end
        end

        if (msg)
          log "Rx (#{msg.size} bytes): " + logging_bytes(msg)
          return msg[1..-3] if msg[-2,2].unpack('n')[0] == crc16(msg[0..-3])
          log "Ignore package: don't match CRC"
        end
        return ''
    end
  end
end

class SoloTemperatureControllerClient < ModBus::RTUClient
  include ModBus

  def initialize(_port,_dataRate,_slaveAddress,_opts)
    super
  end
end

class SMDOven
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
    @profile = _profile
    @client = SoloTemperatureControllerClient.new(_port, _dataRate, _slaveAddress, _opts)
    # @tempController
  end

  attr_accessor :profile
  attr_reader :client

  # profile is array of [temperature,time] values
  def doTemperatureControl(_profile)
    profileStep = Enumerator
    _profile.each do |temperature,duration|
      # main loop
      begin
        TimedRepeat.repeatAt(self.class.defaultSamplingPeriod, self.class.defaultAllowableLateness) do |t|
          t.stop
        end
      rescue TimedRepeat::MissedRepeat
      end
    end
  end
end

# if __FILE__ == $0

sport = Dir.glob("/dev/cu.usbserial*").first
puts "using serial port #{sport}"
$oven = SMDOven.new([], sport)
$oven.client.debug= true
$oven.client.read_holding_registers(0x1001, 1)

# end

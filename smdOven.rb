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

require 'pid'
require 'temperatureControl'
require 'timedRepeat'

# Fixes for rmodbus 0.40.0
module ModBus
  class RTUClient
    alias_method :old_initialize, :initialize

    def initialize(_port,_dataRate,_slaveAddress,_opts)
      old_initialize(_port,_dataRate,_slaveAddress,_opts)
      @character_duration = 
        (1.0 + @sp.data_bits +
        @sp.stop_bits +
        ((@sp.parity == SerialPort::NONE) ? 1 : 0)) / _dataRate
      # per current MODBUS/RTU spec:
      if _dataRate < 19200
        @inter_character_timeout = 1.5 * @character_duration
        @inter_frame_timeout = 3.5 * @character_duration
      else
        @inter_character_timeout = 750e-6
        @inter_frame_timeout = 1.75e-3
      end
      @initial_response_timeout = 0.02
      @transmit_pdu = ''
      @receive_pdu = ''
      @last_transmit = Time.now - @inter_frame_timeout
      @last_receive = Time.now
      @sp.read_timeout = (2 * @inter_character_timeout * 1000.0).round.to_i
      # flush old garbage
      read_all_available_bytes()
    end

    attr_accessor :character_duration, :initial_response_timeout
    attr_reader :receive_pdu, :transmit_pdu

    # return false if no read data is available for me yet
    # timeout is in seconds
    def read_data_available?(timeout = 0)
      (rh, wh, eh) = IO::select([@sp], nil, nil, timeout)
      ! rh.nil?
    end

    def read_all_available_bytes(timeout =0, max = 1000)
      if read_data_available?(timeout)
        r = @sp.sysread(max)
        @last_receive = Time.now
        r
      else
        ''
      end
    end

    def wait_for_characters(n)
      if (n > 0)
        sleep(@character_duration * n)
      end
    end

    def send_pdu(pdu)
      @transmit_pdu = @slave.chr + pdu 
      @transmit_pdu << crc16(@transmit_pdu).to_word

      # ensure minimum gap of 3.5 chars since last xmit
      now = Time.now
      early = @inter_frame_timeout - (now - @last_transmit)
      if early > 0
        log "too fast by #{early}"
        sleep(early)
      end

      @sp.write @transmit_pdu
      @last_transmit = Time.now

      log "Tx (#{@transmit_pdu.size} bytes): " + logging_bytes(@transmit_pdu)
    end

    def read_pdu
        # initial delay for some bytes to be available
        sleep(@inter_frame_timeout)

        @receive_pdu = ''

        # get first byte
        while @receive_pdu.empty?
          @receive_pdu = read_all_available_bytes
        end

        # keep getting bytes until frame timeout
        while read_data_available?(@inter_frame_timeout)
          @receive_pdu += read_all_available_bytes
          gap = Time.now - @last_receive 
          if gap > @inter_character_timeout && gap < @inter_frame_timeout
            # ERROR: too long a gap inside message
            log "too-long inter-character gap in PDU"
            raise ModBusTimeout.new("Too-long inter-character gap in PDU")
          end
        end

        retval = ''

        log "Rx (#{@receive_pdu.size} bytes): " + logging_bytes(@receive_pdu)

        if @receive_pdu.getbyte(0) != @slave
          log "Ignore package: don't match slave ID"
          @receive_pdu = ''
        end

        if @receive_pdu.size > 4
          retval = @receive_pdu[1..-3]
          if @receive_pdu[-2,2].unpack('n')[0] != crc16(@receive_pdu[0..-3])
            log "Ignore package: don't match CRC"
            retval = ''
          end
        end

        @receive_pdu = '' # clear PDU
        return retval
    end
  end
end

module SOLO

    # error codes from reading PV
    PV_INITIAL_PROCESS = 0x8002
    PV_NO_TEMPERATURE_SENSOR = 0x8003
    PV_SENSOR_INPUT_ERROR = 0x8004
    PV_SENSOR_ADC_ERROR = 0x8006
    PV_MEMORY_ERROR = 0x8007

    # control modes
    CM_PID = 0
    CM_ON_OFF = 1
    CM_MANUAL = 2
    CM_RAMP_SOAK = 3

  class TemperatureControllerClient < ModBus::RTUClient
    include ModBus

    def initialize(_port,_dataRate,_slaveAddress,_opts)
      super
    end

    def read_holding_registers(addr,n)
      printf("read(%04x,%d)\n", addr,n)
      v = super(addr,n)
      printf(" => %s\n", v.inspect)
      v
    end

    def read_single_register(addr)
      printf("read(%04x)\n", addr)
      v = query("\x3" + addr.to_word + 1.to_word).unpack('n*')
      printf("  => %s\n", v.inspect)
      v[0]
    end

    def write_single_register(addr,val)
      printf("write(%04x,%d)\n", addr,val.to_i)
      super(addr,val.to_i)
    end

    
    def processValue
      read_single_register(0x1000) / 10.0
    end

    def setpointValue
      read_single_register(0x1001) / 10.0
    end

    def setpointValue=(val)
      write_single_register(0x1001, (val * 10.0).round)
    end

    def controlMode
      read_single_register(0x1005)
    end

    def controlMode=(mode)
      write_single_register(0x1005, mode)
    end

  end

end


class SMDOven
  include SOLO
  extend Forwardable

  def_delegators :@client,:processValue,:setpointValue,:controlMode,:setpointValue=,:controlMode=

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
    @client = TemperatureControllerClient.new(_port, _dataRate, _slaveAddress, _opts)
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

include SOLO

sport = Dir.glob("/dev/cu.usbserial*").first
puts "using serial port #{sport}"
$oven = SMDOven.new([], sport)
$oven.client.debug= true
puts "PV=#{$oven.processValue}"
puts "SV=#{$oven.setpointValue}"

$oven.client.controlMode= CM_PID
$oven.setpointValue= 25.0
puts "SV=#{$oven.setpointValue}"

# end

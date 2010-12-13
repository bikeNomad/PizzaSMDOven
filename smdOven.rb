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
  CONTROL_MODES = [ CM_PID, CM_ON_OFF, CM_MANUAL, CM_RAMP_SOAK ]

  RO_DATA_REGISTERS = {
    "processValue" =>  [0x1000, 10.0],
    "ledStatus" =>  0x102A,
    "pushbuttonStatus" => 0x102B,
    "firmwareVersion" => 0x102F
  }

  RW_DATA_REGISTERS = {
    "setpointValue" => [0x1001, 10.0],
    "inputRangeHigh" => [0x1002, 10.0],
    "inputRangeLow" => [0x1003, 10.0],
    "inputType" => 0x1004,
    "controlMode" => 0x1005,
    "heatingCooling" => 0x1006,
    "output1Period" => 0x1007,
    "output2Period" => 0x1008,

    "pidParameterGroup" => 0x101c,  # affects following PID params
    "proportionalBand" => [0x1009, 10.0],   # P1-4
    "integralTime" => 0x100A, # P1-5
    "derivativeTime" => 0x100B, # P1-5
    "integralOffset" => [0x100C, 1000.0], # P1-8
    "pdControlOffset" => [0x100D, 1000.0],

    "proportionalCoefficient" => [0x100E, 100.0],
    "deadBand" => 0x100F,
    "heatingHysteresis" => 0x1010,
    "coolingHysteresis" => 0x1011,
    "output1Level" => [0x1012, 1000.0],
    "output2Level" => [0x1013, 1000.0],
    "analogHighAdjustment" => 0x1014,
    "analogLowAdjustment" => 0x1015,
    "processValueOffset" => 0x1016,
    "decimalPointPosition" => 0x1017,
    "targetSetpointValue" => [0x101D, 10.0],
    "alarm1" => 0x1020,
    "alarm2" => 0x1021,
    "alarm3" => 0x1022,
    "systemAlarm" => 0x1023,
    "alarm1HighLimit" => 0x1024,
    "alarm1LowLimit" => 0x1025,
    "alarm2HighLimit" => 0x1026,
    "alarm2LowLimit" => 0x1027,
    "alarm3HighLimit" => 0x1028,
    "alarm3LowLimit" => 0x1029,
    "lockMode" => 0x102C,

    "startingRampSoakPattern" => 0x1030,
    # repeated for 0..7
    "lastStepNumber0" => 0x1040,
    "additionalCycles0" => 0x1050,
    "nextPatternNumber0" => 0x1060,
    "rampSoakSetpointValue0" => [0x2000, 10.0],
    "rampSoakTime0" => [0x2080, 1.0/60.0 ]
  }

  class TemperatureControllerClient < ModBus::RTUClient
    include ModBus

  protected
    multi = RW_DATA_REGISTERS.keys.grep(/0$/)
    multi.each do |m|
      name = m.sub(/s*0$/, "s")
      addr = RW_DATA_REGISTERS[m]
      scale = ""
      awscale = ""
      if addr.is_a?(Enumerable)
        ascale = ".map { |v| v / #{addr[1]}}"
        scale = "/#{addr[1]}"
        awscale = ".map { |v| (v * #{addr[1]}).round.to_i }"
        addr = addr[0]
      end
      self.class_eval <<EOT
  def #{name}(n,a=nil);
    if (a)
      a#{awscale}.each_with_index { |v,i| write_single_register(#{addr}+n*8+i)#{scale} }; end"
    else
    read_holding_registers(#{addr}+n*8,8)#{ascale}
    end
  end
EOT
    end
    RO_DATA_REGISTERS.each_pair do |name,addr|
      scale = ""
      if addr.is_a?(Enumerable)
        scale = "/#{addr[1]}"
        addr = addr[0]
      end
      self.class_eval "def #{name}; read_single_register(#{addr})#{scale}; end"
    end
    RW_DATA_REGISTERS.each_pair do |name,addr|
      scale = ""
      wscale = ""
      if addr.is_a?(Enumerable)
        wscale = "*#{addr[1]}"
        scale = "/#{addr[1]}"
        addr = addr[0]
      end
      self.class_eval "def #{name}; read_single_register(#{addr})#{scale}; end"
      self.class_eval "def #{name}=(val); write_single_register(#{addr},(val#{wscale}).to_i); end"
    end

  public
    def initialize(_port,_dataRate,_slaveAddress,_opts)
      super
    end

    alias_method :old_rst, :rampSoakTimes

    def rampSoakTimes
      old_rst.map(&:round)
    end

    def profile
      rampSoakSetpointValues.zip(rampSoakTimes)
    end

  protected

    def read_holding_registers(addr,n)
      log sprintf("read(%04x,%d)\n", addr,n)
      v = super(addr,n)
      log sprintf(" => %s\n", v.inspect)
      v
    end

    def read_single_register(addr)
      log sprintf("read(%04x)\n", addr)
      v = query("\x3" + addr.to_word + 1.to_word).unpack('n*')
      log sprintf("  => %s\n", v.inspect)
      v[0]
    end

    def write_single_register(addr,val)
      log sprintf("write(%04x,%d)\n", addr,val.to_i)
      super(addr,val.to_i)
    end
  end

end


class SMDOven
  include SOLO
  extend Forwardable

  def_delegators(*(([:@client] + SOLO::RO_DATA_REGISTERS.keys.map(&:to_sym)).flatten))
  def_delegators(*([:@client] + SOLO::RW_DATA_REGISTERS.keys.map { |k| [k, "#{k}="] }.flatten))
  def_delegators(:@client,:debug,:debug=)

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

# if __FILE__ == $0 || IRB.CurrentContext

include SOLO

sport = Dir.glob("/dev/cu.usbserial*").first
puts "using serial port #{sport}"
$oven = SMDOven.new([], sport)
# $oven.debug= true

puts "PV=#{$oven.processValue}"
puts "SV=#{$oven.setpointValue}"

$oven.client.controlMode= CM_PID
$oven.setpointValue= 25.0
puts "SV=#{$oven.setpointValue}"

(RO_DATA_REGISTERS.keys + RW_DATA_REGISTERS.keys).sort.each { |k| puts "#{k} = #{$oven.send(k)}" }

# end

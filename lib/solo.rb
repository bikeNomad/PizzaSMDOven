# $Id$
# Automation Direct SOLO temperature controller
#
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

  # run modes
  RUN_MODE_STOP = 0
  RUN_MODE_RUN = 1

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
    "rampSoakTime0" => [0x2080, 1.0/60.0 ],

  }

  RW_BIT_REGISTERS = {
    "autoTune" => 0x0813,
    "runMode" => 0x0814,  # 0 = stop, 1 = run
    "stopRampSoak" => 0x0815,
    "holdRampSoak" => 0x0816,
  }

  class TemperatureControllerClient < ModBus::RTUClient
    include ModBus

  protected
    multi = RW_DATA_REGISTERS.keys.grep(/0$/)
    multi.each do |m|
      name = m.sub(/s*0$/, "s")
      addr = RW_DATA_REGISTERS[m]
      scale = ""
      wscale = ""
      if addr.is_a?(Enumerable)
        ascale = ".map { |v| v / #{addr[1]}}"
        scale = "/#{addr[1]}"
        wscale = "*#{addr[1]}.round.to_i"
        addr = addr[0]
      end
      self.class_eval <<EOT
        def #{name}(n,a=nil)
          if (a)
            a.each_with_index { |v,i| write_single_register(#{addr}+n*8+i,v#{wscale}) }
          else
            read_holding_registers(#{addr}+n*8,8)#{ascale}
          end
        end
EOT
    end
    (RW_DATA_REGISTERS.merge(RO_DATA_REGISTERS)).each_pair do |name,addr|
      scale = ""
      if addr.is_a?(Enumerable)
        scale = "/#{addr[1]}"
        addr = addr[0]
      end
      self.class_eval <<EOT
        def #{name}
          v = read_single_register(#{addr})
          v && v#{scale}
        end
EOT
    end
    RW_DATA_REGISTERS.each_pair do |name,addr|
      scale = ""
      wscale = ""
      if addr.is_a?(Enumerable)
        wscale = "*#{addr[1]}"
        scale = "/#{addr[1]}"
        addr = addr[0]
      end
      self.class_eval <<EOT
        def #{name}=(val)
          write_single_register(#{addr},(val#{wscale}).to_i)
        end
EOT
    end

  public
    def initialize(_port,_dataRate,_slaveAddress,_opts)
      super
    end

    alias_method :old_rst, :rampSoakTimes

    def rampSoakTimes(n,a=nil)
      old_rst(n,a).map(&:round)
    end

    def profile(n,a=nil)
      rampSoakSetpointValues(n,a).zip(rampSoakTimes(n,a))
    end

    def runMode(m=nil)
      if (m.nil?)
        return read_discrete_inputs(0x0814,1)[0]
      else
        puts "RUN MODE=#{m}"
        write_single_coil(0x0814,m)
      end
    end

  protected

    def read_holding_registers(addr,n)
      log sprintf("read(%04x,%d)\n", addr,n)
      v = super(addr,n)
      log sprintf(" => %s\n", v.inspect)
      v
    end

    # returns nil on error
    def read_single_register(addr)
      log sprintf("read(%04x)\n", addr)
      v = query("\x3" + addr.to_word + 1.to_word)
      return nil if v.nil?
      v = v.unpack('n*')
      log sprintf("  => %s\n", v.inspect)
      v[0]
    end

    def write_single_register(addr,val)
      log sprintf("write(%04x,%d)\n", addr,val.to_i)
      super(addr,val.to_i)
    end
  end

end # module SOLO

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

  # arg for heatingCooling
  HC_HEATING = 0
  HC_COOLING = 1
  HC_HEATING_COOLING = 2  # output 1 for heating, 2 for cooling
  HC_COOLING_HEATING = 3  # output 2 for heating, 1 for cooling

  # arg for nextPatternNumber
  NO_NEXT_PATTERN = 8

  # arg for pidParameterGroup
  PID_PARAMETER_GROUP_AUTO = 4

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

    "targetSetpointValue" => [0x101D, 10.0],
    "proportionalBand" => [0x1009, 10.0],   # P1-4
    "integralTime" => 0x100A, # P1-5
    "derivativeTime" => 0x100B, # P1-5
    "integralOffset" => [0x100C, 1000.0],   # P1-8

    "pdControlOffset" => [0x100D, 1000.0],  # P1-7
    "proportionalCoefficient" => [0x100E, 100.0], # P1-14
    "deadBand" => 0x100F, # P1-15
    "heatingHysteresis" => 0x1010,
    "coolingHysteresis" => 0x1011,

    "output1Level" => [0x1012, 1000.0],
    "output2Level" => [0x1013, 1000.0],
    "analogHighAdjustment" => 0x1014,
    "analogLowAdjustment" => 0x1015,
    "processValueOffset" => 0x1016,
    "decimalPointPosition" => 0x1017,
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
  }

  # repeated x8 (per pattern)
  RW_MULTI_PER_RS_PATTERN = {
    # repeated for 0..7
    "lastStepNumber" => 0x1040,  # 0x1040 .. 0x1047
    "additionalCycles" => 0x1050,
    "nextPatternNumber" => 0x1060,
  }

  # repeated x64 (8 steps/pattern for each of 8 patterns)
  RW_MULTI_PER_RS_STEP = {
    # repeated for 0..0x3f (8x8)
    "rampSoakSetpointValues" => [0x2000, 10.0],   # 0x2000 .. 0x203f
    "rampSoakTimes" => [0x2080, "1.0/60.0" ],   # 0x2080 .. 0x20bf
  }

  RO_BIT_REGISTERS = {
    "autoTuneLEDStatus"     => 0x0800,
    "rampSoakControlStatus" => 0x080f,
  }

  RW_BIT_REGISTERS = {
    "onlineConfiguration" => 0x810,
    "temperatureUnitsC" => 0x811,
    "decimalPointDisplay" => 0x812,
    "autoTuning" => 0x0813,
    "runMode" => 0x0814,  # 0 = stop, 1 = run
    "stopRampSoakControl" => 0x0815,
    "holdRampSoakControl" => 0x0816,

    "autoTuneLEDStatus"     => 0x0800,  # RO
    "rampSoakControlStatus" => 0x080f,  # RO
  }

  class TemperatureControllerClient < ModBus::RTUClient
    include ModBus
    include ModBus::Common

  protected
    class << self
      def defineMethod(str)
        self.class_eval(str)
        # $stderr.puts(str)
      end
    end

    (RW_MULTI_PER_RS_PATTERN.merge(RW_MULTI_PER_RS_STEP)).each_pair do |name,addr|
      isMulti = RW_MULTI_PER_RS_STEP.keys.include?(name)
      rscale = ""
      scale = ""
      wscale = ""
      if addr.is_a?(Enumerable)
        rscale = "/(#{addr[1]})"
        ascale = ".map { |v| v/(#{addr[1]}) }"
        wscale = "*#{addr[1]}.round.to_i"
        addr = addr[0]
      end
      methodstring = nil
      if isMulti
        methodstring = <<-EOT
          # #{name}(n) -- read #{name}[n], return array of 8 values
          # #{name}(n, valarray) -- write valarray[0..7] to #{name}[n][0..7]
          def #{name}(n,a=nil)
            if (a)
              a.each_with_index { |v,i| write_single_register(#{addr}+n*8+i,v#{wscale}) }
            else
              read_holding_registers(#{addr}+n*8,8)#{ascale}
            end
          end
          EOT
      else
        methodstring = <<-EOT
          # #{name}(n) -- read #{name}[n]
          # #{name}(n, val) -- write val to #{name}[n]
          def #{name}(n,a=nil)
            if (a)
              write_single_register(#{addr}+n,a#{wscale})
            else
              read_single_register(#{addr}+n)#{rscale}
            end
          end
          EOT
      end
      self.defineMethod(methodstring)
    end

    (RW_DATA_REGISTERS.merge(RO_DATA_REGISTERS)).each_pair do |name,addr|
      scaled = ""
      if addr.is_a?(Enumerable)
        scaled = "\n          v && v/#{addr[1]}"
        addr = addr[0]
      else
        scaled = ""
      end
      methodstring = <<-EOT
        def #{name}
          v = read_single_register(#{addr})#{scaled}
        end
        EOT
      self.defineMethod(methodstring)
    end

    RW_DATA_REGISTERS.each_pair do |name,addr|
      wscale = ""
      if addr.is_a?(Enumerable)
        wscale = "*#{addr[1]}"
        addr = addr[0]
      end
      methodstring = <<-EOT
        def #{name}=(val)
          write_single_register(#{addr},(val#{wscale}).to_i)
        end
        EOT
      self.defineMethod(methodstring)
    end

    RW_BIT_REGISTERS.each_pair do |name,addr|
      methodstring = <<-EOT
        def #{name}
          read_discrete_inputs(#{addr},1)[0]
        end
        def #{name}=(b)
          write_single_coil(#{addr},b || 0)
        end
        EOT
      self.defineMethod(methodstring)
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
      if a.nil?
        rampSoakSetpointValues(n).zip(rampSoakTimes(n))
      else
        temps = a.map { |p| p[0] }
        times = a.map { |p| p[1] }
        rampSoakSetpointValues(n,temps)
        rampSoakTimes(n,times)
      end
    end

    def runMode=(m=nil)
      rm = read_discrete_inputs(0x0814,1)[0]
      if (m.nil?)
        return rm
      else
        return if m == rm
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

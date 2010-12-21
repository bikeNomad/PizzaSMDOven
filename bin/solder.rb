#!/usr/bin/env ruby
# $Id$
#
BEGIN { $: << File.join(File.dirname(__FILE__), 'lib') }

require 'smdoven'

if __FILE__ == $0 || __FILE__ == "irb"

include SOLO
# include ModBus
# include ModBus::Common

sport = Dir.glob("/dev/cu.usbserial*").first
puts "using serial port #{sport}"
$oven = SMDOven.new([], sport)

$oven.runMode RUN_MODE_STOP

$oven.setpointValue= $oven.processValue
puts "PV=#{$oven.processValue}"
puts "SV=#{$oven.setpointValue}"

$retryOnMBError = true

def catchErrorsWhile(logfile=$stderr)
  begin
    yield
  rescue Interrupt
    $oven.setpointValue= 25.0
    logfile.puts("setpoint reset")
  rescue ModBus::Errors::ModBusException, Errno::ENXIO
    logfile.puts $!.to_s
    logfile.puts $!.message
    logfile.puts $!.backtrace.join("\n")
    logfile.puts [ "xmit", logging_bytes($oven.transmit_pdu) ]
    logfile.puts [ "rcv", logging_bytes($oven.receive_pdu) ]
    if $retryOnMBError
      logfile.puts("RESET")
      $oven.reset
      retry 
    else
      raise
    end
  rescue
    logfile.puts "ERROR!", $!.to_s, $!.message, $!.backtrace.join("\n")
  end
end

def dumpRegisters(logfile=$stderr)
  catchErrorsWhile(logfile) do
    (RO_DATA_REGISTERS.keys + RW_DATA_REGISTERS.keys).sort.each { |k| puts "#{k} = #{$oven.send(k)}" }
  end
end

def testProfile(logfile=$stderr)
  logfile.sync= true
  catchErrorsWhile(logfile) do
    $oven.runMode RUN_MODE_RUN
    $oven.setpointValue= 25.0
    $oven.goBelowTemperature(40.0)
    $oven.doProfile([[155,0],[180,60],[215,0],[40,0]], 25)
  end
end


dumpRegisters

$oven.decimalPointPosition= 1
$oven.output2Period= 10

$retryOnMBError = false

# $oven.controlMode= CM_PID
$oven.controlMode= CM_ON_OFF
# $oven.debug= true
File.open("temperature_log.csv", "w") do |lf|
  $oven.temperatureLog= lf
  testProfile
end

end

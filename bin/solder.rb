#!/usr/bin/env ruby
# $Id$
#
BEGIN {
  $: << File.join(File.dirname(File.dirname(__FILE__)), 'rmodbus')
  $: << File.join(File.dirname(File.dirname(__FILE__)), 'lib')
}

require 'pp'
require 'smdoven'

class SMDOven

  # Solder profile from Kester for leaded solders
  LEADED_PROFILE = [[155,0],[180,60],[215,0],[40,0]]

  def leadedProfile
    controlMode= CM_ON_OFF
    sleep(1.0)
    runMode= RUN_MODE_RUN
    sleep(1.0)
    goBelowTemperature(40.0)
    doProfile(LEADED_PROFILE, 25)
    sleep(1.0)
  end

  def setUpProfile(n = 0)
    pidParameterGroup= PID_PARAMETER_GROUP_AUTO 
    controlMode= CM_RAMP_SOAK
    # set up profile in unit
    setPatternToProfile(n, LEADED_PROFILE, 25)
  end

  def startProfile(n = 0)
    runMode = RUN_MODE_STOP
    controlMode = CM_RAMP_SOAK
    startingRampSoakPattern = n
    holdRampSoakControl = 0
    stopRampSoakControl = 0
    runMode = RUN_MODE_RUN
  end

end

if __FILE__ == $0 || $0 == "irb"

  include SOLO

  # find serial port
  # if mac
  $portname = ARGV[0] || Dir.glob("/dev/cu.usbserial*").first
  raise "no USB serial port found" if $portname.nil?
  puts "using serial port #{$portname}"

  temperatureLogName = Time.now.strftime("temperature_log_%y%m%d_%H%M%S.txt")
  puts "\nLogging temperature data to #{temperatureLogName}"
  $logfile = File.open(temperatureLogName, "w")

  begin
    # construct oven
    $oven = SMDOven.new([], $portname)
    # $oven.debug= true
    $oven.statusLog= $stdout

    # initialize modes; stop oven
    $oven.runMode= RUN_MODE_STOP
    $oven.decimalPointPosition= 1
    $oven.output2Period= 10

    # set setpoint to current temperature
    # $oven.setpointValue= $oven.processValue
    $oven.controlMode = CM_ON_OFF
    $oven.setpointValue= 25.0
    puts "PV=#{$oven.processValue}"
    puts "SV=#{$oven.setpointValue}"

    $oven.temperatureLog= $logfile

    if $0 == "irb"
#      $oven.setUpProfile
#      $oven.dumpRegisters
#      $oven.startProfile
#      $oven.waitForProfile

    else
      $oven.runMode= RUN_MODE_RUN
      puts "\nSet dial to 20 and hit ENTER"
      $stdin.readline
      $oven.leadedProfile
    end

  rescue Interrupt
    puts $!.message
    puts $!.backtrace.join("\n")

    $oven.setpointValue= 25.0
    puts("setpoint reset to 25")

  rescue
    puts $!.message
    puts $!.backtrace.join("\n")

    if $oven
      $oven.dumpPDUs
    end
    raise

  ensure
    $oven.setpointValue= 25.0

  end

end

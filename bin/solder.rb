#!/usr/bin/env ruby
# $Id$
#
BEGIN { $: << File.join(File.dirname(File.dirname(__FILE__)), 'lib') }

require 'pp'
require 'smdoven'

class SMDOven
  LEADED_PROFILE = [[155,0],[180,60],[215,0],[40,0]]

  # Solder profile from Kester for leaded solders
  def leadedProfile
    controlMode= CM_ON_OFF
    runMode= RUN_MODE_RUN
    goBelowTemperature(40.0)
    doProfile(LEADED_PROFILE, 25)
  end

  def setUpProfile
    pidParameterGroup= PID_PARAMETER_GROUP_AUTO 
    runMode= RUN_MODE_STOP
    controlMode= CM_RAMP_SOAK
    # set up profile in unit
    setPatternToProfile(0, LEADED_PROFILE, 25)
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
    $oven.setpointValue= 25.0
    puts "PV=#{$oven.processValue}"
    puts "SV=#{$oven.setpointValue}"

    $oven.temperatureLog= $logfile

    if $0 == "irb"
      $oven.setUpProfile
      $oven.dumpRegisters
    else
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
    if $oven
      $oven.dumpPDUs
      $oven.setpointValue= 25.0
    end
    raise

  end

end

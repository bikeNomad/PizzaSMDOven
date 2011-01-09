#!/usr/bin/env ruby
# $Id$
#
BEGIN { $: << File.join(File.dirname(File.dirname(__FILE__)), 'lib') }

require 'pp'
require 'smdoven'

class SMDOven

  # Solder profile from Kester for leaded solders
  def leadedProfile
    controlMode= CM_ON_OFF
    runMode RUN_MODE_RUN
    setpointValue= 25.0
    goBelowTemperature(40.0)
    doProfile([[155,0],[180,60],[215,0],[40,0]], 25)
  end

  def setUpProfile
    runMode RUN_MODE_STOP
    controlMode= CM_ON_OFF
    # set up profile in unit
  end

end

if __FILE__ == $0 || $0 == "irb"

  include SOLO

  # find serial port
  # if mac
  $portname = ARGV[0] || Dir.glob("/dev/cu.usbserial*").first
  if $portname.nil?
    raise "no USB serial port found"
  end
  puts "using serial port #{$portname}"

  temperatureLogName = Time.now.strftime("temperature_log_%y%m%d_%H%M%S.csv")
  puts "\nLogging temperature data to #{temperatureLogName}"
  $logfile = File.open(temperatureLogName, "w")

  begin
    # construct oven
    $oven = SMDOven.new([], $portname)
    # $oven.debug= true
    $oven.statusLog= $stdout

    # initialize modes; stop oven
    $oven.runMode RUN_MODE_STOP
    $oven.decimalPointPosition= 1
    $oven.output2Period= 10

    # set setpoint to current temperature
    # $oven.setpointValue= $oven.processValue
    $oven.setpointValue= 25.0
    puts "PV=#{$oven.processValue}"
    puts "SV=#{$oven.setpointValue}"
    $oven.dumpRegisters

    puts "\nSet dial to 20 and hit ENTER"
    $stdin.readline

    $oven.runMode RUN_MODE_RUN

    $oven.temperatureLog= $logfile
    $oven.leadedProfile unless $0 == "irb"

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

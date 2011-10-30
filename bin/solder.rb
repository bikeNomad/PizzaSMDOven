#!/usr/bin/env ruby
# Pizza oven SMD soldering.
# Ned Konz <ned@bike-nomad.com>
BEGIN {
  HERE=File.dirname(File.dirname(__FILE__))
  $: << File.join(HERE, 'lib')
}

require 'fileutils'

require 'rubygems'
require 'rmodbus'

require 'rmodbus_fixes'

require 'pp'
require 'smdoven'

class SMDOven
  include ModBus
  include Debug

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

  $tempHistory = []
  $logdir = File.join(HERE, 'logs')
  $debug = true

  def lp
    $oven.leadedProfile
  end

  # go to temp manually
  def t(temp=$tempHistory.pop)
    $oven.runMode= RUN_MODE_RUN
    if temp && temp.to_f.zero?
      $oven.setpointValue= 0.0
    else
      $tempHistory.push($oven.setpointValue)
      $oven.goToTemperature(temp || 30.0)
    end
  end

  # find serial port
  # if mac
  $portname = ARGV[0] || Dir.glob("/dev/cu.usbserial*").first
  raise "no USB serial port found" if $portname.nil?
  puts "using serial port #{$portname}"

  FileUtils.mkdir_p($logdir)
  temperatureLogName = Time.now.strftime("#{$logdir}/temperature_log_%y%m%d_%H%M%S.txt")
  puts "\nLogging temperature data to #{temperatureLogName}"

  begin
    $logfile = File.open(temperatureLogName, "w")
    emptyLogfileSize = 0

    # construct oven
    $oven = SMDOven.new([], $portname)
    $oven.debug= $debug
    $oven.debug_log= File.open(File.join($logdir, 'debug.log'), 'w')
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

    $oven.openTemperatureLog($logfile, true)
    emptyLogfileSize = $logfile.tell

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

  rescue
    puts $!.message
    puts $!.backtrace.join("\n")

    if $oven
      $oven.dumpPDUs
    end
    raise

  ensure
    $oven.setpointValue= 25.0
    puts("setpoint reset to 25")

    if $logfile
      here = $logfile.tell
      $logfile.close
      if here <= emptyLogfileSize
        puts("deleting empty file #{temperatureLogName}")
        FileUtils.rm(temperatureLogName)
      end
    end

  end

end

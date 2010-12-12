# Modbus client (over serial port, EIA-232 or EIA-485) in Ruby.
# $Id$

require 'serialport'

module Modbus

DefaultDataRate = 19200
DefaultDatabits = 8
DefaultParity = SerialPort::EVEN
DefaultStopbits = 1

class SerialConnection
  def initialize( _port = 1, _baud = DefaultDataRate, _stopbits = DefaultStopbits, _parity = DefaultParity)
    begin
      @port = SerialPort.open(_port, baud, self.class.databits(), _stopbits, _parity)
    rescue
      $stderr.puts "Error opening serial port #{_port}: #{$!}"
      exit 1
    end
  end

  def send(bytes)
  end

  def receive(timeout)
  end
end

class RS485Connection < SerialConnection
  def send(bytes)
    @port.
    super
  end

  def receive(timeout)
    super
  end
end

Errors = [ nil,
"Illegal Function",
"Illegal Data Address",
"Illegal Data Value",
"Slave Device Failure",
"Acknowledge",
"Slave Device Busy",
nil,
"Memory Parity Error",
nil,
"Gateway Path Unavailable" ,
"Gateway Target Device Failed to Respond" ]

class PDU
  def initialize(fncode)
    @functionCode = fncode
    @data = ""
  end
  attr_accessor :functionCode, :data
end


# Defines message frame packing and timeouts
# And also holds physical layer stuff
class TransmissionMode
  def errorCheck(pdu, slave=nil)
  end

  def frame(pdu, slave=nil)
  end

  # send the ADU and receive a response,
  # or raise an error
  def send(pdu, slave=nil)
  end
end

class SerialTransmissionMode < TransmissionMode
  protected

  def frame(pdu, slave=nil)
    adu = ""
    adu << slave.chr if slave
    adu << pdu
    adu << errorCheck(adu)
    adu
  end

  # CRC-16
  def crc16(adu)
    crc = 0xFFFF
    adu.each_byte do |b|
      crc ^= b
      8.times do
        lsb = crc & 1
        crc = (crc >> 1) & 0x7FFF
        crc ^= 0xA001 if lsb == 1
      end
    end
    [ crc ].pack("v")
  end

  def errorCheck(adu)
    crc16(adu)
  end

  def self.databits
    8
  end

  public

  def initialize(_connection)
    @connection = _connection
  end

  # send the ADU and receive a response,
  # or raise an error
  def send(pdu, slave=nil)
    adu = frame(pdu, slave)
  end
end

class ASCIIMode < SerialTransmissionMode
  protected
    def self.databits
      7
    end

    def frame(pdu, slave=nil)
      adu = super
    end
end

class IO
end

class DiscreteInput < IO
end

class Coil < IO
end

class InputRegister < IO
end

class HoldingRegister < IO
end

class PseudoRegister < IO
end

class FileRecord < IO
end
class Master
end


end # module Modbus

# $Id$
# Fixes for rmodbus 0.40.0 RTU client code 
# From Ned Konz <ned@bike-nomad.com>
#
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
    attr_accessor :inter_character_timeout, :inter_frame_timeout
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
        sleep(@initial_response_timeout)

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

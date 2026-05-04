# frozen_string_literal: true

require "libusb"

# Driver for the USB ESC/POS receipt printer. Talks to the printer's
# bulk OUT endpoint (writes) and bulk IN endpoint (real-time status reads)
# directly via libusb. Bypasses the kernel `usblp` driver via libusb's
# auto-detach, so the host doesn't need /dev/usb/lp0 to be available.
#
# Public API:
#
#   Printer.open do |p|
#     p.write("hello, printer!\n")
#   end                       # auto-feeds 6 lines + cuts on clean exit
#
#   Printer.status            # -> Printer::Status (online?, paper, cover, error)
#
# The class intentionally does NOT word-wrap. The printer auto-wraps at
# its column boundary in hardware. Send raw text + "\n" where you want
# line breaks.
class Printer
  USB_VENDOR_ID  = 0x1fc9
  USB_PRODUCT_ID = 0x2016

  PRINTER_INTERFACE_CLASS = 7
  FEED_BEFORE_CUT         = 6

  # Parsed real-time status. `paper` is one of :ok, :near_end, :out.
  Status = Struct.new(:online, :paper, :cover_open, :error, :raw, keyword_init: true) do
    def ok?
      online && paper != :out && !cover_open && !error
    end

    def summary
      return "online" if ok?

      reasons = []
      reasons << "offline"    unless online
      reasons << "paper out"  if paper == :out
      reasons << "paper low"  if paper == :near_end
      reasons << "cover open" if cover_open
      reasons << "error"      if error
      reasons.join(", ")
    end
  end

  def self.open
    printer = new
    begin
      yield printer
      printer.feed(FEED_BEFORE_CUT)
      printer.cut
    ensure
      printer.close
    end
  end

  def self.status
    printer = new
    printer.read_status
  ensure
    printer&.close
  end

  def initialize
    @ctx    = LIBUSB::Context.new
    @device = @ctx.devices(idVendor: USB_VENDOR_ID, idProduct: USB_PRODUCT_ID).first
    raise "USB printer not found (#{format('%04x:%04x', USB_VENDOR_ID, USB_PRODUCT_ID)})" unless @device

    @setting = @device.settings.find { |s| s.bInterfaceClass == PRINTER_INTERFACE_CLASS }
    raise "No printer-class interface on USB device" unless @setting

    @interface_number = @setting.bInterfaceNumber
    @ep_out = bulk_endpoint(out: true)
    @ep_in  = bulk_endpoint(out: false)
    raise "Bulk OUT endpoint missing" unless @ep_out

    @handle = @device.open
    @handle.auto_detach_kernel_driver = true
    @handle.claim_interface(@interface_number)

    write("\x1b@") # ESC @ -> initialize printer
  end

  # Write raw bytes. No newline added; include "\n" yourself.
  def write(text)
    @handle.bulk_transfer(endpoint: @ep_out, dataOut: text.b, timeout: 2_000)
    self
  end

  def feed(lines = 1)
    write("\x1bd" + [lines].pack("C"))
  end

  def cut
    write("\x1dV\x00")
  end

  # Read all four ESC/POS real-time status bytes and parse them.
  def read_status
    raise "Printer is unidirectional; no IN endpoint available" unless @ep_in

    s1 = real_time_status(1) # printer status
    s2 = real_time_status(2) # off-line cause
    s3 = real_time_status(3) # error cause
    s4 = real_time_status(4) # paper roll sensor

    Status.new(
      online:     (s1 & 0x08) == 0,
      paper:      paper_state(s4),
      cover_open: (s2 & 0x04) != 0,
      error:      (s3 & 0b0110_1000) != 0,
      raw:        { s1: s1, s2: s2, s3: s3, s4: s4 }
    )
  end

  def close
    begin
      @handle&.release_interface(@interface_number) if @interface_number
    rescue StandardError
      # best-effort
    end
    begin
      @handle&.close
    rescue StandardError
      # best-effort
    end
  end

  private

  def bulk_endpoint(out:)
    @setting.endpoints.find do |e|
      direction_bit_in = (e.bEndpointAddress & 0x80) != 0
      bulk             = (e.bmAttributes & 0x03) == LIBUSB::TRANSFER_TYPE_BULK
      bulk && (direction_bit_in != out)
    end
  end

  # DLE EOT n (real-time status). Returns one byte.
  def real_time_status(n)
    write("\x10\x04" + n.chr)
    @handle.bulk_transfer(endpoint: @ep_in, dataIn: 1, timeout: 1_000).bytes.first
  end

  def paper_state(s4)
    return :out      if (s4 & 0x60) != 0
    return :near_end if (s4 & 0x0c) != 0

    :ok
  end
end

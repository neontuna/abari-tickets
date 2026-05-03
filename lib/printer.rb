# frozen_string_literal: true

# Minimal driver for an ESC/POS thermal receipt printer exposed by the
# Linux usblp kernel driver as a character device (e.g. /dev/usb/lp0).
#
# Use the block form for normal print jobs. Each block is one receipt:
# the class auto-feeds + cuts when the block exits cleanly.
#
#   Printer.open do |p|
#     p.write("hello, printer!\n")
#     p.write("line two\n")
#   end   # <- feed + cut happens here
#
# This class intentionally does NOT word-wrap, format, or otherwise
# interpret the text you give it. The printer auto-wraps at its column
# boundary in hardware. Send raw text + "\n" where you want line breaks.
class Printer
  DEFAULT_DEVICE = "/dev/usb/lp0"

  # Lines to feed before cutting. The print head sits ~3-4cm above the
  # cutter, so without this the last line ends up below the cut.
  FEED_BEFORE_CUT = 6

  def self.open(device = DEFAULT_DEVICE)
    printer = new(device)
    begin
      yield printer
      printer.feed(FEED_BEFORE_CUT)
      printer.cut
    ensure
      printer.close
    end
  end

  def initialize(device = DEFAULT_DEVICE)
    @io = File.open(device, "wb")
    @io.write("\x1b@") # ESC @ -> initialize printer
  end

  # Write raw text bytes. No newline added; include "\n" yourself.
  def write(text)
    @io.write(text)
    self
  end

  # Print and feed `lines` lines (ESC d n). Public so manual users can
  # call it; the block form calls it for you before cutting.
  def feed(lines = 1)
    @io.write("\x1bd" + [lines].pack("C"))
    self
  end

  # Full cut (GS V 0). Public for the same reason as `feed`.
  def cut
    @io.write("\x1dV\x00")
    self
  end

  def close
    @io.close unless @io.closed?
  end
end

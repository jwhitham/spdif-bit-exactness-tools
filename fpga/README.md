
S/PDIF decoder FPGA experiments
===============================

These design files are made for the GHDL logic simulator and the Lattice
iCE40HX8K FPGA, which is available in the
[iceFUN module](https://www.robot-electronics.co.uk/icefun.html) from
Devantech along with various other breadboard-compatible modules.

I tested the files in GHDL using recorded S/PDIF outputs from Picoscope
as a test input. It is easier to debug most problems with a logic simulator,
and by using GHDL I was able to get the design "mostly right" before
loading it onto the FPGA. My prior FPGA experience was almost entirely
with Xilinx tools but I found that 
[Lattice iCEcube2](https://www.latticesemi.com/iCEcube2) was similar
to Xilinx ISE from a decade ago, with essentially the same process and
the same main features.

The design is able to correctly decode stereo S/PDIF at up to 96kHz
(I have no way to produce signals at a higher rate).

Components
----------

The [input decoder](input_decoder.vhdl) component decodes the incoming
"biphase mark code" signals, identifying single, double and triple-length
pulses in the S/PDIF data stream.
The single and double pulses represent binary data, while triple
pulses are used for synchronisation at the beginning of each packet.

The [packet decoder](packet_decoder.vhdl) component recognises the
start codes at the beginning of each packet. It asserts a start signal
at the beginning of the packet and a data signal for each bit.

The [channel decoder](channel_decoder.vhdl) component gathers the
data for each audio channel into a shift register and checks the parity.

All three components have their own notion of what it means to be
"synchronised". The input decoder requires pulses of valid width - the
longest pulse cannot be more than 3 times the length of the shortest pulse
(though some margin of measurement error is tolerated). The packet decoder
requires valid start codes, and the channel decoder requires correct parity.


Input decoder
-------------

I found the input decoder to be the most difficult component to debug.
The incoming pulses vary due to differences in clocking and analogue
effects, and so the timings tend to be a range, e.g. 15 .. 17 clock
cycles for a single-length pulse. The clock frequency of the FPGA
needs to be much higher than the clock frequency of the S/PDIF signal
so that there is a clearly measureable threshold to distinguish the
pulse lengths. If the clock frequency is too low, they are not clearly
distinguishable. The decoder measures the time for each pulse and
classifies it into bands, like this:

    T1 = measured shortest single-length pulse
    T2 = ceil(T1 * 1.75)
    T3 = ceil(T1 * 2.75)
    T4 = T1 * 4

    Measured time 0 .. T1-1   -> single length and adjust T1
    Measured time T1 .. T2-1  -> single length
    Measured time T2 .. T3-1  -> double length
    Measured time T3 .. T4-1  -> triple length
    Measured time T4 .. inf   -> error, force resynchronisation

Synchronisation is achieved when 7 sequential pulses can be
classified without an error. If a pulse shorter than T1 is
received, then T1 is adjusted - if the pulse is incorrect,
this will force resynchronisation because the T4 classification
becomes more likely. There is also a "watchdog" counter to detect 
situations where everything is misclassified as double or triple
length - this counter is reset by single-length pulses. It is needed
to force resynchronisation in cases where the sample rate changes
slightly.

I think it is probably possible to make a much better input decoder.
I chose 1.75 and 2.75 as multipliers rather than the more obvious
1.5 and 2.5 because T1 is the minimum pulse length rather than the
average, but this may not be the best approach.
I think the decoder ought to be able to work better at lower FPGA clock
frequencies; as it is, it was not able to decode at the 96kHz sample
rate until I increased the FPGA clock frequency above 48MHz. I think
commercial S/PDIF chipsets do not require such high frequencies.

Other issues
------------

The Lattice iCEcube2 FPGA tools don't allow the pinout constraints (PCF)
files to contain tab characters, but the open-source programming tools
do allow this. Copying the PCF from the iceFUN samples led to warnings
and a non-functional design because the pin constraints didn't work.

The FPGA has 3.3V [LVTTL](https://en.wikipedia.org/wiki/Transistor%E2%80%93transistor_logic)
interfaces, but my S/PDIF optical interface
used TTL at 5V, so I needed to level-shift the 5V interface to 3.3V.
This proved more difficult than I expected, as I have quite limited
experience with analogue electronics. I tried a voltage divider, a
[resistor-transistor logic](https://en.wikipedia.org/wiki/Resistor%E2%80%93transistor_logic)
arrangement, and then various other transistor circuits including a
[TTL gate](https://en.wikipedia.org/wiki/Transistor%E2%80%93transistor_logic#/media/File:7400_Circuit.svg),
but none of these were able to operate at the >= 3MHz speeds needed
for the S/PDIF signals. The bipolar transistors switch on within a 
few nanoseconds, but it takes thousands of nanoseconds for them to switch off,
and though the TTL circuit helps with this, it is still too slow
to be useful. I had better results using FETs, especially with this elegant
[bidirectional level-shift circuit](http://husstechlabs.com/support/tutorials/bi-directional-level-shifter/),
which was fast enough to operate with the 48kHz sample rate.
Eventually I replaced all of these with an optical receiver that
can operate at 3.3V, eliminating the need for extra interface circuitry.




S/PDIF Pico project
===================

This directory has a program for [Raspberry Pi
Pico](https://www.raspberrypi.com/documentation/microcontrollers/pico-series.html#pico-1-family)
which can receive S/PDIF inputs and check them for test patterns.

I think the program is compatible with all of the Pico 1 variants (including Pico W)
but I have not tested this. 

Unlike the [FPGA](../fpga) implementation this is only able to operate
at 44.1kHz and 48kHz. 

Usage
-----

If you have a Pico, then you only need to add an S/PDIF optical receiver module
in order to use the prebuilt firmware file: [spdif 1.uf2](spdif_1.uf2).
Connect the input to physical pin 1 (i.e. GPIO 0). See the "Hardware Interfacing"
section on the [FPGA](../fpga) page for help.

The firmware should be copied to the Pico via USB: if you're not familiar with
installing firmware on Pico, it's probably best to read about that elsewhere first,
e.g. [Getting Started](https://datasheets.raspberrypi.com/pico/getting-started-with-pico.pdf).

Then, connect to Pico using a serial terminal. On Linux this is straightforward,
a serial device named `/dev/ttyACM0` appears when the firmware is running (though not
when the device is in the bootloader, as this is not a hardware USB serial port;
it is implemented in software on the Pico). I usually open a serial terminal
by running `minicom -D /dev/ttyACM0`. You will see a message:

    Ready - press 'x' key to start, or 'r' to return to bootloader:

Use your music-playing software to play the test files
[as described on the main page](..). Press 'x' to start capture.

You should see a VU meter made with '#' characters when sound is playing,
and a message will be printed if this matches a test pattern, like this:

    Sample rate of test data: 44100 Hz
    Walking ones are perfectly correct for 16-bit
    Walking ones are perfectly correct for 24-bit
    Correct 16-bit payload part: signal is 16-bit clean
    Correct 24-bit payload part: signal is 24-bit clean


Design notes
------------

The Pico has an interesting subsystem named PIO which can be used to implement
state machines for input and output. The documentation for PIO is found
[in the RP2040 datasheet](https://datasheets.raspberrypi.com/rp2040/rp2040-datasheet.pdf),
chapter 3.

I was curious about whether PIO could be
used to implement an S/PDIF receiver. Over a few days around new year, 2024-25,
I did some experiments with this and found a way to do it. Then I added the
code for S/PDIF bit exactness checking.

My program: [spdif.pio](fw/spdio.pio) and [main.c](fw/main.c).

I hit a number of problems.

To make best use of resources, the PIO program should be able to decode
an entire packet (containing one sample, sync codes and metadata) and
then provide it via the FIFO so that it can be read by the CPU or copied
to memory by DMA. However, S/PDIF signals don't have a specific polarity,
as the transitions between levels (0->1, 1->0) convey the information, rather
than the levels themselves. Unfortunately PIO doesn't provide a way to
detect a level transition; this has to be written using multiple instructions.
Therefore, it seemed, the program had to be written twice, in order to handle
two possible cases: (1) packet starts with 0001, and (2) packet starts with 1110.

The PIO instruction memory is very small (only 32 instructions) and this
just isn't large enough to implement detectors for both polarities. I also couldn't
use two PIO state machines together, e.g. one detects level transitions and another
decodes packets, because state machines can't communicate directly, except via some
flags which cannot be used for branching - only the "WAIT" instruction can read them,
and you cannot determine how long "WAIT" has been waiting. 

Therefore I decided to just capture the symbols: pulses of length 1, 2, 3 or "invalid length",
and encode these lengths as 2-bit values which are then packed into 32-bit words and
provided to software running on the CPU. The CPU decodes the S/PDIF packets and obtains
the audio data. This works, but bandwidth requirements are very high. Two pulses of length 1
are needed to represent each "1" bit, and two bits are
needed for each pulse within my encoding scheme, so each
32-bit word from PIO may represent only 8 bits of S/PDIF data in the worst case.
With 48kHz stereo sound, the bandwidth requirement is 12.3 megabits per second.

The Pico can cope with this transfer rate, but only just. The PIO FIFO is small
(8 words when the PIO is only used for input) and this provides very little buffer
for cases when the memory bus is busy with other tasks. Even a DMA transfer is
not good enough, because there is no way to prioritise DMA over other bus usage
(e.g. by the CPU). If the CPU reads data directly, interrupts must be disabled,
because interrupts from devices such as USB can't be serviced in the time that
the PIO FIFO takes to fill up (about 20 microseconds).

With this design, it might be possible to decode the audio data in real time by using the second CPU
as a dedicated decoder. But the solution is good enough for bit-exactness checking, because
that does not require a sustained transfer of data. It's enough to capture a short
sound clip and then scan it for the test pattern (as with the
[oscilloscope](../oscilloscope) method).

Room for improvement
--------------------

I searched online and found an alternative implementation by Elehobica
[here](https://github.com/elehobica/pico_spdif_rx/tree/main) which also uses PIO
on Pico, but is more mature in several respects.

Most importantly, it relies on the insight that the polarity of S/PDIF will stay the same
between packets, because of the presence of the parity bit at the end of
each packet, which ensures that the number of '0' bits is always even.

This simplifies the design of the PIO program. Pico's GPIO pins can be [inverted
using a hardware feature](https://github.com/elehobica/pico_spdif_rx/blob/479f0c3998cc848cf7d0c9c28163cf1c8d0bdb20/spdif_rx.c#L180)
(`GPIO_OVERRIDE_INVERT`) so the PIO program can simply
assume that packets always begin with 1110. This allows each S/PDIF packet
to be represented by a single 32-word from PIO, reducing the bandwidth
requirement to 3.1 megabits per second for 48kHz stereo sound. Higher sample
rates are supported.

This is still fairly high bandwidth in Pico terms, and the PIO FIFO will still be exhausted
very quickly, and so a second feature of the Elehobica
implementation is to use 
[two DMA channels with chaining](https://github.com/elehobica/pico_spdif_rx/blob/479f0c3998cc848cf7d0c9c28163cf1c8d0bdb20/spdif_rx.c#L623).
When one DMA transfer
completes, the second begins immediately without intervention from the CPU. An
interrupt handler function is still needed to set up the next DMA transfer but
this can happen at any time during the current transfer. The interrupt handler can
also process the received data as required, and it is here that audio data may be
extracted. Subcode data can also be extracted and there is even [a fast parity check
in software](https://github.com/elehobica/pico_spdif_rx/blob/479f0c3998cc848cf7d0c9c28163cf1c8d0bdb20/spdif_rx.c#L266).

Several PIO programs are used, in order to support different sample rates (apparently
up to 192kHz). The code is identical but they use different timing constants,
which (as in my own PIO program) don't have to be exact because resynchronisation
occurs at every transition. Because of the relative simplicity of the program, it's
possible to support higher sample rates. I wasn't able to sample the S/PDIF input
faster than 25MHz because I used timing loops with a loop counter (X) and an output
value (Y) and 5 cycles were required for the loop body.
This was done in order to fit the program into the available memory (it required
all 32 words) but with use of `GPIO_OVERRIDE_INVERT` the program can rely on fixed timings
(no timing loops) and as the output is just a single bit, it is possible to shift it
either from the zero `null` register or [from a register that's been preset
to 1](https://github.com/elehobica/pico_spdif_rx/blob/479f0c3998cc848cf7d0c9c28163cf1c8d0bdb20/spdif_rx.pio#L120)
(`osr` is used for this). Therefore, sampling can also be fast enough for the really
high sample rates.

This implementation could almost certainly form the basis for an improved bit-exact
tester which supported the higher sample rates.


Artefacts
---------

- Firmware file: [spdif 1.uf2](spdif_1.uf2).




S/PDIF bit exactness testing tools
==================================

These tools can be used to check an S/PDIF output for bit-exactness.

Although music files may be lossless (e.g. FLAC), the pathway from a lossless file
to the digital output is not necessarily lossless. Loss may occur in:

- the music player software itself due to filtering or equalisation,
- the OS, e.g. due to the software mixers that allow multiple applications to play
  sound at the same time, which involves both mixing and sample rate conversion,
- the device drivers, e.g. due to poor design,
- the S/PDIF output hardware, again due to poor design.

These losses are unlikely to be audible, but they are nevertheless detectable
with appropriate tools.

Tools
=====

[siggen.c](siggen.c) generates a WAV file containing a repeated test
pattern. The test pattern consists of 40 samples with values chosen
to indicate whether an S/PDIF output is operating as a perfect passthrough
for audio data, or whether the data is being filtered, scaled, truncated
or otherwise processed in some way.

[oscilloscope/sigtest.py](sigtest.py) analyses the output of a storage oscilloscope
(represented as a CSV file) and decodes S/PDIF data. This is compared to
the expected test pattern. The program reports the results of the comparison,
indicating whether your S/PDIF output is bit-exact and whether it is 16-bit or 24-bit.

The [fpga](fpga) subdirectory contains an FPGA design for the Lattice
iCE40HX8K FPGA which will decode S/PDIF data in real time. One of the features
of this design is a subsystem which compares input to the expected test pattern
and displays the results on some LEDs, indicating whether it is 
bit-exact and whether it is 16-bit or 24-bit.


Instructions
------------

Pre-made WAV files for 44.1kHz, 48kHz and 96kHz can be found in the [examples](examples)
subdirectory. These files contain 16-bit or 24-bit audio data. You should
choose the appopriate one to match the capabilities of your S/PDIF output.

Play a test pattern WAV file using your music-playing program (use the "repeat track" mode).

Then, use one of the following methods to test the accuracy of your S/PDIF output.
Each one requires at least some special hardware.

Recording method
----------------

If you also have an S/PDIF input, loop the output to the input, and record from the
input. Then compare the recording with the test pattern WAV file using suitable
software.

For example, you could record the signal using a multitrack sound editor, then import the test pattern
WAV file as a second track. Then, zoom in so that the individual samples can be seen. Align the recording
with the test pattern by deleting samples. Use an "Invert" effect to negate the
test pattern. Then mix the test pattern and the signal together. The result should be
absolute silence (zero).

This method assumes that your S/PDIF input is bit-exact, that recording from the
output of the computer is permitted by your OS and device drivers, and that the
sound editor is able to preserve bit-exactness. Sound editors which convert to another
format for internal use (e.g. floating point) may not be bit-exact. This
method can tell you that your input and output are both bit-exact, but if they are
not, it does not determine which one is the problem.


FPGA method
-----------

See the [fpga](fpga) subdirectory for more information.


Oscilloscope method
-------------------

See the [oscilloscope](oscilloscope) subdirectory for more information.


Achieving bit-exact outputs on Windows
======================================

To get bit-exact output on Windows, consider using "Windows Audio Session API" (WASAPI).
If your music
playing software does not support this, you may need to install an output plugin, and if your
music playing software cannot do that, you'd need to switch to something else
which does, in order to achieve bit-exact output. My recommendation is
[Foobar2000](https://www.foobar2000.org/) with the
[WASAPI output plugin](https://www.foobar2000.org/components/view/foo_out_wasapi).
Disable the "dither" feature for bit-exact operation. Most of the
[example files](examples) were captured in this way.

![Foobar2000 WASAPI output configuration](/img/wasapi_24_bit.png)

Foobar2000's support for bit-exact operation is excellent once the appropriate output plugin is
installed and configured.
I have tested it extensively using different S/PDIF interfaces (USB and on-board),
different sample rates and different bit depths. The output becomes inexact if:

- the "DirectSound" output or "Primary Sound Driver" is selected;
- the volume control is not at maximum;
- ReplayGain is enabled;
- some DSP plugin is enabled.

If your S/PDIF hardware does not allow bit-exact output (for example, if it is restricted
to 48kHz, forcing resampling) then you might consider adding a USB S/PDIF device to your PC.
Some USB S/PDIF devices are better than others: devices might only support 16-bit 48kHz,
and driver support might also be bad, so order from somewhere that allows returns!

Achieving bit-exact outputs on Linux
====================================

On Linux, depending on your distribution and hardware, bit-exact may "just work". I use Debian
on my PC and the following is based on Debian 12 ("bookworm").

Without changing any default aside from turning the volume to 100%, I was able to play the 24-bit 48kHz test pattern WAV file
and get bit-exact results with various programs. I tested ![Strawberry](https://www.strawberrymusicplayer.org/),
mplayer, aplay, ![play](https://en.wikipedia.org/wiki/SoX)
and ![MPD](https://www.musicpd.org/) and
all produced bit-exact output at 48kHz. Sound is mixed by ![PipeWire](https://pipewire.org/) which is
installed and configured by default. The hardware driver is 
`snd_hda_intel` and the hardware is reported by ALSA as "Realtek ALC887-VD".

However, playing files with different sample rates was not bit-exact with PipeWire. Most likely the
sound is resampled to 48kHz, as on Windows. But unlike Windows, the mixer operates in a bit-exact
mode when there is only one sound source and the volume is 100%. S/PDIF also shuts down when nothing is playing.

If I shut down PipeWire with `systemctl --user stop pipewire-pulse`, I can configure Strawberry to
output directly via ALSA. Having done that, output is bit-exact at 44.1kHz and 96kHz: there is no resampling. 
But this carries similar disadvantages to using WASAPI on Windows, as only one program
can use the sound card at once.


Format of the test pattern
==========================

The first 24 samples consist of a pattern generated by shifting a single bit leftwards (i.e.
multiplying by 2). The left channel contains one high bit, while the right channel contains
one low bit:

    000001 fffffe
    000002 fffffd
    000004 fffffb
    000008 fffff7
    ...
    400000 bfffff
    800000 7fffff

The 25th sample contains a special marker (0x654321).

The 26th to 40th samples contain randomly-generated payload data.

The test pattern does not survive any sort of resampling, scaling, dithering
or signal processing, except for truncation from 24 bits to 16 bits.

Here is the test pattern shown in Audacity.

![Audacity screenshot](/img/wav.png)

Note that Audacity does not have
bit-exact output even when WASAPI is selected. I do not know why this is. Perhaps, internally,
it always uses some other format, e.g. single-precision floating point.


More information about S/PDIF
-----------------------------

- [Audio data format](http://www.hardwarebook.info/S/PDIF) (better than Wikipedia)
- [Subcode description](https://www.minidisc.org/spdif_c_channel.html)
- [Crystal Semiconductor Application Note 22](https://www.minidisc.org/manuals/an22.pdf) (for the
  real details)


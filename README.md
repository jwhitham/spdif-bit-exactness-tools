
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

[sigtest.py](sigtest.py) analyses the output of a storage oscilloscope
(represented as a CSV file) and decodes S/PDIF data. This is compared to
the expected test pattern. The program reports the results of the comparison,
indicating whether your S/PDIF output is bit-exact and whether it is 16-bit or 24-bit.

The [fpga](fpga) subdirectory contains an FPGA design for the Lattice
iCE40HX8K FPGA which will decode S/PDIF data in real time and compare it to the
expected test pattern. LEDs are used to report the result of the comparison,
and indicate whether the S/PDIF output is bit-exact and whether it is 16-bit or 24-bit.


Instructions
------------

Pre-made WAV files for 44.1kHz and 48kHz can be found in the [examples](examples)
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

For example, you could record the signal using Audacity, then import the test pattern
WAV file, then zoom in so that the individual samples can be seen. Align the recording
with the test pattern by deleting samples. Then use "Effects -> Invert" to negate the
test pattern. Then mix the test pattern and the signal together. The result should be
absolute silence (zero).

This method assumes that your S/PDIF input is bit-exact and that recording from the
output of the computer is permitted by your OS and device drivers. Therefore, this
method can tell you that your input and output are both bit-exact, but if they are
not, it does not determine which one is the problem.


FPGA method
-----------

See the [fpga](fpga) subdirectory for more information.


Oscilloscope method
-------------------

Capture the electrical signals on the S/PDIF output using a storage oscilloscope
such as [Picoscope](https://www.picotech.com/products/oscilloscope).
You will need to record for at least 1ms in order to capture
more than 40 audio samples. The oscilloscope sample rate should be as high as possible
while still capturing samples for 1ms. I got good results with a sample rate of 12.5MHz
(a sample interval of 80ns).

![Picoscope screenshot](/examples/osc.png)

Export the oscilloscope recording as a CSV file.

Run the [sigtest.py](sigtest.py) program on the CSV file, e.g.

    python sigtest.py c:\temp\20220410-0001.csv

If your S/PDIF output is 24-bit and you have configured your device drivers and
music player software so that audio data is passed through exactly,
then you will see something like this:

    > python sigtest.py examples\test_44100_24_bit.csv
    Oscilloscope clock period 0.080 microseconds
    Oscilloscope clock frequency 12.500 MHz
    Signal peak-to-peak: -8.493 to 66.012
    Signal midpoint: 28.674
    hold_time width 2 has count 1743
    hold_time width 3 has count 472
    hold_time width 4 has count 864
    hold_time width 5 has count 652
    hold_time width 6 has count 47
    hold_time width 7 has count 86
    S/PDIF clock frequency 3.125 MHz
    width0 2
    width1 4
    width2 6
    resync at 32
    Packets 89
    Malformed packet - wrong size (skip)
    Audio data received:
    257600 7d5600
    ...
    f66900 51f300
    b61800 1d7600
    4dc100 db5e00
    Sample rate of test data: 44100 Hz
    Walking ones are perfectly correct for 16-bit
    Walking ones are perfectly correct for 24-bit
    Correct 16-bit payload part: signal is 16-bit clean
    Correct 24-bit payload part: signal is 24-bit clean

If your S/PDIF output is limited to 16 bits by hardware, but all other configuration
is correct, then messages similar to the following will be shown:

    > python sigtest.py examples\test_44100_16_bit.csv
    ...
    Sample rate of test data: 44100 Hz
    Walking ones are correct for 16-bit with at most +/- 1 bit error
    Correct 16-bit payload part: signal is 16-bit clean
    at 32 (24-bit): expect e3b30d 0c8faf  got e3b300 0c9000
    Error in 24-bit payload part, position 32: signal is not 24-bit clean

If you have not successfully captured S/PDIF data with your oscilloscope,
or your CSV file format is incorrect, then you will see error messages
from sigtest.py. Ensure that a clear waveform is captured for sufficient time.
If you are not using Picoscope, you may need to replace the
[picoscope\_decode.py](picoscope_decode.py) method with something
appropriate for your oscilloscope's output format.


If your configuration is incorrect, then the output may be processed in various ways
by your music player software, the OS, or device drivers. In this case you
will see some audio data, but it won't be a bit-exact copy of the test pattern.

The sigtest.py program will print messages such as:

    Unable to find the 654321 marker within the audio data

This either means that the output is not bit-exact, or that the test WAV file was not
playing. In some cases you can also see a hint about the problem, like this:

    Unable to find the 654321 marker within the audio data
    Possible marker at position 6 with volume level reduced to 0.985: sample rate 44042 Hz ?

This is typical of the output seen when playing the WAV file on Windows via the
"shared mode" audio pathway, which is the default. This is often called
"Primary Sound Driver" and/or "Windows DirectSound". It occurs even if volume controls
are turned to maximum. [One of the example files](examples/test_44100_ds.csv) was captured
in this way.

If you do not see this second message, Windows might be resampling the audio data to
a higher sample rate. Try the 48kHz test pattern, as the default Windows configuration
resamples all sounds to 16-bit 48kHz.

Achieving bit-exact outputs
===========================

To get bit-exact output on Windows, consider using "Windows Audio Session API" (WASAPI). If your music
playing software does not support this, you may need to install an output plugin, and if your
music playing software cannot do that, you'd need to switch to something else
which does, in order to achieve bit-exact output. My recommendation is
[Foobar2000](https://www.foobar2000.org/) with the
[WASAPI output plugin](https://www.foobar2000.org/components/view/foo_out_wasapi).
Disable the "dither" feature for bit-exact operation. Most of the
[example files](examples) were captured in this way.

Foobar2000's support for bit-exact operation is excellent, once the appropriate output plugin is installed.
I have tested it extensively using different S/PDIF interfaces (USB and on-board),
different sample rates and different bit depths. The output becomes inexact if:

- the "DirectSound" output or "Primary Sound Driver" is selected;
- the volume control is not at maximum;
- some DSP plugin is enabled.

If your S/PDIF hardware does not allow bit-exact output (for example, if it is restricted
to 48kHz, forcing resampling) then you might consider adding a USB S/PDIF device to your PC.


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

![Picoscope screenshot](/examples/wav.png)

Note that Audacity does not have
bit-exact output even when WASAPI is selected. I do not know why this is. Perhaps, internally,
it always uses some other format, e.g. single-precision floating point.


More information about S/PDIF
-----------------------------

- [Audio data format](http://www.hardwarebook.info/S/PDIF) (better than Wikipedia)
- [Subcode description](https://www.minidisc.org/spdif_c_channel.html)
- [Crystal Semiconductor Application Note 22](https://www.minidisc.org/manuals/an22.pdf) (for the
  real details)


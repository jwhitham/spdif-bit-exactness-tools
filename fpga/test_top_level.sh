#!/bin/bash

set -ex

export PATH=/j/GHDL/0.37-mingw32-mcode/bin:$PATH

python make_test_bench.py
python make_match_rom.py
rm -f work-obj93.cf

for F in \
            match_rom \
            matcher \
            clock_regenerator \
            sb_ram40_4k \
            fifo \
            output_encoder \
            packet_encoder \
            test_signal_generator \
            input_decoder \
            packet_decoder \
            channel_decoder \
            channel_encoder \
            test_top_level
do
    ghdl -a $F.vhdl
    ghdl -e $F
done
ghdl -r test_top_level


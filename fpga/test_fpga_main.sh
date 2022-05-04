#!/bin/bash

set -ex

export PATH=/j/GHDL/0.37-mingw32-mcode/bin:$PATH

python make_test_bench.py
rm -f work-obj93.cf

for F in test_signal_generator \
            vu_meter \
            input_decoder \
            packet_decoder \
            channel_decoder \
            led_scan \
            fpga_main \
            test_fpga_main
do
    ghdl -a $F.vhdl
    ghdl -e $F
done
ghdl -r test_fpga_main


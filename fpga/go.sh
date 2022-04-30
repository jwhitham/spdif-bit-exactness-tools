#!/bin/bash

set -ex

export PATH=/j/GHDL/0.37-mingw32-mcode/bin:$PATH

for F in test_signal_generator.vhdl \
            input_decoder.vhdl \
            test_top_level.vhdl
do
    ghdl -a $F
    ghdl -e $F
done
ghdl -r test_top_level


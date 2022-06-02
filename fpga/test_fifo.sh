#!/bin/bash

set -ex

export PATH=/j/GHDL/0.37-mingw32-mcode/bin:$PATH

rm -f work-obj93.cf

for F in \
            sb_ram512x8 \
            fifo512x8 \
            test_fifo512x8
do
    ghdl -a $F.vhdl
    ghdl -e $F
done
ghdl -r test_fifo512x8


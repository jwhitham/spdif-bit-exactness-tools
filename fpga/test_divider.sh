#!/bin/bash

set -ex

export PATH=/j/GHDL/0.37-mingw32-mcode/bin:$PATH

rm -f work-obj93.cf

for F in \
            divider \
            test_divider
do
    ghdl -a $F.vhdl
    ghdl -e $F
done
ghdl -r test_divider


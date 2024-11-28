#!/bin/bash -xe

set -xe
export PATH=/opt/oss-cad-suite/bin:/opt/ghdl/bin:$PATH
make compressor_main.bin


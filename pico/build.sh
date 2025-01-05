#!/bin/bash -xe

export PICO_SDK_PATH=~/Projects/rpi-pico/pico-sdk

mkdir -p build
cd build
cmake -DPICO_BOARD=pico ..
make



#!/bin/bash

set -xe
gcc -o ../siggen.exe ../siggen.c -Wall -Werror -g  -O
for sample_rate in 44100 48000 96000
do
    for bits in 16 24
    do
        wav_fname=test_${sample_rate}_${bits}_bit.wav
        rm -f $wav_fname $wav_fname.zip
        ../siggen.exe $sample_rate $bits $wav_fname
        zip -9 $wav_fname.zip $wav_fname
    done
done

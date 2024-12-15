#ifndef PACKETGEN_H
#define PACKETGEN_H

#include <stdint.h>
#include <stdbool.h>

uint64_t packetgen_build_bits(uint64_t data);
bool packetgen_build_samples(const size_t num_packets, const uint64_t* packet_data,
                             int16_t** sample_data, size_t* sample_count);

#endif

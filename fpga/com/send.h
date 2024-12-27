#pragma once
#include <objbase.h>
#include <stdint.h>

HRESULT comSend(const uint32_t numPackets, const uint64_t* packetData);

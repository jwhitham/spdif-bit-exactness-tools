
import collections
import enum
import typing


RawDigitalSignal = typing.List[bool]
RawSPDIFPackets = typing.List[typing.List[bool]] 
RawSubcodeData = typing.List[bool]

class Sample:
    left = 0
    right = 0

AudioData = typing.List[Sample]

class SyncState(enum.Enum):
    NONE = enum.auto()
    START = enum.auto()
    B_HEADER = enum.auto()
    M_HEADER = enum.auto()
    W_HEADER = enum.auto()
    B_FOOTER = enum.auto()
    M_FOOTER = enum.auto()
    W_FOOTER = enum.auto()
    DESYNC = enum.auto()

B_PACKET = [True, False, False, False]
M_PACKET = [False, False, True, False]
W_PACKET = [False, True, False, False]


def biphase_mark_decode(digital: RawDigitalSignal, osc_period: float) -> RawSPDIFPackets:
    # Get S/PDIF clock pulse width
    hold_time = -len(digital)
    hold_time_histogram: typing.Dict[int, int] = collections.defaultdict(lambda: 0)
    max_hold_time = 0
    for i in range(1, len(digital)):
        if digital[i] == digital[i - 1]:
            hold_time += 1
        else:
            hold_time_histogram[hold_time] += 1
            max_hold_time = max(hold_time, max_hold_time)
            hold_time = 1

    for (hold_time, count) in sorted(hold_time_histogram.items()):
        if hold_time > 0:
            print("hold_time width {} has count {}".format(hold_time, count))

    best_score = -1
    best_hold_time = 1
    for hold_time in range(1, max_hold_time):
        peak0 = (hold_time_histogram.get(hold_time - 1, 0)
                + hold_time_histogram.get(hold_time, 0))
        peak1 = (hold_time_histogram.get(hold_time * 2 , 0)
                + hold_time_histogram.get(hold_time * 2 + 1, 0))

        score = peak0 + peak1
        #print("hold time {} has score {}".format(hold_time, score))
        if score > best_score:
            best_score = score
            best_hold_time = hold_time

    # What's the S/PDIF bit rate? (Time to send a single bit)
    spdif_period = best_hold_time * osc_period * 2
    spdif_freq = 1.0 / spdif_period
    print("S/PDIF clock frequency {:1.3f} MHz".format(spdif_freq / 1e6))

    # Thresholds for longer pulses
    width1 = ((best_hold_time * 2) - 0)
    width2 = ((best_hold_time * 3) - 0)
    print("width0", best_hold_time)
    print("width1", width1)
    print("width2", width2)

    # Get binary data
    pulse = -len(digital)
    packets: RawSPDIFPackets = [[]]
    skip = False
    inhibit = False
    sync_state = SyncState.DESYNC

    for i in range(1, len(digital)):
        if digital[i] == digital[i - 1]:
            pulse += 1
        else:
            if sync_state == SyncState.NONE:
                if pulse >= width2:
                    # Synchronisation mark
                    sync_state = SyncState.START
                elif pulse >= width1:
                    # Ordinary data (0)
                    packets[-1].append(False)
                    skip = False
                else:
                    # Ordinary data (1)
                    if not skip:
                        packets[-1].append(True)
                        skip = True
                    else:
                        skip = False

            elif sync_state == SyncState.START:
                if pulse >= width2:
                    sync_state = SyncState.M_HEADER # 111000 received, 10 remaining
                elif pulse >= width1:
                    sync_state = SyncState.W_HEADER # 11100 received, 100 remaining
                else:
                    sync_state = SyncState.B_HEADER # 1110 received, 1000 remaining

            elif sync_state == SyncState.M_HEADER:
                if pulse >= width1:
                    sync_state = SyncState.DESYNC   # expected 10
                else:
                    sync_state = SyncState.M_FOOTER # 0 remaining

            elif sync_state == SyncState.W_HEADER:
                if pulse >= width1:
                    sync_state = SyncState.DESYNC   # expected 100
                else:
                    sync_state = SyncState.W_FOOTER # 00 remaining
                
            elif sync_state == SyncState.B_HEADER:
                if pulse >= width1:
                    sync_state = SyncState.DESYNC   # expected 1000
                else:
                    sync_state = SyncState.B_FOOTER # 000 remaining

            elif sync_state == SyncState.M_FOOTER:
                if pulse >= width1:
                    sync_state = SyncState.DESYNC   # expected 0
                else:
                    sync_state = SyncState.NONE
                    packets.append(M_PACKET[:])

            elif sync_state == SyncState.W_FOOTER:
                if (pulse < width1) or (pulse >= width2):
                    sync_state = SyncState.DESYNC   # expected 00
                else:
                    sync_state = SyncState.NONE
                    packets.append(W_PACKET[:])
                
            elif sync_state == SyncState.B_FOOTER:
                if pulse < width2:
                    sync_state = SyncState.DESYNC   # expected 000
                else:
                    sync_state = SyncState.NONE
                    packets.append(B_PACKET[:])

            elif sync_state == SyncState.DESYNC:
                if pulse >= width2:
                    # Synchronisation mark
                    sync_state = SyncState.START
                    print("resync at", i)

            pulse = 1

    print("Packets", len(packets))
    return packets

def spdif_decode(packets: RawSPDIFPackets) -> typing.Tuple[AudioData, RawSubcodeData]:
    output: AudioData = []
    subcode: RawSubcodeData = []
    channel = 0
    for packet in packets:
        if len(packet) < 32:
            print("Malformed packet - wrong size (skip)")
            continue

        if packet[:4] == B_PACKET:
            subcode.clear()
            output.append(Sample())
            channel = 0
        elif packet[:4] == M_PACKET:
            output.append(Sample())
            channel = 0
        elif packet[:4] == W_PACKET:
            if len(output) == 0:
                print("Await B/M packet (skip)")
                continue
            channel += 1
        else:
            print("Malformed packet - wrong sync bits (skip)")
            continue

        # Audio data here (24 bits)
        audio = 0
        for i in range(27, 3, -1):
            audio = audio << 1
            if packet[i]:
                audio |= 1

        if channel == 0:
            output[-1].left = audio
        elif channel == 1:
            output[-1].right = audio

        # Validity
        if packet[28]:
            print("invalid bit is set")

        # Subcode/status bit
        if packet[29]:
            print("bit 29 is set")

        if channel == 0:
            subcode.append(packet[30])

        # Parity
        count = 0
        for p in packet[4:32]:
            if p:
                count += 1

        if (count % 2) != 0:
            print("parity error detected")

    return (output, subcode)


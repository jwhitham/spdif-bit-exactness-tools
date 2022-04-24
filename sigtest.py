
import sys
from picoscope_decode import picoscope_decode
from spdif_decode import biphase_mark_decode, spdif_decode, AudioData


PAYLOAD = [
    0xc6, 0x4e, 0x65, 0x5e, 0x25, 0x76, 0x7d, 0x56, 0xf6, 0x69, 0x51, 0xf3,
    0xb6, 0x18, 0x1d, 0x76, 0x4d, 0xc1, 0xdb, 0x5e, 0x40, 0xd9, 0x9e, 0x0d,
    0x50, 0x8a, 0x48, 0xdd, 0xe3, 0xb3, 0x0d, 0x0c, 0x8f, 0xaf, 0xaf, 0xe6,
    0x5e, 0x41, 0x95, 0xb3, 0x66, 0x70, 0x01, 0x40, 0x81, 0x7f, 0x24, 0xda,
    0xf1, 0xeb, 0xf8, 0xc9, 0x5a, 0x20, 0xc9, 0x75, 0xc3, 0xea, 0xd0, 0x96,
    0x1c, 0x8d, 0xe3, 0xb3, 0x8f, 0xb4, 0x08, 0xcf, 0xb5, 0x55, 0xea, 0x6d,
    0x66, 0x3e, 0x48, 0x74, 0xec, 0x54, 0x5b, 0x0f, 0xf4, 0x01, 0x20, 0x3c,
    0x18, 0x52, 0x8c, 0xda, 0x9a, 0x00, 0x9a, 0xa2, 0x38, 0xbb, 0x69, 0x74,
    0xae, 0x80, 0x6a, 0xc5, 0x59, 0x62, 0xd1, 0x80, 0xc9, 0x1e, 0xd2, 0x5d,
    0x69, 0x35, 0x06, 0x4e, 0xae, 0x62, 0xb1, 0xab, 0x35, 0x35, 0xcc, 0x54,
    0x35, 0xb9, 0xff, 0x91, 0xa5, 0x58, 0x62, 0xf8
]

TRUE_MARKER_POSITION = 24
MARKER_VALUE = 0x654321
MARKER_MASK = 0xfff000
REPEAT_SIZE = 40
MASK_16 = 0xffff00

def examine_packet(audio: AudioData) -> bool:
    # Find the marker
    marker_position = -1
    for i in range(len(audio)):
        if (audio[i].right & MARKER_MASK) == (MARKER_VALUE & MARKER_MASK):
            marker_position = i
            break

    if marker_position < 0:
        print("Unable to find the {:06x} marker within the audio data".format(
                MARKER_VALUE))
        return False

    if len(audio) < REPEAT_SIZE:
        print("Insufficient samples captured (need at least {})".format(REPEAT_SIZE))
        return False

    # Rearrange data
    samples: AudioData = []
    for i in range(REPEAT_SIZE):
        j = i + marker_position - TRUE_MARKER_POSITION
        if j < 0:
            j += REPEAT_SIZE
        if j >= len(audio):
            j -= REPEAT_SIZE
        assert 0 <= j < len(audio)

        samples.append(audio[j])

    assert (samples[TRUE_MARKER_POSITION].right & MARKER_MASK) == (MARKER_VALUE & MARKER_MASK)
    print("Sample rate of test data: {} Hz".format((samples[TRUE_MARKER_POSITION].left >> 8) * 100))

    # Check walking 1s
    incorrect = -1
    for i in range(24):
        left = 1 << i
        right = left ^ 0xffffff
        if (samples[i].left != left) or (samples[i].right != right):
            incorrect = i

    print("{} walking 1s are correct ({} exact bits)".format(23 - incorrect, 23 - incorrect))

    if incorrect >= 8:
        print("Error in 'walking ones' payload part: signal is not 16-bit clean.")
        return False

    # Check third part of the repeating block: 16 bit data (7 samples)
    j = 0
    for i in range(25, 32):
        left =  (PAYLOAD[j + 0] << 16) | (PAYLOAD[j + 1] << 8)
        right = (PAYLOAD[j + 2] << 16) | (PAYLOAD[j + 3] << 8)
        if (((samples[i].left & MASK_16) != left) or ((samples[i].right & MASK_16) != right)):
            print("Error in 16-bit payload part, position {}: signal is not 16-bit clean".format(i))
            return False
        j += 4

    print("Correct 16-bit payload part: signal is 16-bit clean")

    # Final part of the repeating block: 24 bit data (8 samples)
    for i in range(32, REPEAT_SIZE):
        left =  (PAYLOAD[j + 0] << 16) | (PAYLOAD[j + 1] << 8) | (PAYLOAD[j + 2] << 0)
        right = (PAYLOAD[j + 3] << 16) | (PAYLOAD[j + 4] << 8) | (PAYLOAD[j + 5] << 0)
        if ((samples[i].left != left) or (samples[i].right != right)):
            print("Error in 24-bit payload part, position {}: signal is not 24-bit clean".format(i))
            print("{} walking 1s are correct (< 24 exact bits)".format(23 - incorrect))
            return False
        j += 6

    if incorrect < 0:
        print("Correct 24-bit payload part: signal is 24-bit clean")
    else:
        print("Correct 24-bit payload part but error in walking ones: signal is not 24-bit clean")

    return True

def main() -> None:
    if len(sys.argv) != 2:
        print("Usage: sigtest.py <input.csv>")
        sys.exit(1)

    (digital, osc_period) = picoscope_decode(sys.argv[1])
    packets = biphase_mark_decode(digital, osc_period)
    (audio, subcode_data) = spdif_decode(packets)

    print("Audio data received:")
    for sample in audio:
        print("{:06x} {:06x}".format(sample.left, sample.right))

    examine_packet(audio)


if __name__ == "__main__":
    main()

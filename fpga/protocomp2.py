
import collections
import struct
import math

def decibel(x):
    return math.pow(10.0, x / 10.0)

SAMPLE_RATE = 44100
PEAK = 0x7fff
FORMAT = "<hh"

# how quickly the compression recovers to full volume (decibels per second)
DECAY = decibel(-1 / SAMPLE_RATE)

# sounds below this amplitude are amplified as if they are at this amplitude
THRESHOLD = decibel(-40)

# intended amplitude for output
AIM_FOR = decibel(-1)

# digital delay length sets the ability to see the future
FIFO_SIZE = int(SAMPLE_RATE * 0.01)


class Processor:
    def __init__(self) -> None:
        self.in_fifo = collections.deque()
        self.peak = THRESHOLD

    def add(self, sample_in):
        self.in_fifo.append(sample_in)

        (left, right) = struct.unpack(FORMAT, sample_in)
        abs_level = max(abs(left), abs(right)) / PEAK
        if abs_level > self.peak:
            # Reduce the volume
            self.peak = abs_level
        else:
            # Allow the volume to increase again
            self.peak = self.peak * DECAY
        
        self.peak = max(self.peak, THRESHOLD)

        if len(self.in_fifo) >= FIFO_SIZE:
            return self.remove()
        else:
            return b""

    def remove(self):
        if len(self.in_fifo) == 0:
            return b""

        sample_in = self.in_fifo.popleft()
        (left, right) = struct.unpack(FORMAT, sample_in)

        left = max(-PEAK, min(int(left * AIM_FOR / self.peak), PEAK))
        right = max(-PEAK, min(int(right * AIM_FOR / self.peak), PEAK))

        return struct.pack(FORMAT, left, right)
            

def main():
    p = Processor()
    with open("comp.wav", "wb") as fd_out:
        with open("l2.wav", "rb") as fd_in:
            fd_out.write(fd_in.read(0x2c)) # header
            block_in = fd_in.read(1 << 16)
            while len(block_in) > 0:
                block_out = []
                for i in range(0, len(block_in), 4):
                    block_out.append(p.add(block_in[i:i+4]))

                fd_out.write(b''.join(block_out))
                block_in = fd_in.read(1 << 16)
        
        end = p.remove()
        while len(end) != 0:
            fd_out.write(end)
            end = p.remove()

if __name__ == "__main__":
    main()

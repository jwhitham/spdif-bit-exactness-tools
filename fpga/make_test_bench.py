
import typing, enum, struct

GAP = 1e5                       # nanoseconds - gap between test files
SINGLE = 1e9 / (44100 * 128)    # nanoseconds - length of single pulse

class HeaderType(enum.Enum):
    B = enum.auto()
    W = enum.auto()
    M = enum.auto()

def read_csv_file(csv_file_name: str, state_change_time: typing.List[float]) -> None:

    # Read raw data
    analogue: typing.List[float] = []
    times: typing.List[float] = []
    time_scale = 1e-6 * 1e9
    for line in open(csv_file_name, "rt"):
        fields = line.rstrip().split(",")
        try:
            t = float(fields[0])
            v = float(fields[1])
        except Exception:
            if line.startswith("(ms)"):
                time_scale = 1e-3 * 1e9
            elif line.startswith("(us)"):
                time_scale = 1e-6 * 1e9
            elif line.startswith("(ns)"):
                time_scale = 1e-9 * 1e9

            continue

        times.append(t)
        analogue.append(v)
        t0 = t


    # Digitise, convert to BMC
    average = sum(analogue) / len(analogue)
    threshold1 = average * 1.1
    threshold0 = average / 1.1
    t0 = (times[0] * time_scale) - GAP
    state = state0 = False
    for i in range(len(analogue)):
        if analogue[i] > threshold1:
            state = True
        elif analogue[i] < threshold0:
            state = False

        if state != state0:
            # Record state change time
            t = times[i] * time_scale
            state_change_time.append(max(1.0, t - t0))
            t0 = t
            state0 = state

def bmc_packetise(audio: int, header: HeaderType, state_change_time: typing.List[float]) -> None:
    bits = 0
    data = (audio >> 8)

    # determine parity
    copy = data
    for i in range(28):
        if copy & 1:
            data ^= 1 << 27
        copy = copy >> 1

    # encoded signal
    state_change_time.append(SINGLE * 3)
    if header == HeaderType.B:
        state_change_time.append(SINGLE * 1)
        state_change_time.append(SINGLE)
        state_change_time.append(SINGLE * 3)
    elif header == HeaderType.W:
        state_change_time.append(SINGLE * 2)
        state_change_time.append(SINGLE)
        state_change_time.append(SINGLE * 2)
    elif header == HeaderType.M:
        state_change_time.append(SINGLE * 3)
        state_change_time.append(SINGLE)
        state_change_time.append(SINGLE * 1)

    for i in range(28):
        if data & 1:
            state_change_time.append(SINGLE)
            state_change_time.append(SINGLE)
        else:
            state_change_time.append(SINGLE * 2)
        data = data >> 1

def print_banner(fd: typing.IO, banner: str) -> None:
    fd.write("""write (l, String'("{}")); writeline (output, l);\n""".format(banner))

def print_data(fd: typing.IO, state_change_time: typing.List[float]) -> None:
    for td in state_change_time:
        fd.write("wait for {:1.0f} ns; ".format(td))
        fd.write("r <= not r;\n")

def wav_to_test_data(fd: typing.IO, wav_file_name: str, rounding: bool) -> None:
    state_change_time: typing.List[float] = []
    with open(wav_file_name, "rb") as fd2:
        fd2.seek(0x2c, 0) # skip to start of data
        for i in range(200):
            # Read two 32-bit samples
            (left, right) = struct.unpack("<II", fd2.read(8))
            if rounding:
                # Round to 16 bits
                left = round(left / (1 << 16)) << 16
                right = round(right / (1 << 16)) << 16

            if (i % 100) == 0:
                # Use a B header for the left channel, W for right
                bmc_packetise(left, HeaderType.B, state_change_time)
                bmc_packetise(right, HeaderType.W, state_change_time)
            else:
                # Use a M header for the left channel, W for right
                bmc_packetise(left, HeaderType.M, state_change_time)
                bmc_packetise(right, HeaderType.W, state_change_time)

    state_change_time.append(GAP)
    print_banner(fd, "Start of {} with rouding = {}".format(wav_file_name, rounding))
    print_data(fd, state_change_time)

def csv_to_test_data(fd: typing.IO, csv_file_name: str) -> None:
    state_change_time: typing.List[float] = []
    read_csv_file(csv_file_name, state_change_time)
    state_change_time.append(GAP)
    print_banner(fd, "Start of " + csv_file_name)
    print_data(fd, state_change_time)

def main() -> None:
    # generate test bench
    with open("test_signal_generator.vhdl", "wt") as fd:
        fd.write(f"""
library ieee;
use ieee.std_logic_1164.all;

use std.textio.all;

entity test_signal_generator is
    port (
        done_out        : out std_logic;
        clock_out       : out std_logic;
        raw_data_out    : out std_logic
    );
end test_signal_generator;

architecture structural of test_signal_generator is
    signal done     : std_logic := '0';
    signal r        : std_logic := '0';
    signal clock    : std_logic := '0';
begin
    done_out <= done;
    raw_data_out <= r;
    clock_out <= clock;

    process
    begin
        while done = '0' loop
            clock <= '1';
            wait for 10 ns;
            clock <= '0';
            wait for 10 ns;
        end loop;
        wait;
    end process;

    process
        variable l : line;
    begin
        r <= '0';
        done <= '0';
""")
        # read input files
        csv_to_test_data(fd, "20220502-32k.csv")
        csv_to_test_data(fd, "20220502-44k.csv")
        csv_to_test_data(fd, "20220502-48k.csv")
        csv_to_test_data(fd, "../examples/test_48000.csv")
        csv_to_test_data(fd, "../examples/test_44100.csv")
        wav_to_test_data(fd, "../test_44100.wav", False)
        wav_to_test_data(fd, "../test_44100.wav", True)

        fd.write("""
        done <= '1';
        wait;
    end process;
end structural;
""")

if __name__ == "__main__":
    main()


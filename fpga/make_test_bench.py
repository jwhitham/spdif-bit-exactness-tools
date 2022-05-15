
import typing

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
    t0 = (times[0] * time_scale) - 1000.0
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

def main() -> None:
    # read input files
    state_change_time: typing.List[float] = []
    read_csv_file("20220502-32k.csv", state_change_time)
    read_csv_file("20220502-44k.csv", state_change_time)
    read_csv_file("20220502-48k.csv", state_change_time)
    read_csv_file("../examples/test_48000.csv", state_change_time)
    read_csv_file("../examples/test_44100.csv", state_change_time)
    state_change_time.append(1000)
    state_change_time.append(1000)
    state_change_time.append(1000)

    # generate test bench
    with open("test_signal_generator.vhdl", "wt") as fd:
        fd.write(f"""
library ieee;
use ieee.std_logic_1164.all;

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
    begin
        r <= '0';
        done <= '0';
""")
        data = 0
        for td in state_change_time:
            fd.write("wait for {:1.0f} ns; ".format(td))
            fd.write("r <= '{:d}';\n".format(data))
            data = 1 - data

        fd.write("""
        done <= '1';
        wait;
    end process;
end structural;
""")

if __name__ == "__main__":
    main()


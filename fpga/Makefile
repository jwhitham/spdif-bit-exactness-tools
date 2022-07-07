
RFLAGS = --assert-level=note

VHDL =  \
		lib/divider.vhdl \
		lib/fifo.vhdl \
		lib/led_scan.vhdl \
		app/compressor/compressor.vhdl \
		app/matcher/match_rom.vhdl \
		app/matcher/matcher.vhdl \
		app/vu_meter/vu_meter.vhdl \
		spdif/channel_decoder.vhdl \
		spdif/channel_encoder.vhdl \
		spdif/clock_regenerator.vhdl \
		spdif/input_decoder.vhdl \
		spdif/output_encoder.vhdl \
		spdif/packet_decoder.vhdl \
		spdif/packet_encoder.vhdl \
		projects/spdif_meter/spdif_meter_main.vhdl \

TEST_VHDL = \
		test/sb_ram40_4k.vhdl \
		test/generated/test_signal_generator.vhdl \
		test/test_compressor.vhdl \
		test/test_compressor2.vhdl \
		test/test_divider.vhdl \
		test/test_fifo.vhdl \
		test/test_spdif_meter_main.vhdl \
		test/test_top_level.vhdl

all: run_tests

clean:
	ghdl --remove

run_tests:
	ghdl --remove
	python app/matcher/make_match_rom.py
	python test/make_test_bench.py
	ghdl -a --work=work $(VHDL) $(TEST_VHDL)
	ghdl -r test_fifo $(RFLAGS)
	ghdl -r test_divider $(RFLAGS)
	ghdl -r test_compressor $(RFLAGS)
	ghdl -r test_compressor2 $(RFLAGS)
	ghdl -r test_spdif_meter_main $(RFLAGS)
	ghdl -r test_top_level $(RFLAGS) > tmp.txt
	diff -q tmp.txt test/test_top_level_out.txt
	echo "tests ok"

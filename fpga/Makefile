
VHDL =  app/compressor/compressor.vhdl \
		app/matcher/match_rom.vhdl \
		app/matcher/matcher.vhdl \
		app/vu_meter/vu_meter.vhdl \
		fpga_main.vhdl \
		lib/divider.vhdl \
		lib/fifo.vhdl \
		lib/led_scan.vhdl \
		spdif/channel_decoder.vhdl \
		spdif/channel_encoder.vhdl \
		spdif/clock_regenerator.vhdl \
		spdif/input_decoder.vhdl \
		spdif/output_encoder.vhdl \
		spdif/packet_decoder.vhdl \
		spdif/packet_encoder.vhdl \
		spdif_meter.vhdl

TEST_VHDL = \
		test/sb_ram40_4k.vhdl \
		test/generated/test_signal_generator.vhdl \
		test/test_compressor.vhdl \
		test/test_compressor2.vhdl \
		test/test_divider.vhdl \
		test/test_fifo.vhdl \
		test/test_fpga_main.vhdl \
		test/test_top_level.vhdl

all: run_tests

clean:
	ghdl --remove

run_tests:
	ghdl --remove
	python test/make_test_bench.py
	ghdl -a $(VHDL) $(TEST_VHDL)
	ghdl -r test_fifo
	ghdl -r test_divider
	ghdl -r test_compressor
	ghdl -r test_compressor2
	ghdl -r test_fpga_main
	ghdl -r test_top_level > tmp.txt
	diff tmp.txt test/test_top_level_out.txt

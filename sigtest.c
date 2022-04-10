#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>


typedef struct t_header {
    uint8_t     fixed_riff[4];      // 0
    uint32_t    file_size;          // 4
    uint8_t     fixed_wave[4];      // 8
    uint8_t     fixed_fmt[4];       // c
    uint32_t    length_of_format_data;  // 10
    uint16_t    type_of_format;         // 14
    uint16_t    number_of_channels;     // 16
    uint32_t    sample_rate;            // 18
    uint32_t    bytes_per_second;       // 1c
    uint16_t    bytes_per_sample;       // 20
    uint16_t    bits_per_sample;        // 22
    uint8_t     fixed_data[4];          // 24
    uint32_t    data_size;              // 28
} t_header;

typedef struct t_stereo {
    int32_t     left;
    int32_t     right;
} t_stereo;


int main(int argc, char ** argv)
{
    FILE *          fd_in;
    FILE *          fd_out;
    t_header        header;
    const uint32_t  data_size = 258;
    uint8_t         test_data[data_size];
    t_stereo        samples[(data_size / 6) + 1];
    const uint32_t  block_size = sizeof(samples) / sizeof(t_stereo);
    const uint32_t  sample_rate = 48000;
    const uint32_t  num_blocks = (sample_rate * 2 * 60) / block_size;
    const uint32_t  num_samples = num_blocks * block_size;
    uint32_t        i;

    fd_in = fopen("test.bin", "rb");
    if (!fd_in) {
        perror("open (read)");
        return 1;
    }
    if (fread(test_data, data_size, 1, fd_in) != 1) {
        perror("read");
        return 1;
    }
    fclose(fd_in);

    fd_out = fopen("test.wav", "wb");
    if (!fd_out) {
        perror("open (write)");
        return 1;
    }
    memset(&header, 0, sizeof(header));
    memcpy(header.fixed_riff, "RIFF", 4);
    memcpy(header.fixed_wave, "WAVE", 4);
    memcpy(header.fixed_fmt, "fmt ", 4);
    header.length_of_format_data = 16;
    header.type_of_format = 1; // WAVE_FORMAT_PCM
    header.number_of_channels = 2;
    header.sample_rate = sample_rate;
    header.bytes_per_second = header.sample_rate * sizeof(t_stereo);
    header.bytes_per_sample = sizeof(t_stereo) / 2;
    header.bits_per_sample = header.bytes_per_sample * 8;
    memcpy(header.fixed_data, "data", 4);
    header.data_size = num_samples * sizeof(t_stereo);
    header.file_size = header.data_size + sizeof(t_header);
    fwrite(&header, 1, sizeof(header), fd_out);

    memset(&samples, 0, sizeof(samples));
    for (i = 0; i < data_size; i += 6) {
        samples[i / 6].left  |= ((uint32_t) test_data[i + 0]) << 24U;
        samples[i / 6].left  |= ((uint32_t) test_data[i + 1]) << 16U;
        samples[i / 6].left  |= ((uint32_t) test_data[i + 2]) << 8U;
        samples[i / 6].right |= ((uint32_t) test_data[i + 3]) << 24U;
        samples[i / 6].right |= ((uint32_t) test_data[i + 4]) << 16U;
        samples[i / 6].right |= ((uint32_t) test_data[i + 5]) << 8U;
    }
    for (i = 0; i < block_size; i++) {
        printf("%02d M ch0 %06x\n", i, ((uint32_t) samples[i].left) >> 8U);
        printf("%02d W ch1 %06x\n", i, ((uint32_t) samples[i].right) >> 8U);
    }

    for (i = 0; i < num_blocks; i++) {
        fwrite(&samples, 1, sizeof(samples), fd_out);
    }
    fclose(fd_out);
    return 0;
}


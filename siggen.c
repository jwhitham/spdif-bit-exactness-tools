// Suggested compile command: gcc -o siggen.exe siggen.c -Wall -Werror -g  -O
//
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

static const uint32_t allowed_sample_rate[] = {
    32000, 44100, 48000, 88200, 96000, 0};

static const uint8_t payload[] = {
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
};


static void generate(const uint32_t sample_rate, FILE* fd_out)
{
    t_header        header;
    const uint32_t  repeat_size = 40;   // samples
    const uint32_t  wav_length = 15;    // seconds
    t_stereo        samples[repeat_size];
    const uint32_t  block_size = sizeof(samples) / sizeof(t_stereo);
    const uint32_t  num_blocks = (sample_rate * 2 * wav_length) / block_size;
    const uint32_t  num_samples = num_blocks * block_size;
    const uint32_t  mask24 = 0xffffff00U;
    uint32_t        i = 0;
    uint32_t        j = 0;

    // Write wav header
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

    // Check endianness
    if (((uint32_t *) &header.fixed_riff)[0] != 0x46464952) {
        fprintf(stderr, "endianness error (little endian assumed, sorry)\n");
        exit(1);
    }

    // Generate repeating sample
    memset(&samples, 0, sizeof(samples));

    // First part of the repeating block: walking 1s (24 samples)
    for (i = 0; i < 24; i++) {
        samples[i].left = (int32_t) (256U << i);
        samples[i].right = (int32_t) ((256U << i) ^ mask24);
    }
    // Second part of the repeating block: identifier (1 sample)
    samples[i].left = (sample_rate / 100) << 16;
    samples[i].right = 0x654321 << 8;
    i++;
    // Third part of the repeating block: 16 bit data (7 samples)
    for (; i < 32; i++) {
        samples[i].left  |= ((uint32_t) payload[j + 0]) << 24U;
        samples[i].left  |= ((uint32_t) payload[j + 1]) << 16U;
        samples[i].right |= ((uint32_t) payload[j + 2]) << 24U;
        samples[i].right |= ((uint32_t) payload[j + 3]) << 16U;
        j += 4;
    }
    // Final part of the repeating block: 24 bit data (8 samples)
    for (; i < repeat_size; i++) {
        samples[i].left  |= ((uint32_t) payload[j + 0]) << 24U;
        samples[i].left  |= ((uint32_t) payload[j + 1]) << 16U;
        samples[i].left  |= ((uint32_t) payload[j + 2]) << 8U;
        samples[i].right |= ((uint32_t) payload[j + 3]) << 24U;
        samples[i].right |= ((uint32_t) payload[j + 4]) << 16U;
        samples[i].right |= ((uint32_t) payload[j + 5]) << 8U;
        j += 6;
    }
    if (j > sizeof(payload)) {
        fprintf(stderr, "payload size error\n");
        exit(1);
    }

    // write data
    for (i = 0; i < num_blocks; i++) {
        fwrite(&samples, 1, sizeof(samples), fd_out);
    }
}

int main(int argc, char ** argv)
{
    FILE *          fd_out;
    uint32_t        sample_rate;
    uint32_t        i;

    if (argc != 3) {
        fprintf(stderr, "Usage: siggen <sample rate> <output.wav>\n"
                        "<sample rate> may be");
        for (i = 0; allowed_sample_rate[i] != 0; i++) {
            fprintf(stderr, " %u", (unsigned) allowed_sample_rate[i]);
        }
        fprintf(stderr, "\n");
        return 1;
    }

    sample_rate = (uint32_t) atoi(argv[1]);
    i = 0;
    while (allowed_sample_rate[i] != sample_rate) {
        if (allowed_sample_rate[i] == 0) {
            fprintf(stderr, "this sample rate is not allowed\n");
            return 1;
        }
        i++;
    }

    fd_out = fopen(argv[2], "wb");
    if (!fd_out) {
        perror("open (write)");
        return 1;
    }
    generate(sample_rate, fd_out);
    fclose(fd_out);
    return 0;
}


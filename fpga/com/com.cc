#include "packetgen.h"


#include <objbase.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <stdio.h>


//-----------------------------------------------------------
// Play an audio stream on the default audio rendering
// device. The PlayAudioStream function allocates a shared
// buffer big enough to hold one second of PCM audio data.
// The function uses this buffer to stream data to the
// rendering device. The inner loop runs every 1/2 second.
//-----------------------------------------------------------

// REFERENCE_TIME time units per second and per millisecond
#define REFTIMES_PER_SEC  10000000
#define REFTIMES_PER_MILLISEC  10000

#define EXIT_ON_ERROR(hres)  \
              if (FAILED(hres)) { goto Exit; }
#define SAFE_RELEASE(punk)  \
              if ((punk) != NULL)  \
                { (punk)->Release(); (punk) = NULL; }

const CLSID CLSID_MMDeviceEnumerator = __uuidof(MMDeviceEnumerator);
const IID IID_IMMDeviceEnumerator = __uuidof(IMMDeviceEnumerator);
const IID IID_IAudioClient = __uuidof(IAudioClient);
const IID IID_IAudioRenderClient = __uuidof(IAudioRenderClient);

size_t copySamples(BYTE* pData, const int16_t* sampleData, const size_t sampleIndex,
                const size_t sampleCount, UINT32 bufferFrameCount, WORD nChannels)
{
    const int16_t* in = sampleData;
    int16_t* out = (int16_t*) pData;
    size_t samplesToCopy = sampleCount - sampleIndex;
    if (samplesToCopy > bufferFrameCount)
    {
        samplesToCopy = bufferFrameCount;
    }
    for (size_t i = 0; i < samplesToCopy; i++) 
    {
        for (WORD j = 0; j < nChannels; j++)
        {
            *out = *in;
            out++;
        }
        in++;
    }
    return samplesToCopy + sampleIndex;
}

HRESULT com_send(const size_t numPackets, const uint64_t* packetData)
{
    HRESULT hr;
    REFERENCE_TIME hnsRequestedDuration = REFTIMES_PER_SEC;
    REFERENCE_TIME hnsActualDuration;
    IMMDeviceEnumerator *pEnumerator = NULL;
    IMMDevice *pDevice = NULL;
    IAudioClient *pAudioClient = NULL;
    IAudioRenderClient *pRenderClient = NULL;
    WAVEFORMATEX wfx;
    UINT32 bufferFrameCount;
    UINT32 numFramesAvailable;
    UINT32 numFramesPadding;
    BYTE *pData;
    DWORD flags = 0;
    int16_t* sampleData = NULL;
    size_t sampleCount = 0;
    size_t sampleIndex = 0;
    const uint32_t sampleRate = 48000;

    if (!packetgen_build_samples(numPackets, packetData,
                                 sampleRate,
                                 &sampleData, &sampleCount)) {
        return E_FAIL;
    }

    hr = CoCreateInstance(
           CLSID_MMDeviceEnumerator, NULL,
           CLSCTX_ALL, IID_IMMDeviceEnumerator,
           (void**)&pEnumerator);
    EXIT_ON_ERROR(hr)

    hr = pEnumerator->GetDefaultAudioEndpoint(
                        eRender, eConsole, &pDevice);
    EXIT_ON_ERROR(hr)

    hr = pDevice->Activate(
                    IID_IAudioClient, CLSCTX_ALL,
                    NULL, (void**)&pAudioClient);
    EXIT_ON_ERROR(hr)

    //hr = pAudioClient->GetMixFormat(&pwfx);
    //EXIT_ON_ERROR(hr)
    memset(&wfx, 0, sizeof(wfx));
    wfx.wFormatTag = WAVE_FORMAT_PCM;
    wfx.nChannels = 2;
    wfx.nSamplesPerSec = sampleRate;
    wfx.wBitsPerSample = 16;
    wfx.nBlockAlign = (wfx.wBitsPerSample * wfx.nChannels) / 8;
    wfx.nAvgBytesPerSec = wfx.nSamplesPerSec * wfx.nBlockAlign;
    wfx.cbSize = 0;

    hr = pAudioClient->Initialize(
                         AUDCLNT_SHAREMODE_SHARED,
                         0,
                         hnsRequestedDuration,
                         0,
                         &wfx,
                         NULL);
    switch (hr) {
        case S_OK: printf("S_OK\n"); break;

        case AUDCLNT_E_ALREADY_INITIALIZED: printf("AUDCLNT_E_ALREADY_INITIALIZED\n"); break;
        case AUDCLNT_E_WRONG_ENDPOINT_TYPE: printf("AUDCLNT_E_WRONG_ENDPOINT_TYPE\n"); break;
        case AUDCLNT_E_BUFFER_SIZE_NOT_ALIGNED: printf("AUDCLNT_E_BUFFER_SIZE_NOT_ALIGNED\n"); break;
        case AUDCLNT_E_BUFFER_SIZE_ERROR: printf("AUDCLNT_E_BUFFER_SIZE_ERROR\n"); break;
        case AUDCLNT_E_CPUUSAGE_EXCEEDED: printf("AUDCLNT_E_CPUUSAGE_EXCEEDED\n"); break;
        case AUDCLNT_E_DEVICE_INVALIDATED: printf("AUDCLNT_E_DEVICE_INVALIDATED\n"); break;
        case AUDCLNT_E_DEVICE_IN_USE: printf("AUDCLNT_E_DEVICE_IN_USE\n"); break;
        case AUDCLNT_E_ENDPOINT_CREATE_FAILED: printf("AUDCLNT_E_ENDPOINT_CREATE_FAILED\n"); break;
        case AUDCLNT_E_INVALID_DEVICE_PERIOD: printf("AUDCLNT_E_INVALID_DEVICE_PERIOD\n"); break;
        case AUDCLNT_E_UNSUPPORTED_FORMAT: printf("AUDCLNT_E_UNSUPPORTED_FORMAT\n"); break;
        case AUDCLNT_E_EXCLUSIVE_MODE_NOT_ALLOWED: printf("AUDCLNT_E_EXCLUSIVE_MODE_NOT_ALLOWED\n"); break;
        case AUDCLNT_E_BUFDURATION_PERIOD_NOT_EQUAL: printf("AUDCLNT_E_BUFDURATION_PERIOD_NOT_EQUAL\n"); break;
        case AUDCLNT_E_SERVICE_NOT_RUNNING: printf("AUDCLNT_E_SERVICE_NOT_RUNNING\n"); break;
        case E_POINTER: printf("E_POINTER\n"); break;
        case E_INVALIDARG: printf("E_INVALIDARG\n"); break;
        case E_OUTOFMEMORY: printf("E_OUTOFMEMORY\n"); break;

        case REGDB_E_CLASSNOTREG: printf("REGDB_E_CLASSNOTREG\n"); break;
        case CLASS_E_NOAGGREGATION: printf("CLASS_E_NOAGGREGATION\n"); break;
        case E_NOINTERFACE: printf("E_NOINTERFACE\n"); break;
        default: printf("other\n"); break;
    }
    EXIT_ON_ERROR(hr)

    // Get the actual size of the allocated buffer.
    hr = pAudioClient->GetBufferSize(&bufferFrameCount);
    EXIT_ON_ERROR(hr)

    hr = pAudioClient->GetService(
                         IID_IAudioRenderClient,
                         (void**)&pRenderClient);
    EXIT_ON_ERROR(hr)

    // Grab the entire buffer for the initial fill operation.
    hr = pRenderClient->GetBuffer(bufferFrameCount, &pData);
    EXIT_ON_ERROR(hr)

    // Load the initial data into the shared buffer.
    sampleIndex = copySamples(pData, sampleData, sampleIndex, sampleCount, bufferFrameCount, wfx.nChannels);

    hr = pRenderClient->ReleaseBuffer(bufferFrameCount, flags);
    EXIT_ON_ERROR(hr)

    // Calculate the actual duration of the allocated buffer.
    hnsActualDuration = (double)REFTIMES_PER_SEC *
                        bufferFrameCount / wfx.nSamplesPerSec;

    hr = pAudioClient->Start();  // Start playing.
    EXIT_ON_ERROR(hr)

    // Each loop fills about half of the shared buffer.
    while (sampleIndex < sampleCount)
    {
        // Sleep for half the buffer duration.
        Sleep((DWORD)(hnsActualDuration/REFTIMES_PER_MILLISEC/2));

        // See how much buffer space is available.
        hr = pAudioClient->GetCurrentPadding(&numFramesPadding);
        EXIT_ON_ERROR(hr)

        numFramesAvailable = bufferFrameCount - numFramesPadding;

        // Grab all the available space in the shared buffer.
        hr = pRenderClient->GetBuffer(numFramesAvailable, &pData);
        EXIT_ON_ERROR(hr)

        // Get next 1/2-second of data from the audio source.
        sampleIndex = copySamples(pData, sampleData, sampleIndex, sampleCount, bufferFrameCount, wfx.nChannels);

        hr = pRenderClient->ReleaseBuffer(numFramesAvailable, flags);
        EXIT_ON_ERROR(hr)
    }

    // Wait for last data in buffer to play before stopping.
    Sleep((DWORD)(hnsActualDuration/REFTIMES_PER_MILLISEC/2));

    hr = pAudioClient->Stop();  // Stop playing.
    EXIT_ON_ERROR(hr)

Exit:
    free(sampleData);
    SAFE_RELEASE(pEnumerator)
    SAFE_RELEASE(pDevice)
    SAFE_RELEASE(pAudioClient)
    SAFE_RELEASE(pRenderClient)

    return hr;
}

int main(int argc, char** argv)
{
    HRESULT hr;
    hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    printf("%08x\n", (unsigned) hr);
    if (hr == S_OK)
    {
        // convert packet parameters to numbers
        const int num_packets = argc - 1;
        if (num_packets > 0)
        {
            uint64_t* packet_data = (uint64_t*) calloc(sizeof(uint64_t), num_packets);
            if (!packet_data)
            {
                fprintf(stderr, "Error: allocate failed\n");
                exit(1);
            }
            for (int i = 0; i < num_packets; i++) {
                packet_data[i] = (uint64_t) strtoll(argv[i + 1], NULL, 0);
                
            }
            hr = com_send(num_packets, packet_data);
            printf("%08x\n", (unsigned) hr);
            free(packet_data);
        }
    }
    CoUninitialize();
    return 0;
}


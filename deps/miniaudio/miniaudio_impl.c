#define MA_NO_DECODING
#define MA_NO_ENCODING
#define MA_NO_GENERATION
#define MA_NO_NODE_GRAPH
#define MA_NO_RESOURCE_MANAGER
#define MA_NO_ENGINE
#define MA_NO_JACK
#define MA_NO_OSS
#define MA_NO_SNDIO
#define MA_NO_DSOUND
#define MA_NO_WINMM
#define MA_NO_WAV
#define MA_NO_MP3
#define MA_NO_FLAC
#define MA_NO_STDIO
#define MA_NO_AAUDIO
#define MA_NO_OPENSL
#ifndef __EMSCRIPTEN__
#define MA_NO_WEBAUDIO
#endif
#define MA_NO_COREAUDIO
#define MA_NO_AUDIO4
#define MA_NO_CUSTOM
#define MINIAUDIO_IMPLEMENTATION
/* MinGW to MSVC linkage workaround: Force standard vsnprintf bindings
   rather than relying on MinGW's stdio.h implementations which conflict with MSVC UCRT */
#if defined(_WIN32) && (defined(__MINGW32__) || defined(__MINGW64__) || defined(__GNUC__))
#define vsnprintf _vsnprintf
#define snprintf _snprintf
#endif

#include "miniaudio.h"

#include <stdio.h>

static ma_device device;

void miniaudio_callback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount) {
    void (*callback)(void*, float*, float*, unsigned int) = (void (*)(void*, float*, float*, unsigned int))pDevice->pUserData;
    if (callback) {
        callback(pDevice, (float*)pOutput, (float*)pInput, frameCount);
    }
}

int audio_init_device(void (*callback)(void*, float*, float*, unsigned int)) {
    ma_device_config deviceConfig = ma_device_config_init(ma_device_type_playback);
    deviceConfig.playback.format   = ma_format_f32;
    deviceConfig.playback.channels = 2;
    deviceConfig.sampleRate        = 44100;
    deviceConfig.dataCallback      = miniaudio_callback;
    deviceConfig.pUserData         = (void*)callback;

    if (ma_device_init(NULL, &deviceConfig, &device) != MA_SUCCESS) {
        return -1;
    }

    if (ma_device_start(&device) != MA_SUCCESS) {
        ma_device_uninit(&device);
        return -2;
    }

    return 0;
}

void audio_terminate_device() {
    ma_device_stop(&device);
    ma_device_uninit(&device);
}


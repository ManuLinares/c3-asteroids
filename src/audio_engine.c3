module audio;
import std::math;
import std::io;

const usz MAX_VOICES = 16;
const float SAMPLE_RATE = 44100.0f;

enum VoiceType {
    NONE,
    LASER,
    EXPLOSION,
    THUMP,
    SAUCER,
    THRUST,
    EXTRA_LIFE
}

struct Voice {
    VoiceType type;
    float phase;
    float frequency;
    float duration;
    float elapsed;
    float volume;
    float filter_state;
    float val1;
}

Voice[MAX_VOICES] voices;
uint seed = 12345;

fn float rand_f() {
    seed = seed * 1103515245 + 12345;
    return (float)(seed & 0x7FFFFFFF) / (float)0x7FFFFFFF;
}

fn float triangle(float phase) {
    float v = (phase / (2.0f * 3.14159265f));
    v = v - math::floor(v);
    if (v < 0.5f) return v * 4.0f - 1.0f;
    return 3.0f - v * 4.0f;
}

fn float square(float phase) {
    float v = (phase / (2.0f * 3.14159265f));
    v = v - math::floor(v);
    return (v < 0.5f) ? 1.0f : -1.0f;
}

alias AudioCallbackFn = fn void(void*, float*, float*, uint) @callconv("cdecl");
extern fn int audio_init_device(AudioCallbackFn callback) @callconv("cdecl");
extern fn void audio_terminate_device() @callconv("cdecl");

fn void audio_callback(void* pDevice, float* out, float* in, uint frameCount) @callconv("cdecl") {
    for (uint i = 0; i < frameCount; i++) {
        float sample = 0.0f;
        for (usz v = 0; v < MAX_VOICES; v++) {
            if (voices[v].type == VoiceType.NONE) continue;
            Voice* pVoice = &voices[v];
            float t = pVoice.elapsed / pVoice.duration;
            if (t >= 1.0f && pVoice.type != VoiceType.THRUST && pVoice.type != VoiceType.SAUCER) {
                pVoice.type = VoiceType.NONE;
                continue;
            }
            float currentSample = 0.0f;
            switch (pVoice.type) {
                case VoiceType.LASER:
                    float freq = 200.0f + 1300.0f * math::exp(-t * 6.0f);
                    currentSample = triangle(pVoice.phase + 1.5707f);
                    pVoice.phase += 2.0f * 3.14159f * freq / SAMPLE_RATE;
                    currentSample *= (1.0f - t);
                case VoiceType.EXPLOSION:
                    float noise = rand_f() * 2.0f - 1.0f;
                    float alpha = pVoice.frequency;
                    pVoice.filter_state = pVoice.filter_state + alpha * (noise - pVoice.filter_state);
                    currentSample = pVoice.filter_state * (1.0f - t);
                case VoiceType.THUMP:
                    currentSample = math::sin(pVoice.phase);
                    pVoice.phase += 2.0f * 3.14159f * pVoice.frequency / SAMPLE_RATE;
                    currentSample *= (1.0f - t);
                case VoiceType.SAUCER:
                    pVoice.val1 += 1.0f / SAMPLE_RATE;
                    float lfo_freq = (pVoice.frequency > 200.0f) ? 32.0f : 16.0f;
                    float lfo = math::sin(pVoice.val1 * 2.0f * 3.14159f * lfo_freq) * 40.0f;
                    float freq_s = pVoice.frequency + lfo;
                    currentSample = triangle(pVoice.phase + 1.5707f);
                    pVoice.phase += 2.0f * 3.14159f * freq_s / SAMPLE_RATE;
                    currentSample *= 0.5f;
                case VoiceType.THRUST:
                    float tnoise = rand_f() * 2.0f - 1.0f;
                    pVoice.filter_state = pVoice.filter_state + 0.1f * (tnoise - pVoice.filter_state);
                    currentSample = pVoice.filter_state * pVoice.volume;
                case VoiceType.EXTRA_LIFE:
                    currentSample = square(pVoice.phase);
                    pVoice.phase += 2.0f * 3.14159f * 3000.0f / SAMPLE_RATE;
                    float bt = t * 3.0f;
                    float be = bt - math::floor(bt);
                    currentSample *= (be < 0.5f) ? 1.0f : 0.0f;
                default:
            }
            const float ATTACK_TIME = 0.002f;
            if (pVoice.elapsed < ATTACK_TIME) {
                currentSample *= (pVoice.elapsed / ATTACK_TIME);
            }
            sample += currentSample * pVoice.volume * 0.25f;
            pVoice.elapsed += 1.0f / SAMPLE_RATE;
        }
        if (sample > 1.0f) sample = 1.0f;
        if (sample < -1.0f) sample = -1.0f;
        out[i*2] = sample;
        out[i*2+1] = sample;
    }
}

fn int audio_init() {
    foreach (&v : voices) v.type = VoiceType.NONE;
    return audio_init_device(&audio_callback);
}

fn void audio_play_laser() {
    foreach (&v : voices) {
        if (v.type == VoiceType.NONE) {
            *v = { .type = VoiceType.LASER, .phase = 0, .frequency = 0, .duration = 0.25f, .elapsed = 0, .volume = 0.6f, .filter_state = 0, .val1 = 0 };
            return;
        }
    }
}

fn void audio_play_explosion(float size_scale) {
    foreach (&v : voices) {
        if (v.type == VoiceType.NONE) {
            float alpha = 0.35f / (size_scale * 1.5f);
            if (alpha > 0.6f) alpha = 0.6f;
            if (alpha < 0.08f) alpha = 0.08f;
            *v = { .type = VoiceType.EXPLOSION, .phase = 0, .frequency = alpha, .duration = 0.5f * size_scale, .elapsed = 0, .volume = 0.8f, .filter_state = 0, .val1 = 0 };
            return;
        }
    }
}

fn void audio_play_thump(bool high) {
    foreach (&v : voices) {
        if (v.type == VoiceType.NONE) {
            *v = { .type = VoiceType.THUMP, .phase = 0, .frequency = high ? 72.0f : 64.0f, .duration = 0.12f, .elapsed = 0, .volume = 1.1f, .filter_state = 0, .val1 = 0 };
            return;
        }
    }
}

fn void audio_set_saucer(bool active, bool big) {
    static usz saucerVoiceIdx = (usz)-1;
    if (active) {
        if (saucerVoiceIdx == (usz)-1 || voices[saucerVoiceIdx].type != VoiceType.SAUCER) {
            foreach (i, &v : voices) {
                if (v.type == VoiceType.NONE) {
                    *v = { .type = VoiceType.SAUCER, .phase = 0, .frequency = big ? 280.0f : 560.0f, .duration = 1000.0f, .elapsed = 0, .volume = 0.45f, .filter_state = 0, .val1 = 0 };
                    saucerVoiceIdx = i;
                    return;
                }
            }
        }
    } else {
        if (saucerVoiceIdx != (usz)-1) {
            voices[saucerVoiceIdx].type = VoiceType.NONE;
            saucerVoiceIdx = (usz)-1;
        }
    }
}

fn void audio_set_thrust(bool active) {
    static usz thrustVoiceIdx = (usz)-1;
    if (active) {
        if (thrustVoiceIdx == (usz)-1 || voices[thrustVoiceIdx].type != VoiceType.THRUST) {
            foreach (i, &v : voices) {
                if (v.type == VoiceType.NONE) {
                    *v = { .type = VoiceType.THRUST, .phase = 0, .frequency = 0, .duration = 1000.0f, .elapsed = 0, .volume = 0.35f, .filter_state = 0, .val1 = 0 };
                    thrustVoiceIdx = i;
                    return;
                }
            }
        }
    } else {
        if (thrustVoiceIdx != (usz)-1) {
            voices[thrustVoiceIdx].type = VoiceType.NONE;
            thrustVoiceIdx = (usz)-1;
        }
    }
}

fn void audio_play_life() {
    foreach (&v : voices) {
        if (v.type == VoiceType.NONE) {
            *v = { .type = VoiceType.EXTRA_LIFE, .phase = 0, .frequency = 0, .duration = 0.4f, .elapsed = 0, .volume = 0.7f, .filter_state = 0, .val1 = 0 };
            return;
        }
    }
}

fn void audio_terminate() {
    audio_terminate_device();
}

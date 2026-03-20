module audio;
import ma;
import std::math;
import std::math::random;
import std::io;
import std::time;

const usz MAX_VOICES = 16;
const float SAMPLE_RATE = 44100.0f;
const usz CHANNELS = 2;

ma::Device device;

enum VoiceType
{
	NONE,
	LASER,
	EXPLOSION,
	THUMP,
	SAUCER,
	THRUST,
	EXTRA_LIFE
}

struct Voice
{
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

fn float rand_f() => (float)rnd(); //clock was missing in wasm

//Sfc64Random audio_random;
//fn float rand_f() => random::next_float(&audio_random); //this works fine

fn Voice* find_free_voice()
{
	foreach (&v : voices) if (v.type == VoiceType.NONE) return v;
	return null;
}

fn void Voice.play(&self, VoiceType type, float freq, float dur, float vol)
{
	*self = {
		.type = type,
		.phase = 0,
		.frequency = freq,
		.duration = dur,
		.volume = vol
	};
}

fn float triangle(float phase)
{
	float v = (phase / (2.0f * (float)math::PI));
	v = v - math::floor(v);
	if (v < 0.5f) return v * 4.0f - 1.0f;
	return 3.0f - v * 4.0f;
}

fn float square(float phase)
{
	float v = (phase / (2.0f * (float)math::PI));
	v = v - math::floor(v);
	return (v < 0.5f) ? 1.0f : -1.0f;
}

alias AudioCallbackFn = fn void(
	ma::Device*,
	float*,
	float*,
	uint
) @callconv("cdecl");

fn void audio_callback(
	ma::Device* pDevice,
	float* out,
	float* in,
	uint frameCount
) @callconv("cdecl")
{
	for (uint i = 0; i < frameCount; i++)
	{
		float sample = 0.0f;
		for (usz v = 0; v < MAX_VOICES; v++)
		{
			if (voices[v].type == VoiceType.NONE) continue;
			Voice* pVoice = &voices[v];
			float t = pVoice.elapsed / pVoice.duration;
			if (t >= 1.0f && pVoice.type != VoiceType.THRUST
				&& pVoice.type != VoiceType.SAUCER)
			{
				pVoice.type = VoiceType.NONE;
				continue;
			}
			float currentSample = 0.0f;
			switch (pVoice.type)
			{
				case VoiceType.LASER:
					float freq = 200.0f + 1300.0f * math::exp(-t * 6.0f);
					currentSample = triangle(pVoice.phase + (float)math::PI_2);
					pVoice.phase += 2.0f * (float)math::PI * freq / SAMPLE_RATE;
					currentSample *= (1.0f - t);
				case VoiceType.EXPLOSION:
					float noise = rand_f() * 2.0f - 1.0f;
					float alpha = pVoice.frequency;
					pVoice.filter_state = pVoice.filter_state
						+ alpha * (noise - pVoice.filter_state);
					currentSample = pVoice.filter_state * (1.0f - t);
				case VoiceType.THUMP:
					currentSample = math::sin(pVoice.phase);
					pVoice.phase += 2.0f * (float)math::PI * pVoice.frequency
						/ SAMPLE_RATE;
					currentSample *= (1.0f - t);
				case VoiceType.SAUCER:
					pVoice.val1 += 1.0f / SAMPLE_RATE;
					float lfo_freq = (pVoice
						.frequency > 200.0f) ? 32.0f : 16.0f;
					float lfo = math::sin(
						pVoice.val1 * 2.0f * (float)math::PI * lfo_freq
					)
						* 40.0f;
					float freq_s = pVoice.frequency + lfo;
					currentSample = triangle(pVoice.phase + (float)math::PI_2);
					pVoice.phase += 2.0f * (float)math::PI * freq_s
						/ SAMPLE_RATE;
					currentSample *= 0.5f;
				case VoiceType.THRUST:
					float tnoise = rand_f() * 2.0f - 1.0f;
					pVoice.filter_state = pVoice.filter_state
						+ 0.1f * (tnoise - pVoice.filter_state);
					currentSample = pVoice.filter_state * pVoice.volume;
				case VoiceType.EXTRA_LIFE:
					currentSample = square(pVoice.phase);
					pVoice.phase += 2.0f * (float)math::PI * 3000.0f
						/ SAMPLE_RATE;
					float bt = t * 3.0f;
					float be = bt - math::floor(bt);
					currentSample *= (be < 0.5f) ? 1.0f : 0.0f;
				default:
			}
			const float ATTACK_TIME = 0.002f;
			if (pVoice.elapsed < ATTACK_TIME)
			{
				currentSample *= (pVoice.elapsed / ATTACK_TIME);
			}
			sample += currentSample * pVoice.volume * 0.25f;
			pVoice.elapsed += 1.0f / SAMPLE_RATE;
		}
		if (sample > 1.0f) sample = 1.0f;
		if (sample < -1.0f) sample = -1.0f;
		out[i * 2] = sample;
		out[i * 2 + 1] = sample;
	}
}

fn int audio_init()
{
	//random::seed(&audio_random, (ulong)time::now());
	foreach (&v : voices) v.type = VoiceType.NONE;

	ma::DeviceConfig config = ma::device_config_init(ma::DeviceType.PLAYBACK);
	config.playback.format = ma::Format.F32;
	config.playback.channels = CHANNELS;
	config.sampleRate = (uint)SAMPLE_RATE;
	config.dataCallback = (ma::DataCallback)&audio_callback;

	if (ma::device_init(null, &config, &device) != ma::Result.SUCCESS)
	{
		return -1;
	}

	if (ma::device_start(&device) != ma::Result.SUCCESS)
	{
		ma::device_uninit(&device);
		return -2;
	}

	return 0;
}

fn void audio_play_laser()
{
	if (Voice* v = find_free_voice())
	{
		v.play(LASER, 0, 0.25f, 0.6f);
	}
}

fn void audio_play_explosion(float size_scale)
{
	if (Voice* v = find_free_voice())
	{
		float alpha = 0.35f / (size_scale * 1.5f);
		if (alpha > 0.6f) alpha = 0.6f;
		if (alpha < 0.08f) alpha = 0.08f;
		v.play(EXPLOSION, alpha, 0.5f * size_scale, 0.8f);
	}
}

fn void audio_play_thump(bool high)
{
	if (Voice* v = find_free_voice())
	{
		v.play(THUMP, high ? 72f : 64f, 0.12f, 1.1f);
	}
}

fn void audio_set_saucer(bool active, bool big)
{
	static usz saucerVoiceIdx = (usz)-1;
	if (active)
	{
		if (saucerVoiceIdx == (usz)-1
			|| voices[saucerVoiceIdx].type != VoiceType.SAUCER)
		{
			if (Voice* v = find_free_voice())
			{
				v.play(SAUCER, big ? 280f : 560f, 1000f, 0.45f);
				saucerVoiceIdx = (usz)(v - &voices[0]);
			}
		}
	}
	else
	{
		if (saucerVoiceIdx != (usz)-1)
		{
			voices[saucerVoiceIdx].type = VoiceType.NONE;
			saucerVoiceIdx = (usz)-1;
		}
	}
}

fn void audio_set_thrust(bool active)
{
	static usz thrustVoiceIdx = (usz)-1;
	if (active)
	{
		if (thrustVoiceIdx == (usz)-1
			|| voices[thrustVoiceIdx].type != VoiceType.THRUST)
		{
			if (Voice* v = find_free_voice())
			{
				v.play(THRUST, 0, 1000f, 0.35f);
				thrustVoiceIdx = (usz)(v - &voices[0]);
			}
		}
	}
	else
	{
		if (thrustVoiceIdx != (usz)-1)
		{
			voices[thrustVoiceIdx].type = VoiceType.NONE;
			thrustVoiceIdx = (usz)-1;
		}
	}
}

fn void audio_play_life()
{
	if (Voice* v = find_free_voice())
	{
		v.play(EXTRA_LIFE, 0, 0.4f, 0.7f);
	}
}

fn void audio_terminate()
{
	ma::device_stop(&device);
	ma::device_uninit(&device);
}

module ma;

/**
 * Miniaudio bindings for C3
 */

constdef Format : int {
	UNKNOWN = 0,
	U8      = 1,
	S16     = 2,
	S24     = 3,
	S32     = 4,
	F32     = 5
}

constdef DeviceType : int {
	PLAYBACK = 1,
	CAPTURE  = 2,
	DUPLEX   = 3,
	LOOPBACK = 4
}

constdef Result : int {
	SUCCESS = 0,
	ERROR   = -1,
}

alias DataCallback = fn void(Device* pDevice, void* pOutput, void* pInput, uint frameCount) @callconv("cdecl");

struct Device {
	char[3776] data;
}

struct DeviceConfigPlayback {
	void* pDeviceID;    // 0
	Format format;      // 8
	uint channels;      // 12
	void* pChannelMap;  // 16
	int channelMixMode; // 24
	bool calculateLFE;  // 28
	int shareMode;      // 32
	uint _padding;      // 36
}

struct DeviceConfig {
	DeviceType deviceType;     // 0
	uint sampleRate;           // 4
	uint periodSizeInFrames;   // 8
	uint periodSizeInMS;       // 12
	uint periods;              // 16
	int performanceProfile;    // 20
	bool noPreSilenced;        // 24
	bool noClip;               // 25
	bool noDisableDenormals;   // 26
	bool noFixedSized;         // 27
	DataCallback dataCallback; // 32
	void* notificationCallback; // 40
	void* stopCallback;        // 48
	void* pUserData;           // 56
	char[48] _resampling;      // 64 (resampling starts at 64, playback at 112)
	DeviceConfigPlayback playback; // 112
	char[144] _padding;        // Total 296
}

extern fn DeviceConfig device_config_init(DeviceType type) @cname("ma_device_config_init");
extern fn Result device_init(void* pContext, DeviceConfig* pConfig, Device* pDevice) @cname("ma_device_init");
extern fn Result device_start(Device* pDevice) @cname("ma_device_start");
extern fn Result device_stop(Device* pDevice) @cname("ma_device_stop");
extern fn void device_uninit(Device* pDevice) @cname("ma_device_uninit");

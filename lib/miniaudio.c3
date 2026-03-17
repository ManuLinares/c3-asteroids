module ma;

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

struct Device @if(env::WASM) @align(16) {
	char[3136] data;
}

struct Device @if(!env::WASM) {
	char[3776] data;
}

struct DeviceConfigPlayback @if(env::WASM) {
	void* pDeviceID;
	Format format;
	uint channels;
	void* pChannelMap;
	int channelMixMode;
	bool calculateLFE;
	int shareMode;
}

struct DeviceConfig @if(env::WASM) @align(16) {
	DeviceType deviceType;
	uint sampleRate;
	uint periodSizeInFrames;
	uint periodSizeInMS;
	uint periods;
	int performanceProfile;
	bool noPreSilenced;
	bool noClip;
	bool noDisableDenormals;
	bool noFixedSized;
	DataCallback dataCallback;
	void* notificationCallback;
	void* stopCallback;
	void* pUserData;
	char[32] _resampling;
	DeviceConfigPlayback playback;
	char[116] _tail;
}

struct DeviceConfigPlayback @if(!env::WASM) {
	void* pDeviceID;
	Format format;
	uint channels;
	void* pChannelMap;
	int channelMixMode;
	bool calculateLFE;
	int shareMode;
	uint _padding;
}

struct DeviceConfig @if(!env::WASM) {
	DeviceType deviceType;
	uint sampleRate;
	uint periodSizeInFrames;
	uint periodSizeInMS;
	uint periods;
	int performanceProfile;
	bool noPreSilenced;
	bool noClip;
	bool noDisableDenormals;
	bool noFixedSized;
	uint _pad0;
	DataCallback dataCallback;
	void* notificationCallback;
	void* stopCallback;
	void* pUserData;
	char[48] _resampling;
	DeviceConfigPlayback playback;
	char[144] _padding;
}

extern fn DeviceConfig device_config_init(DeviceType type) @cname("ma_device_config_init");
extern fn Result device_init(void* pContext, DeviceConfig* pConfig, Device* pDevice) @cname("ma_device_init");
extern fn Result device_start(Device* pDevice) @cname("ma_device_start");
extern fn Result device_stop(Device* pDevice) @cname("ma_device_stop");
extern fn void device_uninit(Device* pDevice) @cname("ma_device_uninit");

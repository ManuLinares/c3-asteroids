module rgfw;

/* *
 * RGFW Bindings for C3 */

constdef EventType : char
{
	NONE = 0,
	KEY_PRESSED,
	KEY_RELEASED,
	KEY_CHAR,
	MOUSE_BUTTON_PRESSED,
	MOUSE_BUTTON_RELEASED,
	MOUSE_SCROLL,
	MOUSE_POS_CHANGED,
	WINDOW_MOVED,
	WINDOW_RESIZED,
	FOCUS_IN,
	FOCUS_OUT,
	MOUSE_ENTER,
	MOUSE_LEAVE,
	WINDOW_REFRESH,
	QUIT,
	DATA_DROP,
	DATA_DRAG,
	WINDOW_MAXIMIZED,
	WINDOW_MINIMIZED,
	WINDOW_RESTORED,
	SCALE_UPDATED,
	MONITOR_CONNECTED,
	MONITOR_DISCONNECTED
}

// Opaque window handle
typedef Window = void;

constdef Key : char
{
	NULL          = 0,
	ESCAPE        = 27,
	BACKTICK      = 96,
	K_0           = 48,
	K_1           = 49,
	K_2           = 50,
	K_3           = 51,
	K_4           = 52,
	K_5           = 53,
	K_6           = 54,
	K_7           = 55,
	K_8           = 56,
	K_9           = 57,
	MINUS         = 45,
	EQUALS        = 61,
	BACKSPACE     = 8,
	TAB           = 9,
	SPACE         = 32,
	A             = 97,
	B             = 98,
	C             = 99,
	D             = 100,
	E             = 101,
	F             = 102,
	G             = 103,
	H             = 104,
	I             = 105,
	J             = 106,
	K             = 107,
	L             = 108,
	M             = 109,
	N             = 110,
	O             = 111,
	P             = 112,
	Q             = 113,
	R             = 114,
	S             = 115,
	T             = 116,
	U             = 117,
	V             = 118,
	W             = 119,
	X             = 120,
	Y             = 121,
	Z             = 122,
	PERIOD        = 46,
	COMMA         = 44,
	SLASH         = 47,
	BRACKET       = 91,
	CLOSE_BRACKET = 93,
	SEMICOLON     = 59,
	APOSTROPHE    = 39,
	BACKSLASH     = 92,
	RETURN        = 10,
	DELETE        = 127,
	UP            = 162,
	DOWN          = 163,
	LEFT          = 164,
	RIGHT         = 165
}

constdef Keymod : char
{
	CAPS_LOCK   = 1,
	NUM_LOCK    = 2,
	CONTROL     = 4,
	ALT         = 8,
	SHIFT       = 16,
	SUPER       = 32,
	SCROLL_LOCK = 64
}

constdef MouseButton : char
{
	LEFT = 0,
	MIDDLE,
	RIGHT,
	MISC1,
	MISC2,
	MISC3,
	MISC4,
	MISC5
}

constdef WindowFlags : uint
{
	NO_BORDER        = 1,
	NO_RESIZE        = 2,
	ALLOW_DND        = 4,
	HIDE_MOUSE       = 8,
	FULLSCREEN       = 16,
	TRANSPARENT      = 32,
	CENTER           = 64,
	SCALE_TO_MONITOR = 256,
	HIDE             = 512,
	MAXIMIZE         = 1024,
	CENTER_CURSOR    = 2048,
	FLOATING         = 4096,
	FOCUS_ON_SHOW    = 8192,
	MINIMIZE         = 16384,
	FOCUS            = 32768,
	OPENGL           = 131072,
	EGL              = 262144
}

struct CommonEvent
{
	EventType type;
	Window* win;
}

struct MouseButtonEvent
{
	EventType type;
	Window* win;
	char value;
}

struct MouseScrollEvent
{
	EventType type;
	Window* win;
	float x;
	float y;
}

struct MousePosEvent
{
	EventType type;
	Window* win;
	int x;
	int y;
	float vecX;
	float vecY;
}

struct KeyEvent
{
	EventType type;
	Window* win;
	Key value;
	char sym;
	bool repeat;
	Keymod mod;
}

struct DataDropEvent
{
	EventType type;
	Window* win;
	char** files;
	usz count;
}

struct DataDragEvent
{
	EventType type;
	Window* win;
	int x;
	int y;
}

struct ScaleUpdatedEvent
{
	EventType type;
	Window* win;
	float x;
	float y;
}

struct MonitorMode
{
	int w, h;
	uint refreshRate;
	char red, blue, green;
}

struct Monitor
{
	int x, y;
	char[128] name;
	float scaleX, scaleY;
	float pixelRatio;
	float physW, physH;
	MonitorMode mode;
}

union Event
{
	EventType type;
	CommonEvent common;
	MouseButtonEvent button;
	MouseScrollEvent scroll;
	MousePosEvent mouse;
	KeyEvent key;
	DataDropEvent drop;
	DataDragEvent drag;
	ScaleUpdatedEvent scale;
}

extern fn Monitor* get_primary_monitor() @cname("RGFW_getPrimaryMonitor");

extern fn Window* create_window(char* name, int x, int y, usz w, usz h, WindowFlags flags) @cname("RGFW_createWindow");
extern fn bool window_should_close(Window* win) @cname("RGFW_window_shouldClose");
extern fn bool window_check_event(Window* win, Event* event) @cname("RGFW_window_checkEvent");
extern fn void window_close(Window* win) @cname("RGFW_window_close");
extern fn void window_set_fullscreen(Window* win, bool fullscreen) @cname("RGFW_window_setFullscreen");
extern fn void window_set_exit_key(Window* win, Key key) @cname("RGFW_window_setExitKey");
extern fn bool window_get_size(Window* win, int* width_ptr, int* height_ptr) @cname("RGFW_window_getSize");
extern fn bool window_get_position(Window* win, int* x_ptr, int* y_ptr) @cname("RGFW_window_getPosition");
extern fn void* get_proc_address(char* name) @cname("RGFW_getProcAddress");
extern fn bool is_key_pressed(Key key) @cname("RGFW_isKeyPressed");
extern fn bool is_key_down(Key key) @cname("RGFW_isKeyDown");
extern fn bool is_mouse_pressed(MouseButton button) @cname("RGFW_isMousePressed");
extern fn bool window_is_key_pressed(Window* win, Key key) @cname("RGFW_window_isKeyPressed");
extern fn bool window_is_down(Window* win, Key key) @cname("RGFW_window_isKeyDown");
extern fn bool window_is_mouse_pressed(Window* win, MouseButton button) @cname("RGFW_window_isMousePressed");
extern fn void window_show_mouse(Window* win, bool show) @cname("RGFW_window_showMouse");
extern fn void window_move(Window* win, int x, int y) @cname("RGFW_window_move");
extern fn void window_resize(Window* win, int width, int height) @cname("RGFW_window_resize");
extern fn void window_set_name(Window* win, char* name) @cname("RGFW_window_setName");
extern fn void window_maximize(Window* win) @cname("RGFW_window_maximize");
extern fn void window_minimize(Window* win) @cname("RGFW_window_minimize");
extern fn void window_restore(Window* win) @cname("RGFW_window_restore");
constdef Format : char
{
	RGB8 = 0,
	BGR8,
	RGBA8,
	ARGB8,
	BGRA8,
	ABGR8
}

struct Surface
{
	char* data;
	int w, h;
	Format format;
	void* native;
}

extern fn Surface* window_create_surface(Window* win, char* data, usz width, usz height, Format format) @cname("RGFW_window_createSurface");
extern fn Surface* create_surface(char* data, int width, int height, Format format) @cname("RGFW_createSurface");
extern fn void window_blit_surface(Window* win, Surface* surface) @cname("RGFW_window_blitSurface");
extern fn void surface_free(Surface* surface) @cname("RGFW_surface_free");

extern fn void use_wayland(bool wayland) @cname("RGFW_useWayland");
extern fn bool using_wayland() @cname("RGFW_usingWayland");

import rgfw;
import std::io;
import std::io::file;
import std::core::mem;
import audio;
import std::math;
import std::math::quaternion;
import std::math::vector;
import std::hash::wyhash2;
import std::time;
import std::time::clock;
import std::thread;
import libc;


typedef Color = char[<4>];

const Color BLACK = {0, 0, 0, 255};
const Color GREEN = {0, 255, 0, 255};
const Color WHITE          = {255, 255, 255, 255};
const Color ASTEROID_COLOR = {160, 160, 160, 255};
const Color ENEMY_COLOR    = {255, 100, 255, 255};

const float[<3>][4] SHIP_VERTS = {
	{0.0f,  0.0f,  1.0f},
	{-0.6f, 0.0f, -0.6f},
	{0.6f,  0.0f, -0.6f},
	{0.0f,  0.0f, -0.2f}
};

bitstruct Input : char {
	bool forward : 0;
	bool back    : 1;
	bool left    : 2;
	bool right   : 3;
	bool shoot   : 4;
	bool hyperspace : 5;
	bool cheat : 6;
}

struct Particle {
	float[<3>] pos;
	float[<3>] vel;
	float life;
}

struct Bullet {
	float[<3>] pos;
	float[<3>] vel;
	float life;
	bool from_ship;
}

struct Debris {
	float[<3>] p1;
	float[<3>] p2;
	float[<3>] v1;
	float[<3>] v2;
	bool active;
}

constdef AsteroidSize : int {
	SMALL  = 0,
	MEDIUM = 1,
	LARGE  = 2
}

struct Asteroid {
	float[<3>] pos;
	float[<3>] vel;
	float radius;
	float rot;
	float rot_vel;
	float[<3>][8] verts;
	AsteroidSize size;
	bool active;
}

constdef SaucerType : int {
	BIG = 0,
	SMALL = 1
}

struct Saucer {
	float[<3>] pos;
	float[<3>] vel;
	SaucerType type;
	float shoot_timer;
	bool active;
}

const usz MAX_PARTICLES = 512;
const usz MAX_BULLETS   = 32;
const usz MAX_ASTEROIDS = 128;
const float WORLD_SIZE  = 20.0f;

struct Game {
	float[<3>] ship_pos;
	float[<3>] ship_vel;
	Quaternionf ship_rot;
	float[<3>] cam_pos;
	uint frame;
	uint shoot_cooldown;

	float thrust_acc;
	float rot_speed;
	float cam_ease;
	float scale;

	Input input;
	bool is_dead;
	float death_timer;

	bool is_won;
	float win_timer;
	float wave_notif_timer;

	int score;
	int best_score;
	int lives;
	int wave;
	uint next_saucer_frame;
	int next_extra_life_score;

	bool game_over;
	bool cheat_mode;
	bool paused;
	Saucer saucer;

	Particle[MAX_PARTICLES] particles;
	Bullet[MAX_BULLETS]     bullets;
	Asteroid[MAX_ASTEROIDS] asteroids;
	Debris[5]               ship_pieces;

	uint thump_timer;
	uint thump_interval;
	bool thump_high;
}

fn void Game.init(&self, bool full_reset) {
	if (full_reset) {
		self.score = 0;
		self.lives = 3;
		self.wave = 0;
		self.next_extra_life_score = 10000;
		self.game_over = false;
		self.paused = false;
		self.frame = 0;
		self.thump_interval = 60;
		self.thump_timer = 0;
		self.thump_high = false;

		foreach (&a : self.asteroids) a.active = false;
		self.load_best_score();
		self.wave++;
		self.spawn_wave();
	}

	self.ship_pos   = {0, 0, 0};
	self.ship_vel   = {0, 0, 0};
	self.ship_rot   = QUATERNIONF_IDENTITY;
	self.cam_pos    = self.ship_pos;

	self.thrust_acc = 0.006f;
	self.rot_speed  = 0.06f;
	self.cam_ease   = 0.05f;
	self.scale      = 45.0f;
	self.shoot_cooldown = 0;
	self.is_dead    = false;
	self.death_timer = 0.0f;
	self.is_won     = false;
	self.win_timer  = 0.0f;
	self.wave_notif_timer = 0.0f;

	self.reschedule_saucer();
	self.saucer.active = false;
	self.cheat_mode = false;

	foreach (&p : self.particles) p.life = 0.0f;
	foreach (&b : self.bullets)   b.life = 0.0f;
	foreach (&d : self.ship_pieces) d.active = false;
}

fn void Game.load_best_score(&self) {
	$if (env::WASM):
		self.best_score = emscripten_run_script_int("load_score()");
		return;
	$else
		if (try f = io::file::open("score.txt", "r")) {
			defer (void)f.close();
			char[32] buf;
			usz len = f.read(buf[..])!!;
			if (len > 0) {
				buf[len] = 0;
				self.best_score = (int)libc::atoi(&buf);
			}
		}
	$endif
}

fn void Game.save_best_score(&self) {
	$if (env::WASM):
		char[64] script;
		io::bprintf(script[..], "save_score(%d)\0", self.best_score);
		emscripten_run_script(&script);
	$else
		if (try f = io::file::open("score.txt", "w")) {
			defer (void)f.close();
			char[32] buf;
			usz len = (usz)libc::sprintf(&buf, "%d", self.best_score);
			(void)f.write(buf[:len]);
		}
	$endif
}

fn void Game.trigger_death(&self, float[<3>][4] world_v) {
	if (self.is_dead || self.is_won || self.cheat_mode) return;

	self.is_dead = true;
	self.lives--;
	self.death_timer = 0.0f;
	audio::audio_play_explosion(1.5f);

	int[2][5] edges = {{0,1}, {0,2}, {1,3}, {2,3}, {1,2}};
	foreach (i, edge : edges) {
		Debris* d = &self.ship_pieces[i];
		d.p1 = world_v[edge[0]];
		d.p2 = world_v[edge[1]];
		d.active = true;

		float[<3>] mid = (d.p1 + d.p2) * 0.5f;
		float[<3>] out = (mid - self.ship_pos).normalize() * 0.05f;
		d.v1 = self.ship_vel + out;
		d.v2 = self.ship_vel + out * 1.5f;
	}

	for (int i = 0; i < 60; i++) {
		foreach (&p : self.particles) {
			if (p.life <= 0.0f) {
				p.pos = self.ship_pos;
				ulong h2 = wyhash2::hash(((char*)&i)[:int.sizeof], (ulong)self.frame);
				p.vel = {((float)(h2 & 0xFFu) / 128.0f - 1.0f) * 0.3f, 0,
						 ((float)((h2 >> 8) & 0xFFu) / 128.0f - 1.0f) * 0.3f};
				p.life = 1.0f + (float)(h2 % 50u) * 0.01f;
				break;
			}
		}
	}
}



fn void Game.reschedule_saucer(&self) {
	float factor = math::min(1.0f, (float)self.score / 60000.0f);
	uint base_wait = (uint)(600.0f * (1.0f - factor * 0.75f));
	uint rand_range = (uint)(600.0f * (1.0f - factor * 0.75f));
	if (base_wait < 120) base_wait = 120;
	if (rand_range < 120) rand_range = 120;

	self.next_saucer_frame = self.frame + base_wait + (uint)wyhash2::hash(((char*)&self.frame)[:uint.sizeof]) % rand_range;
}

fn void Game.trigger_saucer_death(&self, bool award_points) {
	if (!self.saucer.active) return;

	if (award_points) {
		self.score += (self.saucer.type == SaucerType.SMALL) ? 1000 : 200;
		if (self.score >= self.next_extra_life_score) {
			self.lives++;
			self.next_extra_life_score += 10000;
		}
	}

	self.saucer.active = false;
	self.reschedule_saucer();

	for (int i = 0; i < 30; i++) {
		foreach (&p : self.particles) {
			if (p.life <= 0.0f) {
				p.pos = self.saucer.pos;
				ulong h = wyhash2::hash(((char*)&i)[:int.sizeof], (ulong)self.frame);
				p.vel = {((float)(h & 0xFFu) / 128.0f - 1.0f) * 0.25f, 0,
						 ((float)((h >> 8) & 0xFFu) / 128.0f - 1.0f) * 0.25f};
				p.life = 0.8f;
				break;
			}
		}
	}
}

fn void Game.destroy_asteroid(&self, Asteroid* a, float[<3>] impact_vel, bool award_points) {
	if (!a.active) return;

	audio::audio_play_explosion(a.radius * 2.5f);
	a.active = false;

	if (award_points) {
		if (a.size == AsteroidSize.LARGE) {
			self.score += 20;
		} else if (a.size == AsteroidSize.MEDIUM) {
			self.score += 50;
		} else {
			self.score += 100;
		}

		if (self.score >= self.next_extra_life_score) {
			self.lives++;
			self.next_extra_life_score += 10000;
		}
	}

	if (a.size != AsteroidSize.SMALL) {
		int count = 0;
		float[<3>] dir = impact_vel.length_sq() > 0.0001f ? impact_vel.normalize() : (float[<3>]){1,0,0};
		float[<3>] perp = {-dir.z, 0, dir.x};

		float[<3>] parent_pos = a.pos;
		float[<3>] parent_vel = a.vel;
		AsteroidSize child_size = (AsteroidSize)((int)a.size - 1);

		for (usz i = 0; i < MAX_ASTEROIDS && count < 2; i++) {
			Asteroid* na = &self.asteroids[i];
			if (!na.active) {
				float side = (count == 0) ? 1.0f : -1.0f;
				float[<3>] n_vel = parent_vel * 1.2f + perp * (side * 0.05f);
				na.spawn(parent_pos, n_vel, child_size, (uint)wyhash2::hash(((char*)&i)[:usz.sizeof], (ulong)self.frame));
				count++;
			}
		}
	}

	for (int i = 0; i < 10; i++) {
		foreach (&p : self.particles) {
			if (p.life <= 0.0f) {
				p.pos = a.pos;
				ulong h = wyhash2::hash(((char*)&i)[:int.sizeof], (ulong)self.frame);
				p.vel = {((float)(h & 0xFFu) / 128.0f - 1.0f) * 0.15f, 0,
						 ((float)((h >> 8) & 0xFFu) / 128.0f - 1.0f) * 0.15f};
				p.life = 0.8f;
				break;
			}
		}
	}
}

fn void Game.spawn_wave(&self) {
	self.wave_notif_timer = 2.0f;
	ulong seed = (ulong)get_time_ns() ^ (ulong)self.frame;
	int count = 2 + self.wave * 2;
	if (count > 11) count = 11;

	for (usz i = 0; i < (usz)count; i++) {
		Asteroid* a = &self.asteroids[i];
		ulong h = wyhash2::hash(((char*)&i)[:usz.sizeof], seed);

		float angle = (float)(h % 360u) * 3.14159f / 180.0f;
		float dist = 6.0f + (float)((h >> 8) % 100u) * 0.1f;
		float[<3>] pos = {math::cos(angle) * dist, 0, math::sin(angle) * dist};
		float[<3>] vel = {((float)((h >> 16) & 0xFFu) / 255.0f - 0.5f) * (0.03f + (float)self.wave * 0.005f), 0,
						 ((float)((h >> 24) & 0xFFu) / 255.0f - 0.5f) * (0.03f + (float)self.wave * 0.005f)};

		a.spawn(pos, vel, AsteroidSize.LARGE, (uint)h);
	}
}

fn void Asteroid.spawn(&self, float[<3>] pos, float[<3>] vel, AsteroidSize size, uint seed) {
	self.active = true;
	self.pos = pos;
	self.vel = vel;
	self.size = size;

	self.radius = (float)((int)size + 1) * 0.4f;
	self.rot = 0;
	self.rot_vel = ((float)(seed % 100u) / 100.0f - 0.5f) * 0.1f;

	for (int j = 0; j < 8; j++) {
		float va = (float)j * 3.14159f * 2.0f / 8.0f;
		ulong vh = wyhash2::hash(((char*)&j)[:int.sizeof], (ulong)seed);
		float vr = self.radius * (0.7f + (float)(vh % 30u) * 0.02f);
		self.verts[j] = {math::cos(va) * vr, 0, math::sin(va) * vr};
	}
}

fn void apply_key(Input* input, rgfw::Key key, bool pressed) {
	switch (key) {
		case rgfw::Key.W:
		case rgfw::Key.UP:    input.forward  = pressed;
		case rgfw::Key.S:
		case rgfw::Key.DOWN:  input.back     = pressed;
		case rgfw::Key.A:
		case rgfw::Key.LEFT:  input.left     = pressed;
		case rgfw::Key.D:
		case rgfw::Key.RIGHT: input.right    = pressed;
		case rgfw::Key.SPACE: input.shoot    = pressed;
		case rgfw::Key.E:     input.hyperspace = pressed;
		case rgfw::Key.C:     input.cheat    = pressed;
		default:
	}
}



fn bool draw_pixel(Color* buf, usz w, usz h, int x, int y, Color c, bool check_collision) {
	if (x >= 0 && (usz)x < w && y >= 0 && (usz)y < h) {
		usz idx = (usz)y * w + (usz)x;
		if (check_collision) {
			Color t = buf[idx];
			if (t.x == ASTEROID_COLOR.x && t.y == ASTEROID_COLOR.y && t.z == ASTEROID_COLOR.z) return true;
			if (t.x == ENEMY_COLOR.x && t.y == ENEMY_COLOR.y && t.z == ENEMY_COLOR.z) return true;
		}
		buf[idx] = c;
	}
	return false;
}

fn bool draw_line(Color* buf, usz w, usz h, int x0, int y0, int x1, int y1, Color color, bool check_collision) {
	int dx = math::abs(x1 - x0);
	int dy = math::abs(y1 - y0);
	int sx = x0 < x1 ? 1 : -1;
	int sy = y0 < y1 ? 1 : -1;
	int err = dx - dy;
	bool hit = false;
	while (true) {
		if (draw_pixel(buf, w, h, x0, y0, color, check_collision)) hit = true;
		if (x0 == x1 && y0 == y1) break;
		int e2 = 2 * err;
		if (e2 > -dy) { err -= dy; x0 += sx; }
		if (e2 <  dx) { err += dx; y0 += sy; }
	}
	return hit;
}

fn void draw_star(Color* buf, usz w, usz h, int cx, int cy, int arm, Color color, bool check_collision) {
	draw_pixel(buf, w, h, cx, cy, color, check_collision);
	for (int i = -arm; i <= arm; i++) {
		draw_pixel(buf, w, h, cx + i, cy, color, check_collision);
		draw_pixel(buf, w, h, cx, cy + i, color, check_collision);
	}
}

fn float toroidal_offset(float val) {
	float w = WORLD_SIZE * 2.0f;
	return val - math::round(val / w) * w;
}

fn float[<2>] get_relative_pos(float wx, float wz, float[<3>] cam) {
	return {toroidal_offset(wx - cam.x), toroidal_offset(wz - cam.z)};
}

fn int[<2>] to_screen(float rel_x, float rel_z, float scale, usz w, usz h) {
	int sx = (int)(rel_x * scale) + (int)w / 2;
	int sy = (int)(rel_z * scale) + (int)h / 2;
	return {sx, sy};
}

fn int[<2>] project(float wx, float wz, float[<3>] cam, float scale, usz w, usz h) {
	float[<2>] rel = get_relative_pos(wx, wz, cam);
	return to_screen(rel.x, rel.y, scale, w, h);
}

fn float toroidal_dist_sq(float[<3>] p1, float[<3>] p2) {
	float[<2>] rel = get_relative_pos(p1.x, p1.z, p2);
	return rel.x * rel.x + rel.y * rel.y;
}


struct FontLine { float x1, y1, x2, y2; }

const FontLine[] F_0 = { {0,0,2,0}, {2,0,2,4}, {2,4,0,4}, {0,4,0,0} };
const FontLine[] F_1 = { {1,0,1,4} };
const FontLine[] F_2 = { {0,0,2,0}, {2,0,2,2}, {2,2,0,2}, {0,2,0,4}, {0,4,2,4} };
const FontLine[] F_3 = { {0,0,2,0}, {2,0,2,4}, {2,4,0,4}, {0,2,2,2} };
const FontLine[] F_4 = { {0,0,0,2}, {0,2,2,2}, {2,0,2,4} };
const FontLine[] F_5 = { {2,0,0,0}, {0,0,0,2}, {0,2,2,2}, {2,2,2,4}, {2,4,0,4} };
const FontLine[] F_6 = { {2,0,0,0}, {0,0,0,4}, {0,4,2,4}, {2,4,2,2}, {2,2,0,2} };
const FontLine[] F_7 = { {0,0,2,0}, {2,0,2,4} };
const FontLine[] F_8 = { {0,0,2,0}, {0,0,0,4}, {0,4,2,4}, {2,4,2,0}, {0,2,2,2} };
const FontLine[] F_9 = { {2,2,0,2}, {0,2,0,0}, {0,0,2,0}, {2,0,2,4} };
const FontLine[] F_G = { {2,0,0,0}, {0,0,0,4}, {0,4,2,4}, {2,4,2,2}, {1,2,2,2} };
const FontLine[] F_A = { {0,4,1,0}, {1,0,2,4}, {0.5,2,1.5,2} };
const FontLine[] F_M = { {0,4,0,0}, {0,0,1,1}, {1,1,2,0}, {2,0,2,4} };
const FontLine[] F_E = { {2,0,0,0}, {0,0,0,4}, {0,4,2,4}, {0,2,1.6,2} };
const FontLine[] F_O = { {0,0,2,0}, {2,0,2,4}, {2,4,0,4}, {0,4,0,0} };
const FontLine[] F_V = { {0,0,1,4}, {1,4,2,0} };
const FontLine[] F_R = { {0,4,0,0}, {0,0,2,0}, {2,0,2,2}, {2,2,0,2}, {1,2,2,4} };
const FontLine[] F_W = { {0,0,0,4}, {0,4,1,3}, {1,3,2,4}, {2,4,2,0} };
const FontLine[] F_S = { {2,0,0,0}, {0,0,0,2}, {0,2,2,2}, {2,2,2,4}, {0,4,2,4} };
const FontLine[] F_C = { {2,0,0,0}, {0,0,0,4}, {0,4,2,4} };
const FontLine[] F_H = { {0,0,0,4}, {2,0,2,4}, {0,2,2,2} };
const FontLine[] F_L = { {0,0,0,4}, {0,4,2,4} };
const FontLine[] F_I = { {1,0,1,4}, {0,0,2,0}, {0,4,2,4} };
const FontLine[] F_B = { {0,0,0,4}, {0,0,2,0}, {2,0,2,2}, {0,2,2,2}, {2,2,2,4}, {0,4,2,4} };
const FontLine[] F_T = { {0,0,2,0}, {1,0,1,4} };
const FontLine[] F_P = { {0,4,0,0}, {0,0,2,0}, {2,0,2,2}, {2,2,0,2} };
const FontLine[] F_U = { {0,0,0,4}, {0,4,2,4}, {2,4,2,0} };
const FontLine[] F_D = { {0,0,0,4}, {0,0,1.5,0}, {1.5,0,2,0.5}, {2,0.5,2,3.5}, {2,3.5,1.5,4}, {1.5,4,0,4} };
const FontLine[] F_N = { {0,4,0,0}, {0,0,2,4}, {2,4,2,0} };
const FontLine[] F_SPACE = { };

const FontLine[][30] FONT_DATA = {
	F_0, F_1, F_2, F_3, F_4, F_5, F_6, F_7, F_8, F_9,
	F_G, F_A, F_M, F_E, F_O, F_V, F_R, F_W, F_S, F_C,
	F_H, F_L, F_I, F_B, F_T, F_P, F_U, F_D, F_N, F_SPACE
};

fn void draw_text(Color* buf, usz w, usz h, int x, int y, int size, char* str, Color c) {
	int cur_x = x;
	for (usz i = 0; str[i] != '\0'; i++) {
		int idx = -1;
		switch (str[i]) {
			case '0'..'9': idx = (int)(str[i] - '0');
			case 'G': idx = 10;
			case 'A': idx = 11;
			case 'M': idx = 12;
			case 'E': idx = 13;
			case 'O': idx = 14;
			case 'V': idx = 15;
			case 'R': idx = 16;
			case 'W': idx = 17;
			case 'S': idx = 18;
			case 'C': idx = 19;
			case 'H': idx = 20;
			case 'L': idx = 21;
			case 'I': idx = 22;
			case 'B': idx = 23;
			case 'T': idx = 24;
			case 'P': idx = 25;
			case 'U': idx = 26;
			case 'D': idx = 27;
			case 'N': idx = 28;
			default: break;
		}

		if (idx != -1) {
			for (usz l = 0; l < FONT_DATA[idx].len; l++) {
				FontLine line = FONT_DATA[idx][l];
				int x1 = cur_x + (int)(line.x1 * (float)size);
				int y1 = y + (int)(line.y1 * (float)size);
				int x2 = cur_x + (int)(line.x2 * (float)size);
				int y2 = y + (int)(line.y2 * (float)size);
				draw_line(buf, w, h, x1, y1, x2, y2, c, false);
			}
		}
		cur_x += size * 4;
	}
}

fn void wrap(float[<3>]* pos) {
	if (pos.x >  WORLD_SIZE) pos.x -= WORLD_SIZE * 2;
	if (pos.x < -WORLD_SIZE) pos.x += WORLD_SIZE * 2;
	if (pos.z >  WORLD_SIZE) pos.z -= WORLD_SIZE * 2;
	if (pos.z < -WORLD_SIZE) pos.z += WORLD_SIZE * 2;
}

fn void update(Game* g) {
	if (g.paused) return;
	g.frame++;
	float[<3>] ship_fwd = g.ship_rot * (float[<3>]){0, 0, 1};

	static bool cheat_last = false;
	if (g.input.cheat && !cheat_last) {
		g.cheat_mode = !g.cheat_mode;
	}
	cheat_last = g.input.cheat;

	if (g.shoot_cooldown > 0) g.shoot_cooldown--;
	if (g.input.shoot && g.shoot_cooldown == 0) {
		foreach (&b : g.bullets) {
			if (b.life <= 0) {
				b.pos  = g.ship_pos + ship_fwd * 0.6f;
				if (g.cheat_mode) {
					b.vel  = ship_fwd * 0.8f;
					b.life = 180;
					g.shoot_cooldown = 4;
				} else {
					b.vel  = ship_fwd * 0.3f;
					b.life = 60;
					g.shoot_cooldown = 15;
				}
				b.from_ship = true;
				audio::audio_play_laser();
				break;
			}
		}
	}

	audio::audio_set_thrust(g.input.forward);
	if (g.input.forward) {
		g.ship_vel += ship_fwd * g.thrust_acc;

		float[<3>] back_pos = g.ship_pos + (g.ship_rot * (float[<3>]){0, 0, -0.6f});
		for (int i = 0; i < 2; i++) {
			foreach (&p : g.particles) {
				if (p.life <= 0.0f) {
					p.pos = back_pos;
					ulong rf = wyhash2::hash(((char*)&g.frame)[:uint.sizeof], (ulong)i);
					float vx = ((float)(rf & 0xFFu) / 255.0f - 0.5f) * 0.05f;
					float vz = ((float)((rf >> 8) & 0xFFu) / 255.0f - 0.5f) * 0.05f;
					p.vel = (ship_fwd * -0.1f) + (float[<3>]){vx, 0, vz};
					p.life = 0.5f + ((float)((rf >> 16) & 0xFFu) / 255.0f) * 0.5f;
					break;
				}
			}
		}
	}

	float drag = g.input.back ? 0.94f : 0.985f;
	g.ship_vel *= drag;

	g.ship_pos += g.ship_vel;

	if (g.input.left)    g.ship_rot = g.ship_rot * quaternion::from_axis_angle({0, 1, 0},  g.rot_speed);
	if (g.input.right)   g.ship_rot = g.ship_rot * quaternion::from_axis_angle({0, 1, 0}, -g.rot_speed);

	static bool hyperspace_last = false;
	if (g.input.hyperspace && !hyperspace_last && !g.is_dead && !g.is_won) {
		for (int i = 0; i < 30; i++) {
			foreach (&p : g.particles) {
				if (p.life <= 0.0f) {
					p.pos = g.ship_pos;
					ulong h = wyhash2::hash(((char*)&i)[:int.sizeof], (ulong)(g.frame + (uint)get_time_ns()));
					p.vel = {((float)(h & 0xFFu) / 128.0f - 1.0f) * 0.4f, 0,
							 ((float)((h >> 8) & 0xFFu) / 128.0f - 1.0f) * 0.4f};
					p.life = 0.5f;
					break;
				}
			}
		}

		ulong hx = wyhash2::hash(((char*)&g.frame)[:uint.sizeof], (ulong)get_time_ns());

		if ((hx % 100u) < 10u) {
			float[<3>][4] boom_v;
			foreach (vi, v : SHIP_VERTS) boom_v[vi] = g.ship_pos + (g.ship_rot * v);
			g.trigger_death(boom_v);

			foreach (&d : g.ship_pieces) {
				if (d.active) {
					d.v1 = {(float)((hx >> 8) & 0xFFu)/255.02f - 0.5f, 0, (float)((hx >> 16) & 0xFFu)/255.0f - 0.5f};
					d.v2 = d.v1 * 1.2f;
				}
			}
		} else {
			g.ship_pos.x = ((float)(hx & 0xFFFFu) / 65535.0f - 0.5f) * WORLD_SIZE * 2.0f;
			g.ship_pos.z = ((float)((hx >> 16) & 0xFFFFu) / 65535.0f - 0.5f) * WORLD_SIZE * 2.0f;
			g.ship_vel = {0, 0, 0};

			for (int i = 0; i < 30; i++) {
				foreach (&p : g.particles) {
					if (p.life <= 0.0f) {
						p.pos = g.ship_pos;
						ulong ha = wyhash2::hash(((char*)&i)[:int.sizeof], (ulong)g.frame);
						p.vel = {((float)(ha & 0xFFu) / 128.0f - 1.0f) * 0.2f, 0,
								 ((float)((ha >> 8) & 0xFFu) / 128.0f - 1.0f) * 0.2f};
						p.life = 0.6f;
						break;
					}
				}
			}
		}
	}
	hyperspace_last = g.input.hyperspace;

	if (!g.saucer.active && !g.game_over && g.frame > g.next_saucer_frame) {
		g.saucer.active = true;
		g.saucer.type = (g.score < 40000 && (g.frame % 2 != 0)) ? SaucerType.BIG : SaucerType.SMALL;
		g.saucer.pos = {(float)((g.frame % 2 == 0) ? -WORLD_SIZE : WORLD_SIZE), 0, (float)((g.frame / 200u) % 10u) - 5.0f};
		g.saucer.vel = {(g.saucer.pos.x < 0) ? 0.08f : -0.08f, 0, 0};
		g.saucer.shoot_timer = 60;
	}

	if (g.saucer.active) {
		g.saucer.pos += g.saucer.vel;
		if (math::abs(g.saucer.pos.x) > WORLD_SIZE + 1.0f) {
			g.saucer.active = false;
			g.reschedule_saucer();
		}

		g.saucer.shoot_timer--;
		if (g.saucer.shoot_timer <= 0) {
			g.saucer.shoot_timer = g.saucer.type == SaucerType.SMALL ? 90.0f : 120.0f;
			foreach (&b : g.bullets) {
				if (b.life <= 0) {
					b.pos = g.saucer.pos;
					float[<3>] target_dir;
					if (g.saucer.type == SaucerType.SMALL) {
						target_dir = (g.ship_pos - g.saucer.pos).normalize();
						float inaccuracy = math::max(0.0f, 0.4f - (float)g.score / 100000.0f);
						ulong rh = wyhash2::hash(((char*)&g.frame)[:uint.sizeof]);
						target_dir.x += ((float)(rh & 0xFFu) / 255.0f - 0.5f) * inaccuracy;
						target_dir.z += ((float)((rh >> 8) & 0xFFu) / 255.0f - 0.5f) * inaccuracy;
						target_dir = target_dir.normalize();
					} else {
						ulong rh = wyhash2::hash(((char*)&g.frame)[:uint.sizeof]);
						float ra = (float)(rh % 360u) * 3.14159f / 180.0f;
						target_dir = {math::cos(ra), 0, math::sin(ra)};
					}
					b.vel = target_dir * 0.2f;
					b.life = 120;
					b.from_ship = false;
					break;
				}
			}
		}

		foreach (&a : g.asteroids) {
			if (!a.active) continue;
			float dist_sq = toroidal_dist_sq(g.saucer.pos, a.pos);
			float limit = a.radius + (g.saucer.type == SaucerType.SMALL ? 0.3f : 0.6f);
			if (dist_sq < limit * limit) {
				g.destroy_asteroid(a, g.saucer.vel, false);
				g.trigger_saucer_death(false);
				break;
			}
		}
	}

	wrap(&g.ship_pos);

	foreach (&p : g.particles) if (p.life > 0.0f) { p.pos += p.vel; p.life -= 0.02f; }
	foreach (&b : g.bullets)   if (b.life > 0.0f) { b.pos += b.vel; wrap(&b.pos); b.life--; }
	foreach (&a : g.asteroids) {
		if (!a.active) continue;
		a.pos += a.vel;
		a.rot += a.rot_vel;
		wrap(&a.pos);
	}

	foreach (&d : g.ship_pieces) {
		if (!d.active) continue;
		d.p1 += d.v1;
		d.p2 += d.v2;
	}

	if (g.game_over) {
		if (g.input.shoot) g.init(true);
		return;
	}

	if (g.is_dead) {
		g.death_timer += 0.016f;
		if (g.death_timer > 2.0f) {
			if (g.lives > 0) {
				g.init(false);
			} else {
				g.game_over = true;
				if (g.score > g.best_score) {
					g.best_score = g.score;
					g.save_best_score();
				}
			}
			return;
		}
	}

	if (!g.is_dead && !g.is_won && !g.saucer.active) {
		bool any_asteroid = false;
		foreach (a : g.asteroids) if (a.active) { any_asteroid = true; break; }
		if (!any_asteroid) g.is_won = true;
	}

	if (g.is_won) {
		g.win_timer += 0.016f;

		// Victory fireworks
		if (g.win_timer < 1.0f && g.frame % 10 == 0) {
			float[<3>] firework_pos = g.ship_pos + (float[<3>]){(float)(g.frame % 7u) - 3.5f, 0, (float)((g.frame / 7u) % 7u) - 3.5f};
			for (int i = 0; i < 20; i++) {
				foreach (&p : g.particles) {
					if (p.life <= 0.0f) {
						p.pos = firework_pos;
						ulong h = wyhash2::hash(((char*)&i)[:int.sizeof], (ulong)g.frame);
						p.vel = {((float)(h & 0xFFu) / 128.0f - 1.0f) * 0.2f, 0,
								 ((float)((h >> 8) & 0xFFu) / 128.0f - 1.0f) * 0.2f};
						p.life = 1.0f;
						break;
					}
				}
			}
		}

		if (g.win_timer > 4.0f) {
			g.is_won = false;
			g.win_timer = 0.0f;
			g.wave++;
			g.spawn_wave();
			return;
		}
	} else if (g.wave_notif_timer > 0.0f) {
		g.wave_notif_timer -= 0.016f;
	}

	foreach (&b : g.bullets) {
		if (b.life <= 0) continue;
		foreach (&a : g.asteroids) {
			if (!a.active) continue;
			float dist_sq = toroidal_dist_sq(b.pos, a.pos);
			if (dist_sq < a.radius * a.radius) {
				b.life = 0;
				g.destroy_asteroid(a, b.vel, b.from_ship);
				break;
			}
		}
		if (g.saucer.active && b.from_ship) {
			float sd = toroidal_dist_sq(b.pos, g.saucer.pos);
			if (sd < 0.8f * 0.8f) {
				b.life = 0;
				g.trigger_saucer_death(true);
				break;
			}
		}
	}

	float dx = toroidal_offset(g.ship_pos.x - g.cam_pos.x);
	float dz = toroidal_offset(g.ship_pos.z - g.cam_pos.z);
	g.cam_pos.x += dx * g.cam_ease;
	g.cam_pos.z += dz * g.cam_ease;
	wrap(&g.cam_pos);

	float speed_mag = g.ship_vel.length();
	float target_scale = 45.0f - speed_mag * 60.0f;
	if (target_scale < 30.0f) target_scale = 30.0f;
	g.scale += (target_scale - g.scale) * 0.05f;

	audio::audio_set_saucer(g.saucer.active, g.saucer.type == SaucerType.BIG);

	if (!g.is_dead && !g.is_won && !g.game_over) {
		g.thump_timer++;
		if (g.thump_timer >= g.thump_interval) {
			g.thump_timer = 0;
			g.thump_high = !g.thump_high;
			audio::audio_play_thump(g.thump_high);
		}

		uint active_count = 0;
		foreach (aIdx, &a : g.asteroids) if (a.active) active_count++;

		float f = math::min(1.0f, (float)active_count / 40.0f);
		g.thump_interval = (uint)(20.0f + f * 40.0f);
	} else {
		audio::audio_set_saucer(false, false);
	}
}

fn void draw_grid(Game* g, Color* buf, usz w, usz h) {
	float spacing = 3.0f;
	int cell_x = (int)(g.cam_pos.x / spacing);
	int cell_z = (int)(g.cam_pos.z / spacing);

	for (int gx = cell_x - 8; gx <= cell_x + 8; gx++) {
		for (int gz = cell_z - 8; gz <= cell_z + 8; gz++) {
			int[2] key = {gx, gz};
			ulong hv = wyhash2::hash(((char*)&key)[:int[2].sizeof]);

			float ox = ((float)(hv & 0xFFu) / 255.0f - 0.5f) * spacing * 1.7f;
			float oz = ((float)((hv >> 8) & 0xFFu) / 255.0f - 0.5f) * spacing * 1.7f;
			float wx = (float)gx * spacing + ox;
			float wz = (float)gz * spacing + oz;

			int arm = 2 + (int)((hv >> 16) % 3u);

			char b  = (char)(90 + (hv >> 24) % 70u);
			char rb = (char)((ulong)b * 60u / 100u);
			Color c = {rb, rb, b, 255};

			int[<2>] s_pos = project(wx, wz, g.cam_pos, g.scale, w, h);
			draw_star(buf, w, h, s_pos[0], s_pos[1], arm, c, false);
		}
	}
}

fn void draw_ship(Game* g, Color* buf, usz w, usz h) {
	if (g.is_dead) {
		foreach (&d : g.ship_pieces) {
			if (!d.active) continue;
			float[<2>] rel1 = get_relative_pos(d.p1.x, d.p1.z, g.cam_pos);
			int[<2>] s1 = to_screen(rel1.x, rel1.y, g.scale, w, h);

			float dx = d.p2.x - d.p1.x;
			float dz = d.p2.z - d.p1.z;
			int[<2>] s2 = to_screen(rel1.x + dx, rel1.y + dz, g.scale, w, h);

			draw_line(buf, w, h, s1[0], s1[1], s2[0], s2[1], GREEN, false);
		}
		return;
	}

	float[<2>] rel_center = get_relative_pos(g.ship_pos.x, g.ship_pos.z, g.cam_pos);
	float[<3>][4] world_v;
	int[2][4] s;

	foreach (i, v : SHIP_VERTS) {
		float[<3>] lv = g.ship_rot * v;
		world_v[i] = lv + g.ship_pos;
		int[<2>] p = to_screen(rel_center.x + lv.x, rel_center.y + lv.z, g.scale, w, h);
		s[i] = {p[0], p[1]};
	}

	bool hit = false;
	if (draw_line(buf, w, h, s[0][0], s[0][1], s[1][0], s[1][1], GREEN, true)) hit = true;
	if (draw_line(buf, w, h, s[0][0], s[0][1], s[2][0], s[2][1], GREEN, true)) hit = true;
	if (draw_line(buf, w, h, s[1][0], s[1][1], s[3][0], s[3][1], GREEN, true)) hit = true;
	if (draw_line(buf, w, h, s[2][0], s[2][1], s[3][0], s[3][1], GREEN, true)) hit = true;
	if (draw_line(buf, w, h, s[1][0], s[1][1], s[2][0], s[2][1], GREEN, true)) hit = true;

	if (hit) {
		g.trigger_death(world_v);
	}
}

fn void draw_particles(Game* g, Color* buf, usz w, usz h) {
	foreach (&p : g.particles) {
		if (p.life <= 0.0f) continue;
		int[<2>] s = project(p.pos.x, p.pos.z, g.cam_pos, g.scale, w, h);

		char r, gr, bv;
		if (p.life > 0.7f) {
			r = 255; gr = 200; bv = 50;
		} else if (p.life > 0.4f) {
			r = 255; gr = 100; bv = 20;
		} else {
			char gray = (char)(p.life * 2.0f * 100.0f);
			r = gray; gr = gray; bv = gray;
		}

		Color c = {r, gr, bv, 255};
		draw_pixel(buf, w, h, s[0], s[1], c, false);
		if (p.life > 0.8f) draw_star(buf, w, h, s[0], s[1], 1, c, false);
	}
}

fn void draw_bullets(Game* g, Color* buf, usz w, usz h) {
	int arm = (int)(g.scale * 0.025f);
	if (arm < 1) arm = 1;

	foreach (&b : g.bullets) {
		if (b.life <= 0) continue;
		float[<2>] rel1 = get_relative_pos(b.pos.x, b.pos.z, g.cam_pos);
		int[<2>] s1 = to_screen(rel1.x, rel1.y, g.scale, w, h);
		Color c = b.from_ship ? WHITE : ENEMY_COLOR;

		float dx = b.vel.x * 1.25f;
		float dz = b.vel.z * 1.25f;
		int[<2>] s2 = to_screen(rel1.x - dx, rel1.y - dz, g.scale, w, h);

		draw_line(buf, w, h, s1[0], s1[1], s2[0], s2[1], c, false);
		draw_star(buf, w, h, s1[0], s1[1], arm, c, false);
	}
}

fn void draw_asteroids(Game* g, Color* buf, usz w, usz h) {
	foreach (&a : g.asteroids) {
		if (!a.active) continue;

		float[<2>] rel_center = get_relative_pos(a.pos.x, a.pos.z, g.cam_pos);
		int[2][8] s;
		Quaternionf rotation = quaternion::from_axis_angle({0, 1, 0}, a.rot);

		for (int i = 0; i < 8; i++) {
			float[<3>] local_v = rotation * a.verts[i];
			int[<2>] pv = to_screen(rel_center.x + local_v.x, rel_center.y + local_v.z, g.scale, w, h);
			s[i] = {pv[0], pv[1]};
		}

		for (int i = 0; i < 8; i++) {
			int next = (i + 1) % 8;
			draw_line(buf, w, h, s[i][0], s[i][1], s[next][0], s[next][1], ASTEROID_COLOR, false);
		}
	}
}

fn void draw_saucer(Game* g, Color* buf, usz w, usz h) {
	if (!g.saucer.active) return;
	float[<2>] rel = get_relative_pos(g.saucer.pos.x, g.saucer.pos.z, g.cam_pos);
	float s = g.saucer.type == SaucerType.SMALL ? 0.3f : 0.6f;

	int[<2>] p1 = to_screen(rel.x - s, rel.y, g.scale, w, h);
	int[<2>] p2 = to_screen(rel.x + s, rel.y, g.scale, w, h);
	int[<2>] p3 = to_screen(rel.x - s*0.5f, rel.y - s*0.5f, g.scale, w, h);
	int[<2>] p4 = to_screen(rel.x + s*0.5f, rel.y - s*0.5f, g.scale, w, h);
	int[<2>] p5 = to_screen(rel.x - s*0.5f, rel.y + s*0.5f, g.scale, w, h);
	int[<2>] p6 = to_screen(rel.x + s*0.5f, rel.y + s*0.5f, g.scale, w, h);

	draw_line(buf, w, h, p1.x, p1.y, p2.x, p2.y, ENEMY_COLOR, false);
	draw_line(buf, w, h, p3.x, p3.y, p4.x, p4.y, ENEMY_COLOR, false);
	draw_line(buf, w, h, p5.x, p5.y, p6.x, p6.y, ENEMY_COLOR, false);
	draw_line(buf, w, h, p1.x, p1.y, p3.x, p3.y, ENEMY_COLOR, false);
	draw_line(buf, w, h, p2.x, p2.y, p4.x, p4.y, ENEMY_COLOR, false);
	draw_line(buf, w, h, p1.x, p1.y, p5.x, p5.y, ENEMY_COLOR, false);
	draw_line(buf, w, h, p2.x, p2.y, p6.x, p6.y, ENEMY_COLOR, false);
}

fn void draw_hud(Game* g, Color* buf, usz w, usz h) {
	draw_text(buf, w, h, 50, 20, 4, "SCORE", WHITE);
	char[32] score_str;
	io::bprintf(score_str[..], "%d", g.score);
	draw_text(buf, w, h, 50, 50, 8, (char*)&score_str, WHITE);
	draw_text(buf, w, h, (int)w/2 - 50, 25, 3, "BEST", WHITE);
	char[32] best_str;
	io::bprintf(best_str[..], "%d", g.best_score);
	draw_text(buf, w, h, (int)w/2 - 50, 50, 5, (char*)&best_str, WHITE);

	for (int i = 0; i < g.lives; i++) {
		int lx = 50 + i * 30;
		int ly = 120;
		draw_line(buf, w, h, lx, ly, lx+10, ly+20, GREEN, false);
		draw_line(buf, w, h, lx, ly, lx-10, ly+20, GREEN, false);
		draw_line(buf, w, h, lx+10, ly+20, lx-10, ly+20, GREEN, false);
	}

	if (g.game_over) {
		draw_text(buf, w, h, (int)w/2 - 180, (int)h/2 - 50, 15, "GAME OVER", WHITE);
	} else if (g.paused) {
		draw_text(buf, w, h, (int)w/2 - 120, (int)h/2 - 50, 15, "PAUSED", WHITE);
	}

	if (g.wave_notif_timer > 0.0f) {
		char[32] wave_str;
		io::bprintf(wave_str[..], "WAVE %d", g.wave);
		draw_text(buf, w, h, (int)w/2 - 100, (int)h/2 - 100, 10, (char*)&wave_str, WHITE);
	} else if (g.is_won && g.win_timer > 1.0f) {
		char[32] wave_str;
		io::bprintf(wave_str[..], "WAVE %d", g.wave + 1);
		draw_text(buf, w, h, (int)w/2 - 100, (int)h/2 - 100, 10, (char*)&wave_str, WHITE);
	}

	if (g.cheat_mode) {
		draw_text(buf, w, h, (int)w - 180, 20, 5, "CHEAT", ENEMY_COLOR);
	}
}

struct WebContext {
	Game g;
	rgfw::Window* win;
	rgfw::Surface* surface;
	Color* buffer;
	usz w, h;
	double accumulator;
	long last_time;
	rgfw::Event event;
}

WebContext web_ctx;

extern fn double emscripten_get_now() @callconv("cdecl");

fn long get_time_ns() {
	$if env::WASM:
		return (long)(emscripten_get_now() * 1000000.0);
	$else
		return (long)clock::now();
	$endif
}

fn void Game.run_frame(&self, double dt, double* accumulator, Color* buffer, usz w, usz h, rgfw::Window* win, rgfw::Surface* surface) {
	const double DT = 1.0 / 60.0;
	*accumulator += dt;

	while (*accumulator >= DT) {
		update(self);
		*accumulator -= DT;
	}

	if (self.score > self.best_score) {
		self.best_score = self.score;
		$if (env::WASM):
			self.save_best_score();
		$endif
	}

	buffer[:w * h] = BLACK;

	draw_grid(self, buffer, w, h);
	draw_particles(self, buffer, w, h);
	draw_bullets(self, buffer, w, h);
	draw_asteroids(self, buffer, w, h);
	draw_saucer(self, buffer, w, h);
	draw_ship(self, buffer, w, h);
	draw_hud(self, buffer, w, h);

	// Game Over screen tint
	if (self.is_dead || self.game_over) {
		float tint = self.game_over ? 1.0f : self.death_timer;
		if (tint > 1.0f) tint = 1.0f;
		char r_add = (char)(tint * 80.0f);
		foreach (&c : buffer[:w * h]) {
			int r = (int)c.x + (int)r_add;
			if (r > 255) r = 255;
			c.x = (char)r;
		}
	}

	// Win screen wash
	if (self.is_won) {
		float val_f = 0.0f;
		if (self.win_timer < 1.0f) {
			val_f = (self.win_timer / 1.0f) * 120.0f;
		} else {
			val_f = (1.0f - (self.win_timer - 1.0f) / 3.0f) * 120.0f;
		}
		if (val_f < 0) val_f = 0;
		char val = (char)val_f;
		foreach (&c : buffer[:w * h]) {
			uint r = (uint)c.x + (uint)val; if (r > 255) r = 255; c.x = (char)r;
			uint gr = (uint)c.y + (uint)val; if (gr > 255) gr = 255; c.y = (char)gr;
			uint bl = (uint)c.z + (uint)val; if (bl > 255) bl = 255; c.z = (char)bl;
		}
	}

	rgfw::window_blit_surface(win, surface);
}

fn void web_frame(void* arg) @export("web_frame") @callconv("cdecl") {
	WebContext* ctx = (WebContext*)arg;

	int rw, rh;
	rgfw::window_get_size(ctx.win, &rw, &rh);
	if (rw > 0 && rh > 0 && ((usz)rw != ctx.w || (usz)rh != ctx.h)) {
		ctx.w = (usz)rw;
		ctx.h = (usz)rh;
		ctx.g.scale = (float)ctx.h / 4.0f;
		mem::free(ctx.buffer);
		ctx.buffer = (Color*)mem::malloc(ctx.w * ctx.h * Color.sizeof);
		rgfw::surface_free(ctx.surface);
		ctx.surface = rgfw::window_create_surface(ctx.win, (char*)ctx.buffer, ctx.w, ctx.h, rgfw::Format.RGBA8);
	}

	long current_time = get_time_ns();
	double dt = (double)(current_time - ctx.last_time) / 1_000_000_000.0;
	if (dt > 0.25) dt = 0.25;
	ctx.last_time = current_time;

	while (rgfw::window_check_event(ctx.win, &ctx.event)) {
		switch (ctx.event.type) {
			case rgfw::EventType.QUIT: return;
			case rgfw::EventType.KEY_PRESSED:
				if (ctx.event.key.value == rgfw::Key.P) ctx.g.paused = !ctx.g.paused;
				apply_key(&ctx.g.input, ctx.event.key.value, true);
			case rgfw::EventType.KEY_RELEASED:
				apply_key(&ctx.g.input, ctx.event.key.value, false);
			default:
		}
	}

	ctx.g.run_frame(dt, &ctx.accumulator, ctx.buffer, ctx.w, ctx.h, ctx.win, ctx.surface);
}

alias EmMainLoopFunc = fn void(void*) @callconv("cdecl");
extern fn void emscripten_set_main_loop_arg(EmMainLoopFunc func, void* arg, int fps, int simulate_infinite_loop) @callconv("cdecl");
extern fn void emscripten_run_script(char* s) @callconv("cdecl");
extern fn int emscripten_run_script_int(char* s) @callconv("cdecl");

extern fn void trap() @extern("abort") @callconv("cdecl") @if(env::WASM);

fn void my_panic(String msg, String file, String func, uint line) @export("my_panic") @callconv("cdecl") @if(env::WASM) {
	io::printn("!!! PANIC !!!");
	io::printn(msg);
	trap();
}

fn int main(int argc, char** args) {
	$if (env::WASM):
		builtin::panic = &my_panic;
	$endif

	io::printn("Main started");

	if (audio::audio_init() != 0) {
		io::printn("Failed to initialize audio!");
	}
	$if (!env::WASM):
		defer audio::audio_terminate();
	$endif

	$if (env::LINUX):
		rgfw::use_wayland(true);
	$endif

	uint flags = (uint)(rgfw::WindowFlags.HIDE_MOUSE |
		rgfw::WindowFlags.ALLOW_DND |
		rgfw::WindowFlags.FOCUS |
		rgfw::WindowFlags.FOCUS_ON_SHOW);

	$if (!env::WASM):
		flags |= (uint)rgfw::WindowFlags.FULLSCREEN;
	$endif

	usz w = 1920;
	usz h = 1080;

	rgfw::Window* win = rgfw::create_window("Software Asteroids", 0, 0, (int)w, (int)h, (rgfw::WindowFlags)flags);

	if (!win) { io::printn("Failed to create window!"); return 1; }
	int rw, rh;
	rgfw::window_get_size(win, &rw, &rh);
	if (rw > 0 && rh > 0) {
		w = (usz)rw;
		h = (usz)rh;
	}

	Color* buffer = (Color*)mem::malloc(w * h * Color.sizeof);
	if (!buffer) { io::printn("Failed to allocate buffer"); return 1; }
	$if (!env::WASM):
		defer mem::free(buffer);
	$endif

	rgfw::Surface* surface = rgfw::window_create_surface(win, (char*)buffer, w, h, rgfw::Format.RGBA8);
	if (!surface) { io::printn("Failed to create surface!"); return 1; }
	$if (!env::WASM):
		defer rgfw::surface_free(surface);
	$endif

	$if (env::LINUX):
		rgfw::window_set_fullscreen(win, true);
	$endif

	if (env::WASM) {
		web_ctx.g.load_best_score();
		web_ctx.g.init(true);
		web_ctx.g.scale = (float)h / 4.0f;
		web_ctx.win = win;
		web_ctx.surface = surface;
		web_ctx.buffer = buffer;
		web_ctx.w = w;
		web_ctx.h = h;
		web_ctx.last_time = get_time_ns();
		web_ctx.accumulator = 0.0;
		emscripten_set_main_loop_arg(&web_frame, &web_ctx, 60, 0);
		return 0;
	}

	Game g;
	g.load_best_score();
	g.init(true);
	g.scale = (float)h / 4.0f;

	rgfw::Event event;

	const double DT = 1.0 / 60.0;
	const long DT_NS = (long)(DT * 1_000_000_000.0);
	double accumulator = 0.0;
	long last_time = get_time_ns();

	while MAINLOOP: (!rgfw::window_should_close(win)) {
		long current_time = get_time_ns();
		double dt = (double)(current_time - last_time) / 1_000_000_000.0;
		if (dt > 0.25) dt = 0.25;
		last_time = current_time;

		while (rgfw::window_check_event(win, &event)) {
			switch (event.type) {
				case rgfw::EventType.QUIT: break MAINLOOP;
				case rgfw::EventType.KEY_PRESSED:
					if (event.key.value == rgfw::Key.ESCAPE) break MAINLOOP;
					if (event.key.value == rgfw::Key.P) g.paused = !g.paused;
					apply_key(&g.input, event.key.value, true);
				case rgfw::EventType.KEY_RELEASED:
					apply_key(&g.input, event.key.value, false);
				default:
			}
		}

		g.run_frame(dt, &accumulator, buffer, w, h, win, surface);

		$if (!env::WASM):
			long now = get_time_ns();
			long work_done = now - last_time;
			long target = g.paused ? (long)100_000_000 : DT_NS;
			if (work_done < target) {
				thread::sleep_ns((NanoDuration)(target - work_done));
			}
		$endif
	}

	g.save_best_score();
	return 0;
}

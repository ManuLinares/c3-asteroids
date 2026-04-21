module asteroids;

import std;
import rgfw;
import audio;

typedef Color = char[<4>];
alias IVec2 = int[<2>];
alias UszVec2 = usz[<2>];

const float NEON_GLOW_INTENSITY_1 = 0.8f;
const float NEON_GLOW_INTENSITY_2 = 0.4f;
const int   NEON_LINE_THICKNESS   = 1;

const Color BLACK = {0, 0, 0, 255};
const Color GREEN = {0, 255, 0, 255};
const Color WHITE          = {255, 255, 255, 255};
const Color ASTEROID_COLOR = {160, 160, 160, 255};
const Color ENEMY_COLOR    = {255, 100, 255, 255};
const int PROJECT_ERROR     = -1000000;

const Vec3[5] SHIP_VERTS = {
	{0.0f,  0.0f,  1.0f},
	{-0.6f, -0.3f, -0.6f},
	{0.6f,  -0.3f, -0.6f},
	{0.0f,  0.3f,  -0.6f},
	{0.0f,  0.0f,  -0.2f}
};

const Vec3[8] SAUCER_VERTS = {
	{-1.0f, 0.0f,  0.0f},
	{-0.5f, 0.0f, -0.8f},
	{ 0.5f, 0.0f, -0.8f},
	{ 1.0f, 0.0f,  0.0f},
	{ 0.5f, 0.0f,  0.8f},
	{-0.5f, 0.0f,  0.8f},
	{ 0.0f, 0.5f,  0.0f},
	{ 0.0f, -0.5f, 0.0f}
};

const int[2][] SHIP_LINES     = {
	{0,1}, {0,2}, {0,3},
	{1,2}, {2,3}, {3,1},
	{1,4}, {2,4}, {3,4}
};
const int[2][] SAUCER_LINES   = {
	{0,1}, {1,2}, {2,3}, {3,4}, {4,5}, {5,0},
	{6,0}, {6,1}, {6,2}, {6,3}, {6,4}, {6,5},
	{7,0}, {7,1}, {7,2}, {7,3}, {7,4}, {7,5}
};
const int[2][] ASTEROID_LINES = {
	{0,1}, {1,2}, {2,3}, {3,4}, {4,5}, {5,0},
	{6,7}, {7,8}, {8,9}, {9,10}, {10,11}, {11,6},
	{0,6}, {1,7}, {2,8}, {3,9}, {4,10}, {5,11}
};

bitstruct Input : ushort {
	bool forward;
	bool back;
	bool left;
	bool right;
	bool shoot;
	bool hyperspace;
	bool cheat;
	bool cam_yaw_l;
	bool cam_yaw_r;
	bool cam_pitch_u;
	bool cam_pitch_d;
}

struct Particle {
	Vec3 pos;
	Vec3 vel;
	float life;
}

struct Bullet {
	Vec3 pos;
	Vec3 vel;
	float life;
	bool from_ship;
}

struct Debris {
	Vec3 p1;
	Vec3 p2;
	Vec3 v1;
	Vec3 v2;
	bool active;
}

enum AsteroidSize : int(int score, float radius) {
	SMALL { 100, 0.4f },
	MEDIUM { 50, 0.8f },
	LARGE { 20, 1.2f }
}

struct Asteroid {
	Vec3 pos;
	Vec3 vel;
	float radius;
	float rot;
	float rot_vel;
	Vec3[12] verts;
	AsteroidSize size;
	bool active;
}

enum SaucerType : int(int score, float draw_rad, float coll_rad, float cooldown) {
	BIG { 200, 1.2f, 0.6f, 120.0f },
	SMALL { 1000, 0.35f, 0.3f, 90.0f }
}

struct Saucer {
	Vec3 pos;
	Vec3 vel;
	SaucerType type;
	float shoot_timer;
	bool active;
}

const float WORLD_PLAY_SIZE = 24.0f;
const float WORLD_WRAP_MARGIN = 12.0f;
const float WORLD_SIZE = WORLD_PLAY_SIZE + WORLD_WRAP_MARGIN;

const float SHIP_THRUST_ACC  = 0.006f;
const float SHIP_ROT_SPEED   = 0.06f;
const float SHIP_CAM_EASE    = 0.05f;
const float SHIP_BASE_SCALE  = 45.0f;
const int   SHIP_LIVES_START = 3;
const float SHIP_BULLET_SPEED = 0.3f;
const float SHIP_BULLET_SPEED_CHEAT = 1.2f;

const int   SCORE_EXTRA_LIFE = 10000;

const usz MAX_PARTICLES = 512;
const usz MAX_BULLETS   = 128;
const usz MAX_ASTEROIDS = 128;

struct Game {
	Vec3 ship_pos;
	Vec3 ship_vel;
	float      ship_yaw;
	float      ship_bank;
	Quat ship_rot;
	Vec3 cam_pos;
	float cam_yaw;
	float cam_pitch;
	float cam_focal_dist;
	Quat cam_rot;
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
	bool is_started;
	bool is_focused;
	Saucer saucer;

	Particle[MAX_PARTICLES] particles;
	Bullet[MAX_BULLETS]     bullets;
	Asteroid[MAX_ASTEROIDS] asteroids;
	Debris[9]               ship_pieces;

	uint thump_timer;
	uint thump_interval;
	bool thump_high;
}

fn void Game.init(&self, bool full_reset) {
	if (full_reset) {
		self.score = 0;
		self.lives = SHIP_LIVES_START;
		self.wave = 0;
		self.next_extra_life_score = SCORE_EXTRA_LIFE;
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
	self.ship_yaw   = 0.0f;
	self.ship_bank  = 0.0f;
	self.ship_rot   = quaternion::IDENTITY;
	self.cam_pos    = { self.ship_pos.x, 20.0f, self.ship_pos.z };
	self.cam_yaw    = 0.0f;
	self.cam_pitch  = 1.57f;
	self.cam_focal_dist = 40.0f;
	self.cam_rot    = quaternion::from_euler(self.cam_pitch, self.cam_yaw, 0.0f);

	self.thrust_acc = SHIP_THRUST_ACC;
	self.rot_speed  = SHIP_ROT_SPEED;
	self.cam_ease   = SHIP_CAM_EASE;
	self.scale      = SHIP_BASE_SCALE;
	self.shoot_cooldown = 0;
	self.is_dead    = false;
	self.death_timer = 0.0f;
	self.is_won     = false;
	self.win_timer  = 0.0f;
	self.wave_notif_timer = 0.0f;

	self.reschedule_saucer();
	self.saucer.active = false;
	self.cheat_mode = false;
	self.is_focused = true;
}

fn void Game.load_best_score(&self) {
	$if (env::WASM):
		self.best_score = emscripten_run_script_int("load_score()");
		return;
	$else
		if (try f = io::file::open("score.txt", "r")) {
			defer (void)f.close();
			char[32] buf;
			if (usz len = f.read(buf[..])!!) {
				if (try score = String.to_int((String)buf[:len])) {
					self.best_score = score;
				}
			}
		}
	$endif
}

fn void Game.save_best_score(&self) {
	$if (env::WASM):
		char[64] buf;
		emscripten_run_script(string::bformat(buf[..], "save_score(%d)\0", self.best_score).ptr);
	$else
		if (try f = file::open("score.txt", "w")) {
			defer (void)f.close();
			char[32] buf;
			(void)f.write(string::bformat(buf[..], "%d", self.best_score));
		}
	$endif
}

fn void Game.trigger_death(&self, Vec3[5] world_v) {
	if (self.is_dead || self.is_won || self.cheat_mode) return;

	self.is_dead = true;
	self.lives--;
	self.death_timer = 0.0f;
	audio::audio_play_explosion(1.5f);

	foreach (i, edge : SHIP_LINES) {
		Debris* d = &self.ship_pieces[i];
		d.p1 = world_v[edge[0]];
		d.p2 = world_v[edge[1]];
		d.active = true;

		Vec3 mid = (d.p1 + d.p2) * 0.5f;
		Vec3 out = (mid - self.ship_pos).normalize() * 0.05f;
		d.v1 = self.ship_vel + out;
		d.v2 = self.ship_vel + out * 1.5f;
	}

	for (int i = 0; i < 60; i++) {
		foreach (&p : self.particles) {
			if (p.life <= 0.0f) {
				p.pos = self.ship_pos;
				ulong h2 = rand_hash(i, self.frame);
				p.vel = {((float)(h2 & 0xFFu) / 128.0f - 1.0f) * 0.3f, 0,
						 ((float)((h2 >> 8) & 0xFFu) / 128.0f - 1.0f) * 0.3f};
				p.life = 1.0f + (float)(h2 % 50u) * 0.01f;
				break;
			}
		}
	}
}

fn void Game.reschedule_saucer(&self) {
	float factor = math::min(1f, (float)self.score / 60000f);
	uint base_wait = (uint)(600f * (1f - factor * 0.75f));
	uint rand_range = (uint)(600f * (1f - factor * 0.75f));
	if (base_wait < 120u) base_wait = 120u;
	if (rand_range < 120u) rand_range = 120u;

	self.next_saucer_frame = self.frame + base_wait + (uint)rand_hash(self.frame) % rand_range;
}

fn void Game.trigger_saucer_death(&self, bool award_points) {
	if (!self.saucer.active) return;

	if (award_points) {
		self.score += self.saucer.type.score;
		if (self.score >= self.next_extra_life_score) {
			self.lives++;
			self.next_extra_life_score += SCORE_EXTRA_LIFE;
		}
	}

	self.saucer.active = false;
	self.reschedule_saucer();

	for (int i = 0; i < 30; i++) {
		foreach (&p : self.particles) {
			if (p.life <= 0.0f) {
				p.pos = self.saucer.pos;
				ulong h = rand_hash(i, self.frame);
				p.vel = {((float)(h & 0xFFu) / 128.0f - 1.0f) * 0.25f, 0,
						 ((float)((h >> 8) & 0xFFu) / 128.0f - 1.0f) * 0.25f};
				p.life = 0.8f;
				break;
			}
		}
	}
}

fn void Game.destroy_asteroid(&self, Asteroid* a, Vec3 impact_vel, bool award_points) {
	if (!a.active) return;

	audio::audio_play_explosion(a.radius * 2.5f);
	a.active = false;

	if (award_points) {
		self.score += a.size.score;

		if (self.score >= self.next_extra_life_score) {
			self.lives++;
			self.next_extra_life_score += 10000;
		}
	}

	if (a.size != AsteroidSize.SMALL) {
		int count = 0;
		Vec3 dir = impact_vel.length_sq() > 0.0001f ? impact_vel.normalize() : (Vec3){1,0,0};
		Vec3 perp = {-dir.z, 0, dir.x};

		Vec3 parent_pos = a.pos;
		Vec3 parent_vel = a.vel;
		AsteroidSize child_size = (AsteroidSize)((int)a.size - 1);

		for (usz i = 0; i < MAX_ASTEROIDS && count < 2; i++) {
			Asteroid* na = &self.asteroids[i];
			if (!na.active) {
				float side = (count == 0) ? 1.0f : -1.0f;
				Vec3 n_vel = parent_vel * 1.2f + perp * (side * 0.05f);
				na.spawn(parent_pos, n_vel, child_size, (uint)rand_hash(i, self.frame));
				count++;
			}
		}
	}

	for (int i = 0; i < 10; i++) {
		foreach (&p : self.particles) {
			if (p.life <= 0.0f) {
				p.pos = a.pos;
				ulong h = rand_hash(i, self.frame);
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
	ulong seed = (ulong)(long)clock::now() ^ (ulong)self.frame;
	int count = 6 + self.wave * 2;
	if (count > 25) count = 25;

	for (usz i = 0; i < (usz)count; i++) {
		Asteroid* a = &self.asteroids[i];
		ulong h = rand_hash(i, seed);

		float angle = ((float)(h % 360u)).to_radians();
		float dist = 6.0f + (float)((h >> 8) % 100u) * 0.1f;
		Vec3 pos = {};
		pos.xz = (Vec2){math::cos(angle), math::sin(angle)} * dist;

		Vec3 vel = {};
		Vec2 rand_vec = {(float)((h >> 20) & 0xFFu), (float)((h >> 24) & 0xFFu)};
		vel.xz = (rand_vec / 255.0f - 0.5f) * (0.03f + self.wave * 0.005f);
		vel.y = 0.0f;
		a.spawn(pos, vel, AsteroidSize.LARGE, (uint)h);
	}
}

fn void Asteroid.spawn(&self, Vec3 pos, Vec3 vel, AsteroidSize size, uint seed) {
	self.active = true;
	self.pos = pos;
	self.vel = vel;
	self.size = size;

	self.radius = size.radius;
	self.rot = 0;
	self.rot_vel = ((float)(seed % 100u) / 100.0f - 0.5f) * 0.1f;

	for (int j = 0; j < 6; j++) {
		float va = (float)j * math::PI * 2.0f / 6.0f;
		ulong vh = rand_hash(j, seed);

		float vr = self.radius * (0.8f + (float)(vh % 40u) * 0.01f);

		self.verts[j] = { math::cos(va) * vr, -self.radius * 0.6f, math::sin(va) * vr };

		ulong vh2 = rand_hash(j, seed ^ 0x12345678UL);
		float vr2 = self.radius * (0.8f + (float)(vh2 % 40u) * 0.01f);
		self.verts[j+6] = { math::cos(va) * vr2, self.radius * 0.6f, math::sin(va) * vr2 };
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
		case rgfw::Key.K_1:   input.cam_yaw_l = pressed;
		case rgfw::Key.K_2:   input.cam_yaw_r = pressed;
		case rgfw::Key.K_3:   input.cam_pitch_u = pressed;
		case rgfw::Key.K_4:   input.cam_pitch_d = pressed;
		default:
	}
}

macro ulong rand_hash(x, seed = 0) {
	return wyhash2::hash(((char*)&x)[:@sizeof(x)], (ulong)seed);
}

fn bool draw_pixel(Color* buf, UszVec2 size, IVec2 pos, Color c, bool check_collision) {
	if (pos.x >= 0 && pos.y >= 0 && pos.x < (int)size.x && pos.y < (int)size.y) {
		usz idx = (usz)pos.y * size.x + (usz)pos.x;
		if (check_collision) {
			if (buf[idx].xyz == ASTEROID_COLOR.xyz) return true;
			if (buf[idx].xyz == ENEMY_COLOR.xyz) return true;
		}
		buf[idx] = c;
	}
	return false;
}

fn void draw_pixel_add(Color* buf, UszVec2 size, IVec2 pos, Color c) {
	if (pos.x >= 0 && pos.y >= 0 && pos.x < (int)size.x && pos.y < (int)size.y) {
		usz idx = (usz)pos.y * size.x + (usz)pos.x;
		uint r = ((uint)buf[idx].x & 0xFFu) + ((uint)c.x & 0xFFu);
		uint g = ((uint)buf[idx].y & 0xFFu) + ((uint)c.y & 0xFFu);
		uint b = ((uint)buf[idx].z & 0xFFu) + ((uint)c.z & 0xFFu);
		buf[idx].x = (char)(r > 255 ? 255 : r);
		buf[idx].y = (char)(g > 255 ? 255 : g);
		buf[idx].z = (char)(b > 255 ? 255 : b);
	}
}

fn void draw_line_add(Color* buf, UszVec2 size, IVec2 p0, IVec2 p1, Color color) {
	if (p0.x == PROJECT_ERROR || p1.x == PROJECT_ERROR) return;
	IVec2 d = math::abs(p1 - p0);
	IVec2 s = { p0.x < p1.x ? 1 : -1, p0.y < p1.y ? 1 : -1 };
	int err = d.x - d.y;
	while (true) {
		draw_pixel_add(buf, size, p0, color);
		if (p0 == p1) break;
		int e2 = 2 * err;
		if (e2 > -d.y) { err -= d.y; p0.x += s.x; }
		if (e2 <  d.x) { err += d.x; p0.y += s.y; }
	}
}

fn bool draw_line_hit_test(Color* buf, UszVec2 size, IVec2 p0, IVec2 p1) {
	if (p0.x == PROJECT_ERROR || p1.x == PROJECT_ERROR) return false;
	IVec2 d = math::abs(p1 - p0);
	IVec2 s = { p0.x < p1.x ? 1 : -1, p0.y < p1.y ? 1 : -1 };
	int err = d.x - d.y;
	while (true) {
		if (p0.x >= 0 && p0.y >= 0 && p0.x < (int)size.x && p0.y < (int)size.y) {
			usz idx = (usz)p0.y * size.x + (usz)p0.x;

			if (buf[idx].xyz == ASTEROID_COLOR.xyz) return true;
			if (buf[idx].xyz == ENEMY_COLOR.xyz) return true;
		}
		if (p0 == p1) break;
		int e2 = 2 * err;
		if (e2 > -d.y) { err -= d.y; p0.x += s.x; }
		if (e2 <  d.x) { err += d.x; p0.y += s.y; }
	}
	return false;
}

fn void draw_line_thick(Color* buf, UszVec2 size, IVec2 p0, IVec2 p1, Color color, bool check_collision) {
	if (p0.x == PROJECT_ERROR || p1.x == PROJECT_ERROR) return;
	draw_line(buf, size, p0, p1, color, check_collision);
	if (NEON_LINE_THICKNESS > 0) {
		for (int i = 1; i <= NEON_LINE_THICKNESS; i++) {
			draw_line(buf, size, p0 + {i, 0}, p1 + {i, 0}, color, check_collision);
			draw_line(buf, size, p0 + {-i, 0}, p1 + {-i, 0}, color, check_collision);
			draw_line(buf, size, p0 + {0, i}, p1 + {0, i}, color, check_collision);
			draw_line(buf, size, p0 + {0, -i}, p1 + {0, -i}, color, check_collision);
		}
	}
}

fn bool draw_line_glow(Color* buf, UszVec2 size, IVec2 p0, IVec2 p1, Color color, bool check_collision) {
	if (p0.x == PROJECT_ERROR || p1.x == PROJECT_ERROR) return false;

	bool hit = false;
	if (check_collision) {
		hit = draw_line_hit_test(buf, size, p0, p1);
	}

	uint cr = (uint)color.x & 0xFFu;
	uint cg = (uint)color.y & 0xFFu;
	uint cb = (uint)color.z & 0xFFu;

	Color g1 = { (char)((float)cr * NEON_GLOW_INTENSITY_1),
				 (char)((float)cg * NEON_GLOW_INTENSITY_1),
				 (char)((float)cb * NEON_GLOW_INTENSITY_1), 255 };
	Color g2 = { (char)((float)cr * NEON_GLOW_INTENSITY_2),
				 (char)((float)cg * NEON_GLOW_INTENSITY_2),
				 (char)((float)cb * NEON_GLOW_INTENSITY_2), 255 };

	draw_line_add(buf, size, p0 + {2, 0}, p1 + {2, 0}, g2);
	draw_line_add(buf, size, p0 + {-2, 0}, p1 + {-2, 0}, g2);
	draw_line_add(buf, size, p0 + {0, 2}, p1 + {0, 2}, g2);
	draw_line_add(buf, size, p0 + {0, -2}, p1 + {0, -2}, g2);

	draw_line_add(buf, size, p0 + {1, 0}, p1 + {1, 0}, g1);
	draw_line_add(buf, size, p0 + {-1, 0}, p1 + {-1, 0}, g1);
	draw_line_add(buf, size, p0 + {0, 1}, p1 + {0, 1}, g1);
	draw_line_add(buf, size, p0 + {0, -1}, p1 + {0, -1}, g1);
	draw_line_add(buf, size, p0 + {1, 1}, p1 + {1, 1}, g1);
	draw_line_add(buf, size, p0 + {-1, -1}, p1 + {-1, -1}, g1);
	draw_line_add(buf, size, p0 + {1, -1}, p1 + {1, -1}, g1);
	draw_line_add(buf, size, p0 + {-1, 1}, p1 + {-1, 1}, g1);

	draw_line_thick(buf, size, p0, p1, color, false);
	return hit;
}

fn bool draw_line(Color* buf, UszVec2 size, IVec2 p0, IVec2 p1, Color color, bool check_collision) {
	if (p0.x == PROJECT_ERROR || p1.x == PROJECT_ERROR) return false;
	IVec2 d = math::abs(p1 - p0);
	IVec2 s = { p0.x < p1.x ? 1 : -1, p0.y < p1.y ? 1 : -1 };
	int err = d.x - d.y;
	bool hit = false;
	while (true) {
		if (draw_pixel(buf, size, p0, color, check_collision)) hit = true;
		if (p0 == p1) break;
		int e2 = 2 * err;
		if (e2 > -d.y) { err -= d.y; p0.x += s.x; }
		if (e2 <  d.x) { err += d.x; p0.y += s.y; }
	}
	return hit;
}

fn void draw_star(Color* buf, UszVec2 size, IVec2 pos, int arm, Color color, bool check_collision) {
	if (pos.x == PROJECT_ERROR) return;
	draw_pixel_add(buf, size, pos, color);
	for (int i = -arm; i <= arm; i++) {
		if (i == 0) continue;
		draw_pixel_add(buf, size, pos + {i, 0}, color);
		draw_pixel_add(buf, size, pos + {0, i}, color);
	}
}

fn bool draw_lines(Color* buf, UszVec2 size, IVec2[] pts, int[2][] indices, Color c, bool collision) {
	bool hit = false;
	foreach (idx : indices) {
		if (draw_line_glow(buf, size, pts[idx[0]], pts[idx[1]], c, collision)) hit = true;
	}
	return hit;
}

fn Vec2 toroidal_offset(Vec2 val) {
	const float W = WORLD_SIZE * 2.0f;
	return val - math::round(val / W) * W;
}

fn Vec2 get_relative_pos(Vec2 pos, Vec3 cam) => toroidal_offset(pos - cam.xz);
fn IVec2 to_screen(Vec2 rel, float scale, UszVec2 size) => (IVec2)(rel * scale) + (IVec2)size / 2;
fn Vec3 get_cam_space_rel(Vec3 rel_to_ship, Game* g) => g.cam_rot.conjugate() * rel_to_ship;

fn IVec2 project_cam_space(Vec3 cam_space, Game* g, UszVec2 size) {
	float dist = g.cam_focal_dist;
	float z = cam_space.z + dist;
	if (z < 1.0f) return { PROJECT_ERROR, PROJECT_ERROR };
	float fov_scale = dist / z;
	return to_screen(cam_space.xy * fov_scale, g.scale, size);
}

fn IVec2 project(Vec3 pos, Game* g, UszVec2 size) {
	Vec3 rel_to_ship = pos - g.ship_pos;
	rel_to_ship.xz = toroidal_offset(rel_to_ship.xz);
	return project_cam_space(get_cam_space_rel(rel_to_ship, g), g, size);
}

fn float toroidal_dist_sq(Vec3 p1, Vec3 p2) {
	return get_relative_pos(p1.xz, p2).length_sq();
}


struct FontLine { float x1, y1, x2, y2; }
 
enum FontChar : int (char c, FontLine[] lines)
{
	ZERO  { '0', { {0,0,2,0}, {2,0,2,4}, {2,4,0,4}, {0,4,0,0} } },
	ONE   { '1', { {1,0,1,4} } },
	TWO   { '2', { {0,0,2,0}, {2,0,2,2}, {2,2,0,2}, {0,2,0,4}, {0,4,2,4} } },
	THREE { '3', { {0,0,2,0}, {2,0,2,4}, {2,4,0,4}, {0,2,2,2} } },
	FOUR  { '4', { {0,0,0,2}, {0,2,2,2}, {2,0,2,4} } },
	FIVE  { '5', { {2,0,0,0}, {0,0,0,2}, {0,2,2,2}, {2,2,2,4}, {2,4,0,4} } },
	SIX   { '6', { {2,0,0,0}, {0,0,0,4}, {0,4,2,4}, {2,4,2,2}, {2,2,0,2} } },
	SEVEN { '7', { {0,0,2,0}, {2,0,2,4} } },
	EIGHT { '8', { {0,0,2,0}, {0,0,0,4}, {0,4,2,4}, {2,4,2,0}, {0,2,2,2} } },
	NINE  { '9', { {2,2,0,2}, {0,2,0,0}, {0,0,2,0}, {2,0,2,4} } },
	A     { 'A', { {0,4,1,0}, {1,0,2,4}, {0.5,2,1.5,2} } },
	B     { 'B', { {0,0,0,4}, {0,0,2,0}, {2,0,2,2}, {0,2,2,2}, {2,2,2,4}, {0,4,2,4} } },
	C     { 'C', { {2,0,0,0}, {0,0,0,4}, {0,4,2,4} } },
	D     { 'D', { {0,0,0,4}, {0,0,1.5,0}, {1.5,0,2,0.5}, {2,0.5,2,3.5}, {2,3.5,1.5,4}, {1.5,4,0,4} } },
	E     { 'E', { {2,0,0,0}, {0,0,0,4}, {0,4,2,4}, {0,2,1.6,2} } },
	F     { 'F', { {0,0,0,4}, {0,0,2,0}, {0,2,1.5,2} } },
	G     { 'G', { {2,0,0,0}, {0,0,0,4}, {0,4,2,4}, {2,4,2,2}, {1,2,2,2} } },
	H     { 'H', { {0,0,0,4}, {2,0,2,4}, {0,2,2,2} } },
	I     { 'I', { {1,0,1,4}, {0,0,2,0}, {0,4,2,4} } },
	K     { 'K', { {0,0,0,4}, {2,0,0,2}, {0,2,2,4} } },
	L     { 'L', { {0,0,0,4}, {0,4,2,4} } },
	M     { 'M', { {0,4,0,0}, {0,0,1,1}, {1,1,2,0}, {2,0,2,4} } },
	N     { 'N', { {0,4,0,0}, {0,0,2,4}, {2,4,2,0} } },
	O     { 'O', { {0,0,2,0}, {2,0,2,4}, {2,4,0,4}, {0,4,0,0} } },
	P     { 'P', { {0,4,0,0}, {0,0,2,0}, {2,0,2,2}, {2,2,0,2} } },
	R     { 'R', { {0,4,0,0}, {0,0,2,0}, {2,0,2,2}, {2,2,0,2}, {1,2,2,4} } },
	S     { 'S', { {2,0,0,0}, {0,0,0,2}, {0,2,2,2}, {2,2,2,4}, {0,4,2,4} } },
	T     { 'T', { {0,0,2,0}, {1,0,1,4} } },
	U     { 'U', { {0,0,0,4}, {0,4,2,4}, {2,4,2,0} } },
	V     { 'V', { {0,0,1,4}, {1,4,2,0} } },
	W     { 'W', { {0,0,0,4}, {0,4,1,3}, {1,3,2,4}, {2,4,2,0} } },
	SPACE { ' ', { } }
}
 
fn void draw_text(Color* buf, UszVec2 size, IVec2 pos, int text_size, char* str, Color c) {
	int cur_x = pos.x;
	for (usz i = 0; str[i] != '\0'; i++) {
		FontChar glyph = FontChar::lookup_field(c, str[i]) ?? FontChar.SPACE;
		for (usz l = 0; l < glyph.lines.len; l++) {
			FontLine line = glyph.lines[l];
			IVec2 p1 = { cur_x + (int)(line.x1 * (float)text_size), pos.y + (int)(line.y1 * (float)text_size) };
			IVec2 p2 = { cur_x + (int)(line.x2 * (float)text_size), pos.y + (int)(line.y2 * (float)text_size) };
			draw_line_glow(buf, size, p1, p2, c, false);
		}
		cur_x += text_size * 4;
	}
}

fn void wrap(Vec3* pos) {
	pos.xz = toroidal_offset(pos.xz);
}

fn void update(Game* g) {
	bool should_update;
	$if env::WASM:
		should_update = !g.paused && g.is_started && g.is_focused;
	$else
		should_update = !g.paused && g.is_started;
	$endif

	if (!should_update) return;
	g.frame++;
	Vec3 ship_fwd = g.ship_rot * {0, 0, 1};

	static bool cheat_last = false;
	if (g.input.cheat && !cheat_last) {
		g.cheat_mode = !g.cheat_mode;
	}
	cheat_last = g.input.cheat;

	if (g.shoot_cooldown > 0) g.shoot_cooldown--;
	if (!g.is_dead && !g.game_over && !g.is_won && g.input.shoot && g.shoot_cooldown == 0) {
		foreach (&b : g.bullets) {
			if (b.life <= 0) {
				b.pos  = g.ship_pos + ship_fwd * 0.6f;
				if (g.cheat_mode) {
					b.vel  = ship_fwd * SHIP_BULLET_SPEED_CHEAT;
					b.life = 180;
					g.shoot_cooldown = 3;
				} else {
					b.vel  = ship_fwd * SHIP_BULLET_SPEED;
					b.life = 60;
					g.shoot_cooldown = 15;
				}
				b.from_ship = true;
				audio::audio_play_laser();
				break;
			}
		}
	}

	bool thrusting = !g.is_dead && !g.game_over && !g.is_won && g.input.forward;
	audio::audio_set_thrust(thrusting);
	float speed_mult = g.cheat_mode ? 4.0f : 1.0f;

	if (thrusting) {
		g.ship_vel += ship_fwd * (g.thrust_acc * speed_mult);

		Vec3 back_pos = g.ship_pos + (g.ship_rot * {0, 0, -0.6f});
		for (int i = 0; i < 2; i++) {
			foreach (&p : g.particles) {
				if (p.life <= 0.0f) {
					p.pos = back_pos;
					ulong rf = rand_hash(g.frame, i);
					Vec2 rand_vec = {(float)(rf & 0xFFu), (float)((rf >> 8) & 0xFFu)};
					p.vel.xz = (ship_fwd.xz * -0.1f) + (rand_vec / 255.0f - 0.5f) * 0.05f;
					p.life = 0.5f + ((float)((rf >> 16) & 0xFFu) / 255.0f) * 0.5f;
					break;
				}
			}
		}
	}

	float drag = g.input.back ? 0.94f : 0.985f;
	g.ship_vel *= drag;

	g.ship_pos += g.ship_vel;
	g.ship_pos.y = 0.0f;

	if (!g.is_dead && !g.game_over && !g.is_won) {
		float target_bank = 0.0f;
		if (g.input.left) {
			g.ship_yaw += g.rot_speed;
			target_bank = 0.5f;
		}
		if (g.input.right) {
			g.ship_yaw -= g.rot_speed;
			target_bank = -0.5f;
		}
		g.ship_bank += (target_bank - g.ship_bank) * 0.1f;
		g.ship_rot = quaternion::from_euler(0.0f, g.ship_yaw, g.ship_bank);
	}

	static bool hyperspace_last = false;
	if (g.input.hyperspace && !hyperspace_last && !g.is_dead && !g.is_won) {
		for (int i = 0; i < 30; i++) {
			foreach (&p : g.particles) {
				if (p.life <= 0.0f) {
					p.pos = g.ship_pos;
					ulong h = rand_hash(i, g.frame + (ulong)(long)clock::now());
					p.vel = {((float)(h & 0xFFu) / 128.0f - 1.0f) * 0.4f, 0,
							 ((float)((h >> 8) & 0xFFu) / 128.0f - 1.0f) * 0.4f};
					p.life = 0.5f;
					break;
				}
			}
		}

		ulong hx = rand_hash(g.frame, (ulong)(long)clock::now());

		if ((hx % 100u) < 10u) {
			Vec3[5] boom_v;
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
						ulong ha = rand_hash(i, g.frame);
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
			g.saucer.shoot_timer = g.saucer.type.cooldown;
			foreach (&b : g.bullets) {
				if (b.life <= 0) {
					b.pos = g.saucer.pos;
					Vec3 target_dir;
					if (g.saucer.type == SaucerType.SMALL) {
						target_dir = (g.ship_pos - g.saucer.pos).normalize();
						float inaccuracy = math::max(0.0f, 0.4f - (float)g.score / 100000.0f);
						ulong rh = rand_hash(g.frame);
						Vec2 rand_off = {(float)(rh & 0xFFu), (float)((rh >> 8) & 0xFFu)};
						target_dir.xz += (rand_off / 255.0f - 0.5f) * inaccuracy;
						target_dir = target_dir.normalize();
					} else {
						ulong rh = rand_hash(g.frame);
						float ra = ((float)(rh % 360u)).to_radians();
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
			float limit = a.radius + g.saucer.type.coll_rad;
			if (dist_sq < limit * limit) {
				g.destroy_asteroid(a, g.saucer.vel, false);
				g.trigger_saucer_death(false);
				break;
			}
		}
	}

	wrap(&g.ship_pos);

	foreach (&p : g.particles) if (p.life > 0.0f) { p.pos += p.vel; p.life -= 0.02f; }
	foreach (&b : g.bullets)   if (b.life > 0.0f) { b.pos += b.vel; b.pos.y = 0; wrap(&b.pos); b.life--; }
	foreach (&a : g.asteroids) {
		if (!a.active) continue;
		a.pos += a.vel;
		a.pos.y = 0;
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
		if (g.win_timer < 3.0f && g.frame % 12 == 0) {
			ulong h_pos = rand_hash(g.frame);
			Vec3 firework_pos = g.ship_pos;
			firework_pos.xz += (Vec2){(float)(h_pos & 0xFFu) / 25.5f - 5.0f, (float)((h_pos >> 8) & 0xFFu) / 25.5f - 5.0f};

			for (int i = 0; i < 30; i++) {
				foreach (&p : g.particles) {
					if (p.life <= 0.0f) {
						p.pos = firework_pos;
						ulong h = rand_hash(i, g.frame);
						p.vel.xz = (Vec2){(float)(h & 0xFFu) / 128.0f - 1.0f, (float)((h >> 8) & 0xFFu) / 128.0f - 1.0f} * 0.35f;
						p.life = 0.8f + (float)(h % 50u) * 0.01f;
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
			float coll_rad = a.radius * 1.5f;
			if (dist_sq < coll_rad * coll_rad) {
				b.life = 0;
				g.destroy_asteroid(a, b.vel, b.from_ship);
				break;
			}
		}
		if (g.saucer.active && b.from_ship) {
			float sd = toroidal_dist_sq(b.pos, g.saucer.pos);
			if (sd < 1.2f * 1.2f) {
				b.life = 0;
				g.trigger_saucer_death(true);
				break;
			}
		}
	}

	g.cam_pos = { g.ship_pos.x, 20.0f, g.ship_pos.z };

	if (g.input.cam_yaw_l)   g.cam_yaw   -= 0.05f;
	if (g.input.cam_yaw_r)   g.cam_yaw   += 0.05f;
	if (g.input.cam_pitch_u) g.cam_pitch -= 0.05f;
	if (g.input.cam_pitch_d) g.cam_pitch += 0.05f;

	g.cam_rot = quaternion::from_euler(g.cam_pitch, g.cam_yaw, 0.0f);

	float speed_mag = g.ship_vel.length();
	float target_scale = 45.0f - speed_mag * 60.0f;
	if (target_scale < 30.0f) target_scale = 30.0f;
	g.scale += (target_scale - g.scale) * 0.05f;

	float target_focal = 40.0f - speed_mag * 50.0f;
	if (target_focal < 20.0f) target_focal = 20.0f;
	g.cam_focal_dist += (target_focal - g.cam_focal_dist) * 0.05f;

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

fn void draw_grid(Game* g, Color* buf, UszVec2 size) {
	const float SPACING = 4.0f;
	const int GRID_DIM = (int)math::@ceil((WORLD_SIZE * 2.0f) / SPACING);

	int cell_x = (int)math::floor(g.cam_pos.x / SPACING);
	int cell_z = (int)math::floor(g.cam_pos.z / SPACING);

	for (int layer = -6; layer <= 6; layer++) {
		float y_off = (float)layer * 12.0f;
		int range = (layer == 0) ? 20 : 16;

		for (int gx = cell_x - range; gx <= cell_x + range; gx++) {
			for (int gz = cell_z - range; gz <= cell_z + range; gz++) {
				int[3] key = { (gx % GRID_DIM + GRID_DIM) % GRID_DIM,
							   (gz % GRID_DIM + GRID_DIM) % GRID_DIM,
							   layer };
				ulong hv = rand_hash(key);

				float ox = ((float)(hv & 0xFFu) / 255.0f - 0.5f) * SPACING * 1.5f;
				float oz = ((float)((hv >> 8) & 0xFFu) / 255.0f - 0.5f) * SPACING * 1.5f;
				Vec2 w_pos = { (float)gx * SPACING + ox, (float)gz * SPACING + oz };

				int arm = (layer == 0) ? 2 + (int)((hv >> 16) % 3u) : 1;

				char b  = (char)(90 + (hv >> 24) % 70u);

				float l_abs = math::abs((float)layer);
				float dim = 1.0f / (1.0f + l_abs * 0.25f);
				b = (char)((float)b * dim);

				char rb = (char)((ulong)b * 60u / 100u);
				Color c = {rb, rb, b, 255};

				draw_star(buf, size, project({w_pos.x, y_off, w_pos.y}, g, size), arm, c, false);
			}
		}
	}
}

fn void draw_ship(Game* g, Color* buf, UszVec2 size) {
	if (g.is_dead) {
		foreach (&d : g.ship_pieces) {
			if (!d.active) continue;
			IVec2 s1 = project(d.p1, g, size);
			IVec2 s2 = project(d.p2, g, size);
			draw_line_glow(buf, size, s1, s2, GREEN, false);
		}
		return;
	}

	Vec3 ship_cam_space = { 0, 0, 0 };

	Vec3[5] world_v;
	IVec2[5] s;
	foreach (i, v : SHIP_VERTS) {
		Vec3 lv = g.ship_rot * v;
		world_v[i] = lv + g.ship_pos;
		s[i] = project_cam_space(get_cam_space_rel(lv, g), g, size);
	}

	if (draw_lines(buf, size, s[..], SHIP_LINES, GREEN, true)) {
		g.trigger_death(world_v);
	}
}

fn void draw_particles(Game* g, Color* buf, UszVec2 size) {
	foreach (&p : g.particles) {
		if (p.life <= 0.0f) continue;
		IVec2 s = project(p.pos, g, size);

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
		draw_pixel_add(buf, size, s, c);
		if (p.life > 0.8f) draw_star(buf, size, s, 1, c, false);
	}
}

fn void draw_bullets(Game* g, Color* buf, UszVec2 size) {
	int arm = (int)(g.scale * 0.025f);
	if (arm < 1) arm = 1;

	foreach (&b : g.bullets) {
		if (b.life <= 0) continue;
		Vec3 r1 = b.pos - g.ship_pos;
		r1.xz = toroidal_offset(r1.xz);
		Vec3 r2 = r1 - b.vel * 1.25f;

		IVec2 s1 = project_cam_space(get_cam_space_rel(r1, g), g, size);
		IVec2 s2 = project_cam_space(get_cam_space_rel(r2, g), g, size);
		Color c = b.from_ship ? WHITE : ENEMY_COLOR;

		draw_line_glow(buf, size, s1, s2, c, false);
		draw_star(buf, size, s1, arm, c, false);
	}
}

fn void draw_asteroids(Game* g, Color* buf, UszVec2 size) {
	foreach (&a : g.asteroids) {
		if (!a.active) continue;

		Vec3 asteroid_rel_center = a.pos - g.ship_pos;
		asteroid_rel_center.xz = toroidal_offset(asteroid_rel_center.xz);

		IVec2[12] s;
		Quat rotation = quaternion::from_axis_angle({0, 1, 0}, a.rot);

		for (int i = 0; i < 12; i++) {
			Vec3 local_v = rotation * a.verts[i];
			s[i] = project_cam_space(get_cam_space_rel(asteroid_rel_center + local_v, g), g, size);
		}

		draw_lines(buf, size, s[..], ASTEROID_LINES, ASTEROID_COLOR, false);
	}
}

fn void draw_saucer(Game* g, Color* buf, UszVec2 size) {
	if (!g.saucer.active) return;
	Vec3 saucer_rel_center = g.saucer.pos - g.ship_pos;
	saucer_rel_center.xz = toroidal_offset(saucer_rel_center.xz);

	IVec2[8] s;
	foreach (i, v : SAUCER_VERTS) {
		s[i] = project_cam_space(get_cam_space_rel(saucer_rel_center + (v * g.saucer.type.draw_rad), g), g, size);
	}

	draw_lines(buf, size, s[..], SAUCER_LINES, ENEMY_COLOR, false);
}

fn void draw_hud(Game* g, Color* buf, UszVec2 size) {
	draw_text(buf, size, {50, 20}, 4, "SCORE", WHITE);
	char[32] score_str;
	draw_text(buf, size, {50, 50}, 8, string::bformat(score_str[..], "%d", g.score), WHITE);

	draw_text(buf, size, {(int)size.x/2 - 50, 25}, 3, "BEST SCORE", WHITE);
	char[32] best_str;
	draw_text(buf, size, {(int)size.x/2 - 50, 50}, 5, string::bformat(best_str[..], "%d", g.best_score), WHITE);

	for (int i = 0; i < g.lives; i++) {
		int lx = 50 + i * 30;
		int ly = 120;
		draw_line_glow(buf, size, {lx, ly}, {lx+10, ly+20}, GREEN, false);
		draw_line_glow(buf, size, {lx, ly}, {lx-10, ly+20}, GREEN, false);
		draw_line_glow(buf, size, {lx+10, ly+20}, {lx-10, ly+20}, GREEN, false);
	}

	if (g.game_over) {
		draw_text(buf, size, {(int)size.x/2 - 180, (int)size.y/2 - 50}, 15, "GAME OVER", WHITE);
	} else if (g.paused) {
		draw_text(buf, size, {(int)size.x/2 - 120, (int)size.y/2 - 50}, 15, "PAUSED", WHITE);
	}

	if (g.wave_notif_timer > 0.0f) {
		char[32] wave_str;
		draw_text(buf, size, {(int)size.x/2 - 100, (int)size.y/2 - 100}, 10, string::bformat(wave_str[..], "WAVE %d", g.wave), WHITE);
	} else if (g.is_won && g.win_timer > 1.0f) {
		char[32] wave_str;
		draw_text(buf, size, {(int)size.x/2 - 100, (int)size.y/2 - 100}, 10, string::bformat(wave_str[..], "WAVE %d", g.wave + 1), WHITE);
	}

	if (g.cheat_mode) {
		draw_text(buf, size, {(int)size.x - 180, 20}, 5, "CHEAT", ENEMY_COLOR);
	}
}

struct WebContext {
	Game g;
	rgfw::Window* win;
	rgfw::Surface* surface;
	Color* buffer;
	UszVec2 size;
	double accumulator;
	long last_time;
	rgfw::Event event;
}

WebContext web_ctx;


fn void Game.run_frame(&self, double dt, double* accumulator, Color* buffer, UszVec2 size, rgfw::Window* win, rgfw::Surface* surface) {
	const double DT = 1.0 / 60.0;

	bool should_run;
	$if env::WASM:
		should_run = self.is_started && self.is_focused && !self.paused;
	$else
		should_run = self.is_started && !self.paused;
	$endif

	if (should_run) {
		*accumulator += dt;
		while (*accumulator >= DT) {
			update(self);
			*accumulator -= DT;
		}
	} else {
		*accumulator = 0.0;
	}

	if (self.score > self.best_score) {
		self.best_score = self.score;
		$if (env::WASM):
			self.save_best_score();
		$endif
	}

	buffer[:size.x * size.y] = BLACK;

	draw_grid(self, buffer, size);
	draw_particles(self, buffer, size);
	draw_bullets(self, buffer, size);
	draw_asteroids(self, buffer, size);
	draw_saucer(self, buffer, size);
	draw_ship(self, buffer, size);
	draw_hud(self, buffer, size);

	$if env::WASM:
		if (!self.is_started) {
			draw_text(buffer, size, {(int)size.x/2 - 150, (int)size.y/2}, 10, "CLICK TO START", WHITE);
		} else if (!self.is_focused) {
			draw_text(buffer, size, {(int)size.x/2 - 150, (int)size.y/2}, 10, "CLICK TO FOCUS", WHITE);
		}
	$endif

	if (self.is_dead || self.game_over) {
		float tint = self.game_over ? 1.0f : self.death_timer;
		if (tint > 1.0f) tint = 1.0f;
		char r_add = (char)(tint * 80.0f);
		foreach (&c : buffer[:size.x * size.y]) {
			int r = (int)c.x + (int)r_add;
			if (r > 255) r = 255;
			c.x = (char)r;
		}
	}

	if (self.is_won) {
		float val_f = 0.0f;
		if (self.win_timer < 1.0f) {
			val_f = (self.win_timer / 1.0f) * 120.0f;
		} else {
			val_f = (1.0f - (self.win_timer - 1.0f) / 3.0f) * 120.0f;
		}
		if (val_f < 0) val_f = 0;
		char val = (char)val_f;
		foreach (&c : buffer[:size.x * size.y]) {
			uint r = (uint)c.x + (uint)val; if (r > 255) r = 255; c.x = (char)r;
			uint gr = (uint)c.y + (uint)val; if (gr > 255) gr = 255; c.y = (char)gr;
			uint bl = (uint)c.z + (uint)val; if (bl > 255) bl = 255; c.z = (char)bl;
		}
	}

	rgfw::window_blit_surface(win, surface);
}

fn void web_frame(void* arg) @export("web_frame") {
	WebContext* ctx = (WebContext*)arg;

	int rw, rh;
	rgfw::window_get_size(ctx.win, &rw, &rh);
	if (rw > 0 && rh > 0 && ((usz)rw != ctx.size.x || (usz)rh != ctx.size.y)) {
		ctx.size.x = (usz)rw;
		ctx.size.y = (usz)rh;
		ctx.g.scale = (float)ctx.size.y / 4.0f;
		mem::free(ctx.buffer);
		ctx.buffer = (Color*)mem::malloc(ctx.size.x * ctx.size.y * Color::size);
		rgfw::surface_free(ctx.surface);
		ctx.surface = rgfw::window_create_surface(ctx.win, (char*)ctx.buffer, ...ctx.size, rgfw::Format.RGBA8);
	}

	long current_time = (long)clock::now();
	double dt = (double)(current_time - ctx.last_time) / 1_000_000_000.0;
	if (dt > 0.5) dt = 0.5;
	ctx.last_time = current_time;

	while (rgfw::window_check_event(ctx.win, &ctx.event)) {
		switch (ctx.event.type) {
			case rgfw::EventType.QUIT: return;
			case rgfw::EventType.FOCUS_IN: ctx.g.is_focused = true;
			case rgfw::EventType.FOCUS_OUT: ctx.g.is_focused = false;
			case rgfw::EventType.MOUSE_BUTTON_PRESSED:
				if (!ctx.g.is_started) ctx.g.is_started = true;
				ctx.g.is_focused = true;
			case rgfw::EventType.KEY_PRESSED:
				if (!ctx.g.is_started) ctx.g.is_started = true;
				ctx.g.is_focused = true;
				if (ctx.event.key.value == rgfw::Key.P) ctx.g.paused = !ctx.g.paused;
				apply_key(&ctx.g.input, ctx.event.key.value, true);
			case rgfw::EventType.KEY_RELEASED:
				apply_key(&ctx.g.input, ctx.event.key.value, false);
			default:
		}
	}

	ctx.g.run_frame(dt, &ctx.accumulator, ctx.buffer, ctx.size, ctx.win, ctx.surface);
}


fn int main(int argc, char** args) {
	$if (env::WASM):
		wasm_initialize();
	$endif;
	if (audio::audio_init() != 0) {
		io::printn("Failed to initialize audio!");
	}
	$if (!env::WASM):
		defer audio::audio_terminate();
	$endif

	WindowFlags flags = (
		HIDE_MOUSE |
		FOCUS |
		NO_BORDER);

	$if (!env::WASM):
		$if env::LINUX:
			if (env::tget_var("WAYLAND_DISPLAY")!!) {
				flags |= FULLSCREEN;
			} else {
				flags |= MAXIMIZE;
			}
		$else
			flags |= FULLSCREEN;
		$endif
	$endif

	UszVec2 screen_size = { 1920, 1080 };

	rgfw::Window* win = rgfw::create_window("Software Asteroids", 0, 0, ...screen_size, flags);
	if (!win) { io::printn("Failed to create window!"); return 1; }

	int rw, rh;
	rgfw::window_get_size(win, &rw, &rh);
	if (rw > 0 && rh > 0) {
		screen_size.x = (usz)rw;
		screen_size.y = (usz)rh;
	}

	Color* buffer = mem::malloc(screen_size.x * screen_size.y * Color::size);
	if (!buffer) { io::printn("Failed to allocate buffer"); return 1; }
	$if (!env::WASM):
		defer mem::free(buffer);
	$endif

	rgfw::Surface* surface;
	$if (env::LINUX):
		if (rgfw::using_wayland()) {
			surface = rgfw::create_surface((char*)buffer, ...(IVec2)screen_size, rgfw::Format.RGBA8);
		} else {
			surface = rgfw::window_create_surface(win, (char*)buffer, ...screen_size, rgfw::Format.RGBA8);
		}
	$else
		surface = rgfw::window_create_surface(win, (char*)buffer, ...screen_size, rgfw::Format.RGBA8);
	$endif
	if (!surface) { io::printn("Failed to create surface!"); return 1; }
	$if (!env::WASM):
		defer rgfw::surface_free(surface);
	$endif

	$if (env::WASM):
		web_ctx.g.is_started = false;
		web_ctx.g.load_best_score();
		web_ctx.g.init(true);
		web_ctx.g.scale = (float)screen_size.y / 4.0f;
		web_ctx.win = win;
		web_ctx.surface = surface;
		web_ctx.buffer = buffer;
		web_ctx.size = screen_size;
		web_ctx.last_time = (long)clock::now();
		web_ctx.accumulator = 0.0;
	$else

		Game g;
		g.is_started = true;
		g.load_best_score();
		g.init(true);
		g.scale = (float)screen_size.y / 4.0f;

		rgfw::Event event;

		const double DT = 1.0 / 60.0;
		const long DT_NS = (long)(DT * 1_000_000_000.0);
		double accumulator = 0.0;
		long last_time = (long)clock::now();

		while MAINLOOP: (!rgfw::window_should_close(win)) {
			long current_time = (long)clock::now();
			double dt = (double)(current_time - last_time) / 1_000_000_000.0;
			if (dt > 0.25) dt = 0.25;
			last_time = current_time;

			while (rgfw::window_check_event(win, &event)) {
				switch (event.type) {
					case rgfw::EventType.QUIT: break MAINLOOP;
					case rgfw::EventType.FOCUS_IN: g.is_focused = true;
					case rgfw::EventType.FOCUS_OUT: g.is_focused = false;
					case rgfw::EventType.MOUSE_BUTTON_PRESSED:
						if (!g.is_started) g.is_started = true;
						g.is_focused = true;
					case rgfw::EventType.KEY_PRESSED:
						if (!g.is_started) g.is_started = true;
						g.is_focused = true;
						if (event.key.value == rgfw::Key.ESCAPE) break MAINLOOP;
						if (event.key.value == rgfw::Key.P) g.paused = !g.paused;
						apply_key(&g.input, event.key.value, true);
					case rgfw::EventType.KEY_RELEASED:
						apply_key(&g.input, event.key.value, false);
					default:
				}
			}

			g.run_frame(dt, &accumulator, buffer, screen_size, win, surface);

			$if (!env::WASM):
				long now = (long)clock::now();
				long work_done = now - last_time;
				long target = g.paused ? (long)100_000_000 : DT_NS;
				if (work_done < target) {
					thread::sleep_ns((NanoDuration)(target - work_done));
				}
			$endif
		}

		g.save_best_score();
	$endif;

	return 0;
}


////////////////////////////////////////////////////////////////////////////////
extern fn void emscripten_run_script(char* s);
extern fn int emscripten_run_script_int(char* s);

fn void wasm_start_game() @export("wasm_start_game") {
	web_ctx.g.is_started = true;
}

fn void web_tick() @export("web_tick") @if(env::WASM) => web_frame(&web_ctx);

// The linker synthesizes this to call constructors.
extern fn void __wasm_call_ctors() @if(env::WASM);
fn void wasm_initialize() @cname("_initialize") @wasm @if(env::WASM) => __wasm_call_ctors();


////////////////////////////////////////////////////////////////////////////////
module std::time::os @if(env::WASM && !env::WASI);

extern fn double emscripten_get_now() @callconv("cdecl");
fn Time native_timestamp() => (Time)(emscripten_get_now() * 1_000.0);
fn Clock native_clock()    => (Clock)(emscripten_get_now() * 1_000_000.0);

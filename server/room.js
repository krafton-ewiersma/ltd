// Room: one game instance (the old single-game server, now a class).
// The server (server.js) owns many of these. A room simulates movement for
// humans and bots, runs the yellow-cube lifecycle, and detects pickups.

const { BotController } = require("./bots");

const RESERVED_NAMES = [
  "Litha", "Lughnasa", "Mabon", "Samhain",
  "Yule", "Imbolc", "Ostara", "Beltane",
];
const COLORS = ["red", "blue", "white", "black", "green", "orange", "purple", "cyan"];
const MAX_MEMBERS = 8;
const BOUND = 18; // playable area is [-BOUND, BOUND] on x/z
const SPEED = 8; // units per second
const PICKUP_RADIUS = 1.0;
const CUBE_LIFETIME_MS = 5000;

let nextRoomId = 1;
let nextEntityId = 1;

function clampBound(v) {
  return Math.max(-BOUND, Math.min(BOUND, v));
}

function randPos() {
  return {
    x: (Math.random() * 2 - 1) * BOUND,
    z: (Math.random() * 2 - 1) * BOUND,
  };
}

function isReservedName(name) {
  const lower = String(name).trim().toLowerCase();
  return RESERVED_NAMES.some((n) => n.toLowerCase() === lower);
}

class Room {
  constructor({ name, password = "", maxScore = 20, botCount = 0, auto = false }) {
    this.id = nextRoomId++;
    this.name = name;
    this.password = password;
    this.maxScore = maxScore;
    this.botCount = botCount;
    this.auto = auto; // seeded by the server: recreated with same bots on game over
    this.cube = null;
    this.entities = new Map(); // id -> {id,name,bot,ws,color,x,z,tx,tz,score}
    this.bots = new BotController(botCount, BOUND);
    for (const bot of this.bots.list) {
      bot.entity = this._addEntity(bot.name, true, null);
    }
  }

  get members() {
    return [...this.entities.values()];
  }

  get memberCount() {
    return this.entities.size;
  }

  get humans() {
    return this.members.filter((e) => !e.bot);
  }

  _freeColor() {
    const used = new Set(this.members.map((e) => e.color));
    return COLORS.find((c) => !used.has(c)) || "red";
  }

  _addEntity(name, isBot, ws) {
    const p = randPos();
    const e = {
      id: nextEntityId++,
      name,
      bot: isBot,
      ws,
      color: this._freeColor(),
      x: p.x,
      z: p.z,
      tx: p.x,
      tz: p.z,
      score: 0,
    };
    this.entities.set(e.id, e);
    return e;
  }

  addPlayer(ws, name) {
    if (this.memberCount >= MAX_MEMBERS) return null;
    return this._addEntity(name, false, ws);
  }

  removeEntity(id) {
    this.entities.delete(id);
    // Fresh game for the next visitor once the last human is gone.
    if (this.humans.length === 0) {
      this.cube = null;
      for (const e of this.entities.values()) e.score = 0;
    }
  }

  broadcast(obj) {
    const data = JSON.stringify(obj);
    for (const e of this.entities.values()) {
      if (!e.bot && e.ws && e.ws.readyState === e.ws.OPEN) e.ws.send(data);
    }
  }

  spawnCube(now) {
    const p = randPos();
    this.cube = { x: p.x, z: p.z, dieAt: now + CUBE_LIFETIME_MS };
    this.bots.onCubeSpawn(now);
  }

  // Advances the simulation one tick. Returns the winning entity when the
  // room's max score is reached, otherwise null.
  tick(now, dtMs) {
    const dt = dtMs / 1000;
    for (const e of this.entities.values()) {
      const dx = e.tx - e.x;
      const dz = e.tz - e.z;
      const dist = Math.hypot(dx, dz);
      if (dist > 0.001) {
        const step = Math.min(dist, SPEED * dt);
        e.x += (dx / dist) * step;
        e.z += (dz / dist) * step;
      }
    }

    // The game only runs while a human is in the room; bots alone idle.
    if (this.humans.length === 0) {
      this.cube = null;
      return null;
    }

    if (!this.cube || now >= this.cube.dieAt) this.spawnCube(now);
    this.bots.tick(now, this.cube);

    for (const e of this.entities.values()) {
      if (Math.hypot(e.x - this.cube.x, e.z - this.cube.z) <= PICKUP_RADIUS) {
        e.score += 1;
        this.broadcast({ type: "pickup", id: e.id, name: e.name, score: e.score });
        if (e.score >= this.maxScore) return e;
        this.spawnCube(now);
        break;
      }
    }

    this.broadcast({
      type: "state",
      players: this.members.map((e) => ({
        id: e.id,
        name: e.name,
        color: e.color,
        bot: e.bot,
        x: Number(e.x.toFixed(3)),
        z: Number(e.z.toFixed(3)),
        score: e.score,
      })),
      cube: this.cube
        ? { x: Number(this.cube.x.toFixed(3)), z: Number(this.cube.z.toFixed(3)) }
        : null,
    });
    return null;
  }
}

module.exports = { Room, RESERVED_NAMES, isReservedName, clampBound, MAX_MEMBERS, BOUND };

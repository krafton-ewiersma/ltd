// LTD game server — authoritative simulation over WebSockets.
// Run with: npm install && npm start   (listens on ws://0.0.0.0:8765)

const { WebSocketServer } = require("ws");

const PORT = 8765;
const TICK_MS = 50; // 20 Hz simulation + broadcast
const BOUND = 18; // playable area is [-BOUND, BOUND] on x/z (plane is 40x40)
const PLAYER_SPEED = 8; // units per second
const PICKUP_RADIUS = 1.0; // player half-size (0.5) + cube half-size (0.25) + slack
const CUBE_LIFETIME_MS = 5000;
const COLORS = ["red", "blue", "white", "black"]; // join order: 1..4

const players = new Map(); // ws -> player
let cube = null; // { x, z, dieAt } — at most one yellow cube exists
let nextId = 1;

function clampBound(v) {
  return Math.max(-BOUND, Math.min(BOUND, v));
}

function randPos() {
  return {
    x: (Math.random() * 2 - 1) * BOUND,
    z: (Math.random() * 2 - 1) * BOUND,
  };
}

function spawnCube() {
  const p = randPos();
  cube = { x: p.x, z: p.z, dieAt: Date.now() + CUBE_LIFETIME_MS };
}

function freeColor() {
  const used = new Set([...players.values()].map((p) => p.color));
  return COLORS.find((c) => !used.has(c)) || null;
}

function broadcast(obj) {
  const data = JSON.stringify(obj);
  for (const ws of players.keys()) {
    if (ws.readyState === ws.OPEN) ws.send(data);
  }
}

const wss = new WebSocketServer({ port: PORT });
console.log(`LTD server listening on ws://0.0.0.0:${PORT}`);

wss.on("connection", (ws) => {
  ws.on("message", (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw);
    } catch {
      return;
    }
    const player = players.get(ws);

    if (!player && msg.type === "join") {
      const color = freeColor();
      if (!color) {
        ws.send(JSON.stringify({ type: "full" }));
        ws.close();
        return;
      }
      const name = String(msg.name || "").trim().slice(0, 16) || "Player";
      const spawn = randPos();
      const p = {
        id: nextId++,
        name,
        color,
        x: spawn.x,
        z: spawn.z,
        tx: spawn.x,
        tz: spawn.z,
        score: 0,
      };
      players.set(ws, p);
      ws.send(JSON.stringify({ type: "welcome", id: p.id, color }));
      console.log(`${p.name} joined as ${color} (${players.size}/4)`);
      return;
    }

    if (player && msg.type === "move") {
      const x = Number(msg.x);
      const z = Number(msg.z);
      if (Number.isFinite(x) && Number.isFinite(z)) {
        player.tx = clampBound(x);
        player.tz = clampBound(z);
      }
    }
  });

  ws.on("close", () => {
    const p = players.get(ws);
    if (p) {
      players.delete(ws);
      console.log(`${p.name} (${p.color}) left (${players.size}/4)`);
    }
  });

  ws.on("error", () => ws.close());
});

setInterval(() => {
  const now = Date.now();
  const dt = TICK_MS / 1000;

  for (const p of players.values()) {
    const dx = p.tx - p.x;
    const dz = p.tz - p.z;
    const dist = Math.hypot(dx, dz);
    if (dist > 0.001) {
      const step = Math.min(dist, PLAYER_SPEED * dt);
      p.x += (dx / dist) * step;
      p.z += (dz / dist) * step;
    }
  }

  if (players.size > 0) {
    if (!cube || now >= cube.dieAt) spawnCube();
    // First player within reach wins the cube — only one can ever collect it.
    for (const p of players.values()) {
      if (Math.hypot(p.x - cube.x, p.z - cube.z) <= PICKUP_RADIUS) {
        p.score += 1;
        console.log(`${p.name} scored (${p.score})`);
        broadcast({ type: "pickup", id: p.id, name: p.name, score: p.score });
        spawnCube();
        break;
      }
    }
  } else {
    cube = null;
  }

  if (players.size > 0) {
    broadcast({
      type: "state",
      players: [...players.values()].map((p) => ({
        id: p.id,
        name: p.name,
        color: p.color,
        x: Number(p.x.toFixed(3)),
        z: Number(p.z.toFixed(3)),
        score: p.score,
      })),
      cube: cube ? { x: Number(cube.x.toFixed(3)), z: Number(cube.z.toFixed(3)) } : null,
    });
  }
}, TICK_MS);

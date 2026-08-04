// LTD lobby server — hosts game rooms over WebSockets.
// Run with: npm install && npm start   (listens on ws://0.0.0.0:8765)
//
// Players connect, pick a unique name, then see the lobby: game rooms
// (pushed every second), connected players, and a chat room. They can join
// a room (optionally password-protected) or create their own. On launch the
// server seeds 4 bot rooms named from the reserved name list.

const { WebSocketServer } = require("ws");
const { Room, RESERVED_NAMES, isReservedName, clampBound, MAX_MEMBERS } = require("./room");

const PORT = 8765;
const TICK_MS = 50; // 20 Hz simulation
const LOBBY_MS = 1000; // lobby list refresh push
const INITIAL_BOT_COUNTS = [1, 3, 5, 7];
const DEFAULT_MAX_SCORE = 20;
const CHAT_HISTORY_LIMIT = 50;

const clients = new Map(); // ws -> {name, room, entity}
const rooms = new Map(); // id -> Room
const chatHistory = [];

function send(ws, obj) {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(obj));
}

function roomNameInUse(name) {
  const lower = name.toLowerCase();
  return [...rooms.values()].some((r) => r.name.toLowerCase() === lower);
}

function playerNameInUse(name) {
  const lower = name.toLowerCase();
  return [...clients.values()].some((c) => c.name && c.name.toLowerCase() === lower);
}

function randomReservedName() {
  const free = RESERVED_NAMES.filter((n) => !roomNameInUse(n));
  const pool = free.length > 0 ? free : RESERVED_NAMES;
  return pool[Math.floor(Math.random() * pool.length)];
}

function seedRooms() {
  const names = [...RESERVED_NAMES].sort(() => Math.random() - 0.5);
  INITIAL_BOT_COUNTS.forEach((botCount, i) => {
    const room = new Room({ name: names[i], maxScore: DEFAULT_MAX_SCORE, botCount, auto: true });
    rooms.set(room.id, room);
    console.log(`Seeded room "${room.name}" with ${botCount} bot(s)`);
  });
}

function lobbyPayload() {
  return {
    type: "lobby",
    rooms: [...rooms.values()].map((r) => ({
      id: r.id,
      name: r.name,
      players: r.memberCount,
      max_players: MAX_MEMBERS,
      has_password: r.password.length > 0,
      max_score: r.maxScore,
    })),
    players: [...clients.values()]
      .filter((c) => c.name)
      .map((c) => ({ name: c.name, room: c.room ? c.room.name : null })),
  };
}

function broadcastLobby() {
  const data = JSON.stringify(lobbyPayload());
  for (const [ws, c] of clients) {
    if (c.name && !c.room && ws.readyState === ws.OPEN) ws.send(data);
  }
}

function joinRoom(ws, c, room) {
  const entity = room.addPlayer(ws, c.name);
  if (!entity) {
    send(ws, { type: "join_error", reason: "Room is full." });
    return;
  }
  c.room = room;
  c.entity = entity;
  send(ws, {
    type: "join_ok",
    id: entity.id,
    color: entity.color,
    room: { id: room.id, name: room.name, max_score: room.maxScore },
  });
  console.log(`${c.name} joined room "${room.name}" (${room.memberCount}/${MAX_MEMBERS})`);
  broadcastLobby();
}

function leaveRoom(ws, c) {
  if (!c.room) return;
  const room = c.room;
  room.removeEntity(c.entity.id);
  c.room = null;
  c.entity = null;
  if (!room.auto && room.humans.length === 0) {
    rooms.delete(room.id);
    console.log(`Closed empty room "${room.name}"`);
  }
  send(ws, lobbyPayload());
  broadcastLobby();
}

const handlers = {
  login(ws, c, msg) {
    if (c.name) return;
    const name = String(msg.name || "").trim();
    if (!name || name.length > 16) {
      send(ws, { type: "login_error", reason: "Name must be 1-16 characters." });
      return;
    }
    if (isReservedName(name)) {
      send(ws, { type: "login_error", reason: "That name is reserved." });
      return;
    }
    if (playerNameInUse(name)) {
      send(ws, { type: "login_error", reason: "Name already taken." });
      return;
    }
    c.name = name;
    send(ws, { type: "login_ok", name });
    send(ws, { type: "chat_history", messages: chatHistory });
    send(ws, lobbyPayload());
    console.log(`${name} connected (${clients.size} online)`);
    broadcastLobby();
  },

  chat(ws, c, msg) {
    if (!c.name || c.room) return;
    const text = String(msg.text || "").trim().slice(0, 200);
    if (!text) return;
    const entry = { from: c.name, text };
    chatHistory.push(entry);
    if (chatHistory.length > CHAT_HISTORY_LIMIT) chatHistory.shift();
    const data = JSON.stringify({ type: "chat", ...entry });
    for (const [otherWs, other] of clients) {
      if (other.name && !other.room && otherWs.readyState === otherWs.OPEN) otherWs.send(data);
    }
  },

  create_room(ws, c, msg) {
    if (!c.name || c.room) return;
    const name = String(msg.name || "").trim();
    if (!name || name.length > 20) {
      send(ws, { type: "create_error", reason: "Room name must be 1-20 characters." });
      return;
    }
    if (isReservedName(name)) {
      send(ws, { type: "create_error", reason: "That room name is reserved." });
      return;
    }
    if (roomNameInUse(name)) {
      send(ws, { type: "create_error", reason: "A room with that name already exists." });
      return;
    }
    const password = String(msg.password || "").slice(0, 32);
    const rawScore = Number(msg.max_score);
    const maxScore = Number.isFinite(rawScore)
      ? Math.min(50, Math.max(10, Math.round(rawScore)))
      : DEFAULT_MAX_SCORE;
    const room = new Room({ name, password, maxScore });
    rooms.set(room.id, room);
    console.log(`${c.name} created room "${name}" (first to ${maxScore})`);
    joinRoom(ws, c, room);
  },

  join_room(ws, c, msg) {
    if (!c.name || c.room) return;
    const room = rooms.get(Number(msg.id));
    if (!room) {
      send(ws, { type: "join_error", reason: "Room no longer exists." });
      return;
    }
    if (room.password && String(msg.password || "") !== room.password) {
      send(ws, { type: "join_error", reason: "Wrong password." });
      return;
    }
    joinRoom(ws, c, room);
  },

  leave_room(ws, c) {
    leaveRoom(ws, c);
  },

  move(ws, c, msg) {
    if (!c.entity) return;
    const x = Number(msg.x);
    const z = Number(msg.z);
    if (Number.isFinite(x) && Number.isFinite(z)) {
      c.entity.tx = clampBound(x);
      c.entity.tz = clampBound(z);
    }
  },
};

const wss = new WebSocketServer({ port: PORT });
seedRooms();
console.log(`LTD lobby server listening on ws://0.0.0.0:${PORT}`);

wss.on("connection", (ws) => {
  clients.set(ws, { name: null, room: null, entity: null });

  ws.on("message", (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw);
    } catch {
      return;
    }
    const c = clients.get(ws);
    const handler = handlers[msg.type];
    if (c && handler) handler(ws, c, msg);
  });

  ws.on("close", () => {
    const c = clients.get(ws);
    if (c) {
      leaveRoom(ws, c);
      clients.delete(ws);
      if (c.name) {
        console.log(`${c.name} disconnected (${clients.size} online)`);
        broadcastLobby();
      }
    }
  });

  ws.on("error", () => ws.close());
});

setInterval(() => {
  const now = Date.now();
  for (const room of [...rooms.values()]) {
    const winner = room.tick(now, TICK_MS);
    if (!winner) continue;

    const scores = room.members
      .map((e) => ({ name: e.name, color: e.color, bot: e.bot, score: e.score }))
      .sort((a, b) => b.score - a.score);
    room.broadcast({
      type: "game_over",
      room: room.name,
      winner: { name: winner.name, color: winner.color, bot: winner.bot, score: winner.score },
      scores,
    });
    console.log(`Room "${room.name}": ${winner.name} won with ${winner.score}`);

    for (const human of room.humans) {
      const c = clients.get(human.ws);
      if (c) {
        c.room = null;
        c.entity = null;
      }
    }
    rooms.delete(room.id);

    if (room.auto) {
      const next = new Room({
        name: randomReservedName(),
        maxScore: DEFAULT_MAX_SCORE,
        botCount: room.botCount,
        auto: true,
      });
      rooms.set(next.id, next);
      console.log(`Recreated bot room as "${next.name}" (${next.botCount} bots)`);
    }
    broadcastLobby();
  }
}, TICK_MS);

setInterval(broadcastLobby, LOBBY_MS);

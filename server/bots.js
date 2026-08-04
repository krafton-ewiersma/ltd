// Bot controller: server-side AI players for a game room.
//
// Each bot rolls a random skill profile when the room is created:
//  - accuracy:   how close its first aim lands to the cube (1.0 = dead on)
//  - reactionMs: how long it waits before responding to a cube (re)spawn
//
// A bot that misses takes another look after a fresh reaction delay and
// halves its aim error each attempt, so sloppy bots still get there — late.

function clamp(v, bound) {
  return Math.max(-bound, Math.min(bound, v));
}

class BotController {
  constructor(names, bound) {
    this.bound = bound;
    this.list = [];
    for (const name of names) {
      this.list.push({
        name,
        accuracy: 0.35 + Math.random() * 0.65,
        reactionMs: 250 + Math.random() * 1750,
        aimAt: null, // timestamp of the next aim, null = nothing scheduled
        errScale: 1, // shrinks with every re-aim at the same cube
        entity: null, // room entity, assigned by the Room
      });
    }
  }

  onCubeSpawn(now) {
    for (const bot of this.list) {
      bot.aimAt = now + bot.reactionMs;
      bot.errScale = 1;
    }
  }

  tick(now, cube) {
    if (!cube) return;
    for (const bot of this.list) {
      const e = bot.entity;
      if (!e) continue;
      if (bot.aimAt !== null && now >= bot.aimAt) {
        bot.aimAt = null;
        const maxErr = (1 - bot.accuracy) * 6 * bot.errScale;
        const angle = Math.random() * Math.PI * 2;
        const dist = Math.random() * maxErr;
        e.tx = clamp(cube.x + Math.cos(angle) * dist, this.bound);
        e.tz = clamp(cube.z + Math.sin(angle) * dist, this.bound);
        bot.errScale *= 0.5;
      } else if (bot.aimAt === null) {
        // Arrived at its (possibly wrong) target while the cube is still
        // alive: schedule another, sharper look.
        const dx = e.tx - e.x;
        const dz = e.tz - e.z;
        if (dx * dx + dz * dz < 0.01) {
          bot.aimAt = now + bot.reactionMs * (0.4 + Math.random() * 0.6);
        }
      }
    }
  }
}

module.exports = { BotController };

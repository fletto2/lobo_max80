// Headless checks of the engine: node test_engine.js
// Reads the stages from $LODERUNNER_LEVELS, by default ../private/levels.txt.
'use strict';
const fs = require('fs');
const path = require('path');
const assert = require('assert');
const { Game, parseLevels, T, W, H } = require('./engine.js');

const levelsPath = process.env.LODERUNNER_LEVELS || path.join(__dirname, '..', 'private', 'levels.txt');
if (!fs.existsSync(levelsPath)) {
  console.log('test_engine.js: no ' + levelsPath + ", Lode Runner's stages, so no checks (set LODERUNNER_LEVELS)");
  process.exit(0);
}
const levels = parseLevels(fs.readFileSync(levelsPath, 'utf8'));
assert.strictEqual(levels.length, 150, 'level count');

let seed = 12345;
const rng = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x80000000);

function checkActor(g, a, what) {
  assert(a.x >= 0 && a.x < W && a.y >= 0 && a.y < H, `${what} out of field ${a.x},${a.y}`);
  assert(a.ox >= -2 && a.ox <= 1 && a.oy >= -2 && a.oy <= 1, `${what} bad offset ${a.ox},${a.oy}`);
  const t = g.terrain[a.y][a.x];
  assert(t !== T.BRICK && t !== T.SOLID || (a.state === 'dead'), `${what} inside wall at ${a.x},${a.y} lvl ${g.levelNo}`);
}

// 1. Load stats match README: 5-guard cap, 45 hidden-ladder cap.
const g0 = new Game(levels, rng);
let gold = 0;
for (let n = 1; n <= 150; n++) {
  g0.levelNo = n; g0.loadLevel();
  assert(g0.guards.length >= 2 && g0.guards.length <= 5, `guards lvl ${n}`);
  assert(g0.hiddenLadders.length <= 45);
  gold += g0.goldLeft;
}
assert.strictEqual(gold, 2671, 'total gold');
g0.levelNo = 89; g0.loadLevel(); assert.strictEqual(g0.hiddenLadders.length, 45, 'lvl 89 ladder cap');

// 2. Random play on every level: no exceptions, invariants hold.
const DIRS = [null, 'left', 'right', 'up', 'down'];
let deaths = 0, traps = 0, completes = 0, rebirths = 0;
for (let n = 1; n <= 150; n++) {
  const g = new Game(levels, rng);
  g.levelNo = n; g.loadLevel();
  let input = { dir: 'left' };
  for (let i = 0; i < 3000; i++) {
    if (i % 6 === 0) input = { dir: DIRS[Math.floor(rng() * 5)], dig: rng() < 0.25 ? (rng() < 0.5 ? 'left' : 'right') : null };
    g.tick(input);
    for (const e of g.events) {
      if (e === 'death') deaths++;
      if (e === 'trap') traps++;
      if (e === 'rebirth') rebirths++;
      if (e === 'complete') completes++;
    }
    g.events.length = 0;
    if (g.state === 'over') { g.newGame(n); }
    if (g.state === 'play') {
      checkActor(g, g.runner, 'runner');
      g.guards.forEach((a, k) => a.state !== 'dead' && checkActor(g, a, 'guard' + k));
    }
  }
}
console.log(`random play OK: deaths=${deaths} traps=${traps} rebirths=${rebirths} completes=${completes}`);
assert(deaths > 0 && traps > 0 && rebirths > 0, 'mechanics exercised');

// 3. Scripted: on level 1 the runner digs and a hole refills after 180 rounds.
{
  const g = new Game(levels, rng);
  g.guards.length = 0;                       // isolate the runner
  g.tick({ dir: 'left' });
  const r = g.runner;
  const sx = r.x, sy = r.y;
  g.tick({ dig: 'right' });
  for (let i = 0; i < 6; i++) g.tick({});
  assert.strictEqual(g.terrain[sy + 1][sx + 1], T.EMPTY, 'hole opened');
  for (let i = 0; i < 180; i++) g.tick({});
  assert.strictEqual(g.terrain[sy + 1][sx + 1], T.BRICK, 'hole closed');
  console.log('dig/refill OK');
}

// 4. Collecting all gold reveals hidden ladders and reaching row 0 completes.
{
  const g = new Game(levels, rng);
  g.guards.length = 0;
  for (let y = 0; y < H; y++) g.gold[y].fill(false);
  g.state = 'play';
  g.tick({});
  assert(g.revealed, 'ladders revealed');
  assert.strictEqual(g.terrain[0][18], T.LADDER);
  // teleport runner onto the hidden ladder and climb
  Object.assign(g.runner, { x: 18, y: 3, ox: 0, oy: 0 });
  for (let i = 0; i < 40 && g.state === 'play'; i++) g.tick({ dir: 'up' });
  assert.strictEqual(g.state, 'complete', 'level complete');
  const before = g.score;
  for (let i = 0; i < 60; i++) g.tick({});
  assert.strictEqual(g.score - before, 1500);
  assert.strictEqual(g.levelNo, 2);
  console.log('reveal/complete OK');
}
// 5. Two guards in a line for one ladder: the one behind waits for
// the other, it does not turn away and back. A floor at row 10, a ladder
// at column 5 from it up to row 3, the runner up there at column 20.
{
  const g = new Game(levels, rng);
  for (let y = 0; y < H; y++) { g.terrain[y].fill(T.EMPTY); g.gold[y].fill(false); }
  g.terrain[11].fill(T.BRICK);
  g.terrain[4].fill(T.BRICK);
  for (let y = 3; y <= 10; y++) g.terrain[y][5] = T.LADDER;
  g.goldLeft = 1; g.gold[0][0] = true;
  const r = g.runner; r.x = 20; r.y = 3; r.ox = 0; r.oy = 0;
  g.guards.length = 2;
  [[7, 0], [8, 1]].forEach(([x, k]) => Object.assign(g.guards[k], { x, y: 10, ox: 0, oy: 0, state: 'normal', carry: 0 }));
  const b = g.guards[1];
  let turns = 0, last = 0, px = b.x * 8 + b.ox;
  for (let i = 0; i < 120 && b.y === 10; i++) {
    g.tick({});
    const p = b.x * 8 + b.ox, d = Math.sign(p - px);
    if (d && last && d !== last) turns++;
    if (d) last = d;
    px = p;
  }
  assert.strictEqual(turns, 0, 'the guard behind turned back ' + turns + ' times');
  console.log('guards in line OK');
}
// 5b. A hole between a guard and the runner, a ladder behind the guard:
// the chase sees the brick that was there and walks into the hole.
{
  const g = new Game(levels, rng);
  for (let y = 0; y < H; y++) { g.terrain[y].fill(T.EMPTY); g.gold[y].fill(false); }
  g.terrain[14].fill(T.BRICK);
  for (let y = 5; y <= 14; y++) g.terrain[y][1] = T.LADDER;
  g.goldLeft = 1; g.gold[0][0] = true;
  const r = g.runner; r.x = 12; r.y = 13; r.ox = 0; r.oy = 0;
  g.guards.length = 1;
  const b = g.guards[0];
  Object.assign(b, { x: 3, y: 13, ox: 0, oy: 0, state: 'normal', carry: 0 });
  g.tick({ dig: 'left' });
  for (let i = 0; i < 100 && b.y === 13; i++) g.tick({});
  assert.deepStrictEqual([b.x, b.y], [11, 14], 'the guard went to ' + b.x + ',' + b.y);
  console.log('guard into a hole OK');
}

// 6. Stage 145 with the runner walking about: guards do not take each
// other for walls in the chase.
{
  seed = 1;
  const g = new Game(levels, rng);
  g.levelNo = 145; g.loadLevel();
  const st = g.guards.map(a => ({ p: a.x * 8 + a.ox, last: 0 }));
  let turns = 0;
  for (let i = 0; i < 1500 && g.levelNo === 145; i++) {
    g.tick({ dir: ['left', 'right', 'up', 'down'][Math.floor(i / 60) % 4] });
    g.guards.forEach((a, k) => {
      const s = st[k], p = a.x * 8 + a.ox, d = Math.sign(p - s.p);
      if (a.state !== 'normal') { s.last = 0; s.p = p; return; }
      if (d && s.last && d !== s.last) turns++;
      if (d) s.last = d;
      s.p = p;
    });
  }
  assert(turns < 200, 'stage 145: guards turned ' + turns + ' times');
  console.log('stage 145: guards turned ' + turns + ' times');
}
console.log('all tests passed');

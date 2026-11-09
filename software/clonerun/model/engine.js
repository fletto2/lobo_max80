// Lode Runner engine - pure game logic, no DOM.
// Rules and constants follow PHYSICS.md (C64 disassembly readings).
(function (root) {
  'use strict';

  const W = 28, H = 16;          // field size
  const STEP = 4;                // image steps per tile (LR_PosOnImage_Max)
  const T = { EMPTY: 0, BRICK: 1, SOLID: 2, LADDER: 3, BAR: 4, TRAP: 5, HLADDER: 6 };
  const CHAR = { ' ': T.EMPTY, '#': T.BRICK, '@': T.SOLID, 'H': T.LADDER, '-': T.BAR,
                 'X': T.TRAP, 'S': T.HLADDER, '$': T.EMPTY, '0': T.EMPTY, '&': T.EMPTY };

  const C = {
    LIVES_INIT: 5,
    MAX_GUARDS: 5,
    MAX_HLADDERS: 45,
    MAX_HOLES: 30,
    HOLE_OPEN: 180,              // rounds a hole stays open
    HOLE_STEP1: 20, HOLE_STEP2: 10,
    DIG_TIME: 6,                 // rounds the dig beam takes
    BIRTH_TIME: 20,              // rounds until a killed guard reappears
    SCORE_GOLD: 250, SCORE_TRAP: 75, SCORE_REBIRTH: 75, SCORE_LEVEL: 1500,
    MAX_DIFFICULTY: 10,
  };
  // Guard moves per round, cycled over 6 rounds, indexed by guard count
  // (+ difficulty), the table of Simon Hung's Lode Runner Total Recall
  // (github.com/SimonHung/LodeRunner_TotalRecall). With 5 guards each guard moves 2 rounds in 5 - always
  // visibly slower than the runner, as on the C64.
  const MOVE_POLICY = [
    [0, 0, 0, 0, 0, 0], [0, 1, 1, 0, 1, 1], [1, 1, 1, 1, 1, 1], [1, 2, 1, 1, 2, 1],
    [1, 2, 2, 1, 2, 2], [2, 2, 2, 2, 2, 2], [2, 2, 3, 2, 2, 3], [2, 3, 3, 2, 3, 3],
    [3, 3, 3, 3, 3, 3], [3, 3, 4, 3, 3, 4], [3, 4, 4, 3, 4, 4], [4, 4, 4, 4, 4, 4],
  ];

  function parseLevels(text) {
    const levels = [];
    let cur = null;
    for (const raw of text.split(/\r?\n/)) {
      const m = /^=== (\d+) ===$/.exec(raw);
      if (m) { cur = []; levels.push(cur); continue; }
      if (cur && cur.length < H && raw.length > 0) cur.push(raw.padEnd(W, ' ').slice(0, W));
    }
    for (const l of levels) while (l.length < H) l.push(' '.repeat(W));
    return levels;
  }

  const wall = t => t === T.BRICK || t === T.SOLID;

  class Game {
    constructor(levels, rng) {
      this.levels = levels;
      this.rng = rng || Math.random;
      this.events = [];          // sound/visual events drained by the front end
      this.newGame(1);
    }

    newGame(level) {
      this.score = 0;
      this.lives = C.LIVES_INIT;
      this.difficulty = 0;
      this.levelNo = level;
      this.birthCol = 0;
      this.loadLevel();
    }

    // ---------- level setup ----------
    loadLevel() {
      const rows = this.levels[this.levelNo - 1];
      this.terrain = []; this.gold = [];
      const guardSpots = [], hl = [];
      this.runner = null;
      for (let y = 0; y < H; y++) {
        this.terrain.push(new Array(W).fill(T.EMPTY));
        this.gold.push(new Array(W).fill(false));
        for (let x = 0; x < W; x++) {
          const ch = rows[y][x];
          this.terrain[y][x] = CHAR[ch] !== undefined ? CHAR[ch] : T.EMPTY;
          if (ch === '$') this.gold[y][x] = true;
          if (ch === '0') guardSpots.push([x, y]);
          if (ch === '&') this.runner = this.makeActor(x, y);
        }
      }
      // Load scan runs bottom-up, right to left; extras past the limits are blanked.
      const scanOrder = (a, b) => (b[1] - a[1]) || (b[0] - a[0]);
      guardSpots.sort(scanOrder);
      for (let y = H - 1; y >= 0; y--)
        for (let x = W - 1; x >= 0; x--)
          if (this.terrain[y][x] === T.HLADDER) {
            if (hl.length < C.MAX_HLADDERS) hl.push([x, y]); else this.terrain[y][x] = T.EMPTY;
          }
      this.hiddenLadders = hl;
      this.guards = guardSpots.slice(0, C.MAX_GUARDS).map(([x, y]) => {
        const g = this.makeActor(x, y);
        Object.assign(g, { state: 'normal', carry: false, carryT: 0, cooldown: 0, holdT: 0, holeX: 0, holeY: 0, deadT: 0 });
        return g;
      });
      if (!this.runner) this.runner = this.makeActor(0, 0);
      Object.assign(this.runner, { digging: null, falling: false, dead: false });
      this.holes = [];
      this.revealed = false;
      this.moveOffset = 0; this.moveId = 0;
      this.state = 'ready';      // ready | play | dying | complete | over
      this.stateT = 0;
      this.round = 0;
      this.goldLeft = this.countGold();
      this.tally = 0;
    }

    makeActor(x, y) {
      return { x, y, ox: 0, oy: 0, face: 1, anim: 0, pose: 'stand', px: x * STEP, py: y * STEP };
    }

    emit(e) { this.events.push(e); }

    // ---------- map queries ----------
    eff(x, y) {                  // tile as it behaves
      if (x < 0 || x >= W || y >= H) return T.SOLID;
      if (y < 0) return T.EMPTY;
      const t = this.terrain[y][x];
      return (t === T.TRAP || t === T.HLADDER) ? T.EMPTY : t;
    }
    guardAt(x, y, except) {
      for (const g of this.guards)
        if (g !== except && g.state !== 'dead' && g.x === x && g.y === y) return g;
      return null;
    }
    holeAt(x, y) { return this.holes.find(h => h.x === x && h.y === y && h.open) || null; }
    supports(x, y, self) {       // does tile (x,y) hold up a body above it?
      if (y >= H) return true;
      const t = this.eff(x, y);
      return t === T.BRICK || t === T.SOLID || t === T.LADDER || !!this.guardAt(x, y, self);
    }
    countGold() {
      let n = 0;
      for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) if (this.gold[y][x]) n++;
      for (const g of this.guards) if (g.carry && g.state !== 'dead') n++;
      return n;
    }
    isFalling(a) {
      const cur = this.eff(a.x, a.y);
      if (cur === T.LADDER || (cur === T.BAR && a.oy === 0)) return false;
      if (a.oy < 0) return true;
      return !this.supports(a.x, a.y + 1, a);
    }

    // ---------- movement primitives ----------
    // Each returns true if the actor moved. `isGuard` makes other guards block.
    canMove(a, dir, isGuard) {
      const { x, y, ox, oy } = a;
      const blockedBy = (tx, ty) => wall(this.eff(tx, ty)) || (isGuard && this.guardAt(tx, ty, a));
      switch (dir) {
        case 'left':
          if (ox > 0) return true;
          return x > 0 && !blockedBy(x - 1, y);
        case 'right':
          if (ox < 0) return true;
          return x < W - 1 && !blockedBy(x + 1, y);
        case 'up': {
          const cur = this.eff(x, y);
          if (cur === T.LADDER) {
            if (oy > 0) return true;
            return y > 0 && !blockedBy(x, y - 1);
          }
          return oy > 0 && this.eff(x, y + 1) === T.LADDER;
        }
        case 'down':
          if (oy < 0) return true;
          return y < H - 1 && !wall(this.eff(x, y + 1)) && !this.guardAt(x, y + 1, a);
      }
      return false;
    }
    step(a, dir) {
      if (dir === 'left' || dir === 'right') {
        const d = dir === 'left' ? -1 : 1;
        a.face = d;
        a.ox += d;
        if (a.ox >= 2) { a.x++; a.ox -= STEP; } else if (a.ox < -2) { a.x--; a.ox += STEP; }
        if (a.oy < 0) a.oy++; else if (a.oy > 0) a.oy--;
        a.pose = this.eff(a.x, a.y) === T.BAR && a.oy === 0 ? 'bar' : 'run';
      } else {
        a.oy += dir === 'up' ? -1 : 1;
        if (a.oy >= 2) { a.y++; a.oy -= STEP; } else if (a.oy < -2) { a.y--; a.oy += STEP; }
        if (a.ox < 0) a.ox++; else if (a.ox > 0) a.ox--;
        a.pose = 'climb';
      }
      a.anim++;
    }
    fallStep(a) {
      a.oy++;
      if (a.oy >= 2) { a.y++; a.oy -= STEP; }
      if (a.ox < 0) a.ox++; else if (a.ox > 0) a.ox--;
      a.pose = 'fall';
    }
    snapPose(a) {
      const cur = this.eff(a.x, a.y);
      if (cur === T.BAR && a.oy === 0 && a.pose === 'fall') a.pose = 'bar';
      else if (cur === T.LADDER && a.pose === 'fall') a.pose = 'climb';
      else if (a.pose === 'fall') a.pose = 'stand';
    }

    // ---------- main tick: one logic round ----------
    tick(input) {
      this.round++;
      switch (this.state) {
        case 'ready':
          if (input && (input.dir || input.dig)) this.state = 'play';
          else return;
          break;
        case 'dying':
          if (++this.stateT >= 18) {
            if (this.lives <= 0) { this.state = 'over'; this.emit('gameover'); }
            else this.loadLevel();
          }
          return;
        case 'complete':
          this.stateT++;
          if (this.tally < C.SCORE_LEVEL) {
            this.tally += 100; this.score += 100;
            this.emit({ type: 'tally', n: this.tally / 100 });
          } else if (this.stateT > 25) this.nextLevel(1);
          return;
        case 'over':
          return;
      }
      for (const a of [this.runner, ...this.guards]) { a.px = a.x * STEP + a.ox; a.py = a.y * STEP + a.oy; }
      this.updateHoles();
      if (this.state !== 'play') return;
      this.updateRunner(input || {});
      if (this.state !== 'play') return;
      this.updateGuards();
      this.checkGold();
      this.checkCollision();
      if (this.state === 'play' && this.revealed && this.runner.y === 0 && this.runner.oy === 0 && !this.runner.falling) {
        this.state = 'complete'; this.stateT = 0; this.tally = 0;
        this.lives = Math.min(255, this.lives + 1);
        this.emit('complete');
      }
    }

    nextLevel(delta) {
      this.levelNo += delta;
      if (this.levelNo > this.levels.length) {
        this.levelNo = 1;
        this.difficulty = Math.min(C.MAX_DIFFICULTY, this.difficulty + 1);
      }
      if (this.levelNo < 1) this.levelNo = this.levels.length;
      this.loadLevel();
    }

    killRunner() {
      if (this.state !== 'play') return;
      this.lives--;
      this.state = 'dying'; this.stateT = 0;
      this.runner.dead = true;
      this.emit('death');
    }

    // ---------- runner ----------
    updateRunner(input) {
      const r = this.runner;
      if (r.digging) { this.continueDig(); return; }
      r.falling = this.isFalling(r);
      if (r.falling) {
        if (r.pose !== 'fall') this.emit('fallstart');
        this.fallStep(r);
        r.falling = this.isFalling(r);
        if (!r.falling) { this.snapPose(r); this.emit('land'); }
        this.collectGold(r);
        return;
      }
      if (input.dig) { if (this.startDig(input.dig)) return; }
      const dirs = input.dir ? [input.dir] : [];
      for (const d of dirs) {
        if (this.canMove(r, d, false)) { this.step(r, d); break; }
      }
      if (!dirs.length && r.pose === 'run' && r.oy === 0) r.pose = 'stand';
      this.collectGold(r);
    }

    collectGold(a) {
      if (a.ox < -1 || a.ox > 1 || a.oy < -1 || a.oy > 1) return;
      if (this.gold[a.y] && this.gold[a.y][a.x]) {
        this.gold[a.y][a.x] = false;
        this.score += C.SCORE_GOLD;
        this.emit('gold');
      }
    }

    startDig(side) {
      const r = this.runner, d = side === 'left' ? -1 : 1;
      const tx = r.x + d, ty = r.y + 1;
      if (ty >= H || tx < 0 || tx >= W) return false;
      if (this.terrain[ty][tx] !== T.BRICK) return false;
      if (this.eff(tx, r.y) !== T.EMPTY) return false;
      if (this.gold[r.y][tx] || this.guardAt(tx, r.y)) return false;
      if (this.holes.filter(h => h.open).length >= C.MAX_HOLES) return false;
      if (this.holes.some(h => h.x === tx && h.y === ty)) return false;
      r.ox = 0; r.oy = 0; r.face = d; r.pose = 'dig';   // the Apple II nudges it there
      r.digging = { x: tx, y: ty, t: 0, d };
      this.emit('dig');
      return true;
    }

    continueDig() {
      const r = this.runner, dg = r.digging;
      if (this.guardAt(dg.x, dg.y - 1) || this.guardAt(dg.x, dg.y)) { // guard stepped over: abort
        r.digging = null; r.pose = 'stand'; return;
      }
      dg.t++;
      if (dg.t >= C.DIG_TIME) {
        this.terrain[dg.y][dg.x] = T.EMPTY;
        this.holes.push({ x: dg.x, y: dg.y, t: C.HOLE_OPEN, open: true });
        r.digging = null; r.pose = 'stand';
      }
    }

    // ---------- holes ----------
    updateHoles() {
      for (const h of this.holes) {
        if (--h.t > 0) continue;
        h.open = false;
        this.terrain[h.y][h.x] = T.BRICK;
        this.gold[h.y][h.x] = false;          // buried gold is gone; countGold() drops it
        const r = this.runner;
        if (r.x === h.x && r.y === h.y) { this.killRunner(); }
        for (const g of this.guards) {
          if (g.state !== 'dead' && g.x === h.x && g.y === h.y) {
            g.state = 'dead'; g.deadT = C.BIRTH_TIME; g.carry = false;
            this.emit('guarddie');
          }
        }
      }
      this.holes = this.holes.filter(h => h.open);
    }

    // ---------- guards ----------
    updateGuards() {
      for (const g of this.guards) {
        if (g.state === 'trapped' && g.holdT > 0) g.holdT--;
        if (g.state === 'dead' && --g.deadT <= 0) this.rebirth(g);
      }
      const n = this.guards.length;
      if (!n) return;
      const idx = Math.min(MOVE_POLICY.length - 1, n + this.difficulty);
      const moves = MOVE_POLICY[idx][this.moveOffset];
      this.moveOffset = (this.moveOffset + 1) % 6;
      for (let i = 0; i < moves; i++) {
        const g = this.guards[this.moveId];
        this.moveId = (this.moveId + 1) % n;
        this.moveGuard(g);
      }
    }

    rebirth(g) {
      for (let k = 0; k < W * (H - 1); k++) {
        const x = (this.birthCol + k) % W;
        const y = 1 + Math.floor((this.birthCol + k) / W) % (H - 1);
        if (this.terrain[y][x] === T.EMPTY && !this.gold[y][x] && !this.guardAt(x, y) &&
            !(this.runner.x === x && this.runner.y === y)) {
          Object.assign(g, { x, y, ox: 0, oy: 0, state: 'normal', carry: false, cooldown: 0, pose: 'fall', px: x * STEP, py: y * STEP });
          this.birthCol = (this.birthCol + 1) % W;
          this.score += C.SCORE_REBIRTH;
          this.emit('rebirth');
          return;
        }
      }
      g.deadT = 1;               // no room yet, try next round
    }

    moveGuard(g) {
      if (g.state === 'dead') return;
      if (g.cooldown > 0) g.cooldown--;
      if (g.state === 'trapped') {
        if (g.holdT > 0) { g.anim++; return; }
        g.state = 'climb';
      }
      if (g.state === 'climb') { this.climbOut(g); return; }

      if (this.isFalling(g)) {
        this.fallStep(g);
        if (!this.isFalling(g)) this.snapPose(g);
      } else {
        const dir = this.bestMove(g);
        if (dir && this.canMove(g, dir, true)) this.step(g, dir);
        else if (g.pose === 'run') g.pose = 'stand';
      }
      // trapped by a hole?
      if (g.oy === 0 && g.ox > -2 && g.ox < 2 && this.holeAt(g.x, g.y)) {
        g.ox = 0; g.state = 'trapped'; g.holdT = 38 + 4 * this.difficulty;
        g.holeX = g.x; g.holeY = g.y; g.pose = 'fall';
        this.score += C.SCORE_TRAP;
        this.emit('trap');
        if (g.carry) this.dropGold(g, g.x, g.y - 1);
        return;
      }
      this.guardGold(g);
    }

    dropGold(g, x, y) {
      if (y >= 0 && this.eff(x, y) === T.EMPTY && this.terrain[y][x] !== T.TRAP && !this.gold[y][x]) {
        this.gold[y][x] = true; g.carry = false; g.cooldown = 12;
        return true;
      }
      return false;
    }

    guardGold(g) {
      if (!g.carry && g.cooldown === 0 && g.ox > -2 && g.ox < 2 && g.oy > -2 && g.oy < 2 && this.gold[g.y][g.x]) {
        this.gold[g.y][g.x] = false;
        g.carry = true; g.carryT = 12 + Math.floor(this.rng() * 26);
      } else if (g.carry) {
        if (g.carryT > 0) g.carryT--;
        if (g.carryT === 0 && g.ox === 0 && g.oy === 0 && this.terrain[g.y][g.x] === T.EMPTY &&
            this.supports(g.x, g.y + 1, g) && !this.holeAt(g.x, g.y)) this.dropGold(g, g.x, g.y);
      }
    }

    climbOut(g) {
      const rimY = g.holeY - 1;
      if (g.y > rimY || g.oy > 0) {
        if (g.y === g.holeY && g.oy <= 0 && (wall(this.eff(g.x, rimY)) || this.guardAt(g.x, rimY, g))) return;
        g.oy--; if (g.oy < -2) { g.y--; g.oy += STEP; }
        g.pose = 'climb'; g.anim++;
        return;
      }
      if (g.oy < 0) { g.oy++; return; }
      // on the rim: step sideways off the hole column
      const prefer = this.runner.x < g.x ? 'left' : 'right';
      const other = prefer === 'left' ? 'right' : 'left';
      const dir = this.canMove(g, prefer, true) ? prefer : (this.canMove(g, other, true) ? other : null);
      if (!dir) return;
      this.step(g, dir);
      if (g.carry && g.x !== g.holeX) this.dropGold(g, g.holeX, rimY);
      if (g.x !== g.holeX) { g.state = 'normal'; g.cooldown = Math.max(g.cooldown, 4); }
    }

    // Classic Apple II/C64 chase heuristic (EnemyMoveGetDirProposal).
    bestMove(g) {
      const r = this.runner;
      const rx = r.x, ry = r.y;
      let x = g.x; const y = g.y;
      // As the Apple II's DETERMINE_GUARD_MOVE and the C64's: from
      // the next column to the runner's, only a gap stops it. A wall does
      // not, nor another guard: the move then fails and the guard waits.
      if (y === ry) {
        let clear = true;
        while (x !== rx) {
          x += x < rx ? 1 : -1;
          const cur = this.eff(x, y);
          if (cur === T.LADDER || cur === T.BAR || y >= H - 1) continue;
          if (this.seen(x, y + 1) === T.EMPTY && !this.gold[y + 1][x]) { clear = false; break; }
        }
        if (clear) {
          if (g.x < rx) return 'right';
          if (g.x > rx) return 'left';
          return g.ox < r.ox ? 'right' : (g.ox > r.ox ? 'left' : null);
        }
      }
      return this.scanFloor(g);
    }

    // A tile under a body as the chase sees it: a hole is the brick it was.
    // The originals clear the active tile only, and read the background.
    seen(x, y) {
      return this.holes.some(h => h.x === x && h.y === y) ? T.BRICK : this.eff(x, y);
    }

    scanFloor(g) {
      const sx = g.x, sy = g.y, ry = this.runner.y;
      let best = null, bestRating = 255;
      const rate = (x, y, path) => {
        let rating;
        if (y === ry) rating = Math.abs(sx - x);
        else if (y > ry) rating = y - ry + 200;
        else rating = ry - y + 100;
        if (rating < bestRating) { bestRating = rating; best = path; }
      };
      const canStandBeside = (x, y) =>
        x >= 0 && x < W && (y >= H - 1 || [T.BRICK, T.SOLID, T.LADDER].includes(this.seen(x, y + 1)) || this.eff(x, y) === T.BAR);
      const scanDown = (x, path) => {
        let y = sy;
        while (y < H - 1 && !wall(this.seen(x, y + 1))) {
          const cur = this.eff(x, y);
          if (cur !== T.EMPTY || this.gold[y][x]) {   // could step off here
            if ((canStandBeside(x - 1, y) || canStandBeside(x + 1, y)) && y >= ry) break;
          }
          y++;
        }
        rate(x, y, path);
      };
      const scanUp = (x, path) => {
        let y = sy;
        while (y > 0 && this.eff(x, y) === T.LADDER) {
          y--;
          if ((canStandBeside(x - 1, y) || canStandBeside(x + 1, y)) && y <= ry) break;
        }
        rate(x, y, path);
      };
      const passable = (x) => {
        const t = this.eff(x, sy);
        return !wall(t);        // other guards do not count
      };
      const supported = (x) => sy >= H - 1 || this.eff(x, sy) === T.LADDER || this.eff(x, sy) === T.BAR ||
        [T.BRICK, T.SOLID, T.LADDER].includes(this.seen(x, sy + 1));

      let left = sx;
      while (left > 0 && passable(left - 1)) { left--; if (!supported(left)) break; }
      let right = sx;
      while (right < W - 1 && passable(right + 1)) { right++; if (!supported(right)) break; }

      if (sy < H - 1 && !wall(this.seen(sx, sy + 1))) scanDown(sx, 'down');
      if (this.eff(sx, sy) === T.LADDER) scanUp(sx, 'up');
      for (let x = left; x < sx; x++) {      // each wing from its far end
        if (sy < H - 1 && !wall(this.seen(x, sy + 1))) scanDown(x, 'left');
        if (this.eff(x, sy) === T.LADDER) scanUp(x, 'left');
      }
      for (let x = right; x > sx; x--) {
        if (sy < H - 1 && !wall(this.seen(x, sy + 1))) scanDown(x, 'right');
        if (this.eff(x, sy) === T.LADDER) scanUp(x, 'right');
      }
      return best;
    }

    // ---------- global checks ----------
    checkGold() {
      this.goldLeft = this.countGold();
      if (this.goldLeft === 0 && !this.revealed) {
        this.revealed = true;
        for (const [x, y] of this.hiddenLadders) this.terrain[y][x] = T.LADDER;
        this.emit('reveal');
      }
    }

    checkCollision() {
      const r = this.runner;
      const rx = r.x * STEP + r.ox, ry = r.y * STEP + r.oy;
      for (const g of this.guards) {
        if (g.state === 'dead') continue;
        const gx = g.x * STEP + g.ox, gy = g.y * STEP + g.oy;
        if (Math.abs(rx - gx) < 3 && Math.abs(ry - gy) < 3) { this.killRunner(); return; }
      }
    }
  }

  const api = { Game, parseLevels, T, W, H, STEP, C };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.LR = api;
})(typeof window !== 'undefined' ? window : globalThis);

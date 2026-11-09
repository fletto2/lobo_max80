// Lode Runner front end: canvas rendering, keyboard/touch input, sound.
(function () {
  'use strict';
  const { Game, parseLevels, T, W, H, STEP } = window.LR;

  // ---------- setup ----------
  const levels = parseLevels(document.getElementById('level-data').textContent);
  const PX = 2;                       // sprite pixel size
  const TW = 10 * PX, TH = 11 * PX;   // tile size (Apple II 10x11 cell)
  const HUD = 28;
  const canvas = document.getElementById('screen');
  canvas.width = W * TW; canvas.height = H * TH + HUD;
  const ctx = canvas.getContext('2d');

  const store = {
    get(k, d) { try { const v = localStorage.getItem('lr.' + k); return v === null ? d : JSON.parse(v); } catch (e) { return d; } },
    set(k, v) { try { localStorage.setItem('lr.' + k, JSON.stringify(v)); } catch (e) { /* ignore */ } },
  };

  let game = null;
  let screen = 'title';               // title | game
  let startLevel = store.get('lastLevel', 1);
  let hiScore = store.get('hiScore', 0);
  let speed = 5;                      // IRQs per logic round (LR_GameSpeed), 50 Hz
  let paused = false;
  let muted = store.get('muted', false);
  let lastTick = 0, acc = 0;

  // ---------- palette ----------
  const COL = {
    bg: '#000', brick: '#b5461f', brickHi: '#e0693a', mortar: '#3a1408',
    solid: '#6f7ea3', solidHi: '#a9b7d9', solidLo: '#3b4566',
    ladder: '#e8e2c8', bar: '#e8e2c8', gold: '#ffd23f', goldLo: '#b8860b',
    runner: '#ffffff', guard: '#ff4fa3', guardGold: '#ffd23f', hud: '#f2f2f2', hudDim: '#8a8a8a',
  };

  // ---------- sprites (10x11, 'x' = body, 'o' = head) ----------
  const SPR = {
    stand: [
      '....oo....', '....oo....', '...xxxx...', '..x.xx.x..', '..x.xx.x..', '....xx....',
      '...x..x...', '...x..x...', '...x..x...', '..xx..xx..', '..........'],
    run1: [
      '.....oo...', '.....oo...', '....xxx...', '...x.xxx..', '..x..xx.x.', '.....xx...',
      '....x.x...', '...x...x..', '..x....x..', '.x......x.', '..........'],
    run2: [
      '.....oo...', '.....oo...', '....xxx...', '....xxxx..', '....xx..x.', '....xx....',
      '....xx....', '....x.x...', '....x..x..', '...xx..x..', '..........'],
    climb1: [
      '..x.oo....', '..x.oo....', '..xxxxxx..', '....xx.x..', '....xx.x..', '....xx....',
      '...x..x...', '...x...x..', '...x...x..', '...x......', '..........'],
    bar1: [
      '.x......x.', '.x..oo..x.', '..x.oo.x..', '...xxxx...', '....xx....', '....xx....',
      '...x..x...', '...x..x...', '...x...x..', '..xx....x.', '..........'],
    bar2: [
      '.x......x.', '.x..oo..x.', '..x.oo.x..', '...xxxx...', '....xx....', '....xx....',
      '....x.x...', '...x..x...', '..x...x...', '.x....xx..', '..........'],
    fall: [
      '.x..oo..x.', '.x..oo..x.', '..xxxxxx..', '....xx....', '....xx....', '...xxxx...',
      '..x....x..', '..x....x..', '.x......x.', '..........', '..........'],
    dig: [
      '....oo....', '....oo....', '...xxxx...', '..x.xxxxxx', '..x.xx....', '....xx....',
      '...x..x...', '...x..x...', '...x..x...', '..xx..xx..', '..........'],
  };
  SPR.climb2 = SPR.climb1.map(r => r.split('').reverse().join(''));

  const spriteCache = {};
  function sprite(name, color, flip) {
    const key = name + color + (flip ? 'f' : '');
    if (spriteCache[key]) return spriteCache[key];
    const c = document.createElement('canvas');
    c.width = TW; c.height = TH;
    const g = c.getContext('2d');
    const rows = SPR[name];
    for (let y = 0; y < rows.length; y++)
      for (let x = 0; x < 10; x++) {
        const ch = rows[y][flip ? 9 - x : x];
        if (ch === '.') continue;
        g.fillStyle = color;
        g.fillRect(x * PX, y * PX, PX, PX);
      }
    return (spriteCache[key] = c);
  }

  // ---------- tile drawing ----------
  function drawBrick(x, y, fillFrac) {
    // fillFrac: 1 = full brick, <1 = only the bottom part (dig/refill)
    const top = y + Math.round(TH * (1 - fillFrac));
    ctx.fillStyle = COL.brick;
    ctx.fillRect(x, top, TW, y + TH - top);
    ctx.fillStyle = COL.mortar;
    for (let r = 0; r < 3; r++) {
      const ry = y + Math.round(r * TH / 3);
      if (ry + TH / 3 <= top) continue;
      ctx.fillRect(x, Math.max(top, ry + TH / 3 - PX), TW, PX);
      const off = r % 2 ? TW / 2 : 0;
      for (let bx = off; bx < TW; bx += TW) {
        if (ry >= top) ctx.fillRect(x + bx, ry, PX, TH / 3);
      }
    }
    ctx.fillStyle = COL.brickHi;
    if (fillFrac >= 1) ctx.fillRect(x, y, TW, PX);
  }
  function drawSolid(x, y) {
    ctx.fillStyle = COL.solid; ctx.fillRect(x, y, TW, TH);
    ctx.fillStyle = COL.solidHi; ctx.fillRect(x, y, TW, PX); ctx.fillRect(x, y, PX, TH);
    ctx.fillStyle = COL.solidLo; ctx.fillRect(x, y + TH - PX, TW, PX); ctx.fillRect(x + TW - PX, y, PX, TH);
  }
  function drawLadder(x, y, color) {
    ctx.fillStyle = color || COL.ladder;
    ctx.fillRect(x + PX, y, PX, TH); ctx.fillRect(x + TW - 2 * PX, y, PX, TH);
    for (let r = 1; r < TH; r += 4 * PX - 1) ctx.fillRect(x + PX, y + r, TW - 2 * PX, PX);
  }
  function drawBar(x, y) {
    ctx.fillStyle = COL.bar; ctx.fillRect(x, y + PX, TW, PX);
  }
  function drawGold(x, y) {
    ctx.fillStyle = COL.goldLo; ctx.fillRect(x + 2 * PX, y + 6 * PX, 6 * PX, 4 * PX);
    ctx.fillStyle = COL.gold; ctx.fillRect(x + 3 * PX, y + 5 * PX, 4 * PX, 4 * PX);
    ctx.fillRect(x + 2 * PX, y + 7 * PX, 6 * PX, 2 * PX);
    ctx.fillStyle = '#fff6c0'; ctx.fillRect(x + 4 * PX, y + 6 * PX, PX, PX);
  }

  function drawField(g) {
    ctx.fillStyle = COL.bg; ctx.fillRect(0, 0, canvas.width, canvas.height);
    const holeMap = {};
    for (const h of g.holes) holeMap[h.x + ',' + h.y] = h;
    const dig = g.runner.digging;
    for (let y = 0; y < H; y++)
      for (let x = 0; x < W; x++) {
        const px = x * TW, py = y * TH;
        const tile = g.terrain[y][x];
        const hole = holeMap[x + ',' + y];
        if (hole) {
          if (hole.t <= 10) drawBrick(px, py, 0.66);       // second crumble-back step
          else if (hole.t <= 20) drawBrick(px, py, 0.33);
        } else if (dig && dig.x === x && dig.y === y) {
          drawBrick(px, py, 1 - dig.t / 6);
        } else if (tile === T.BRICK || tile === T.TRAP) drawBrick(px, py, 1);
        else if (tile === T.SOLID) drawSolid(px, py);
        else if (tile === T.LADDER) drawLadder(px, py);
        else if (tile === T.BAR) drawBar(px, py);
        if (g.gold[y][x]) drawGold(px, py);
      }
    // dig spark beam
    if (dig) {
      const bx = dig.x * TW, by = (dig.y - 1) * TH;
      ctx.fillStyle = (g.round & 1) ? '#9ff' : '#fff';
      for (let i = 0; i < 6; i++) {
        const sx = bx + ((i * 37 + g.round * 13) % TW), sy = by + TH - 2 * PX - ((i * 23 + g.round * 7) % (TH / 2));
        ctx.fillRect(sx, sy, PX, PX);
      }
    }
  }

  function poseSprite(a) {
    switch (a.pose) {
      case 'run': return (a.anim >> 1) & 1 ? 'run2' : 'run1';
      case 'bar': return (a.anim >> 1) & 1 ? 'bar2' : 'bar1';
      case 'climb': return (a.anim >> 1) & 1 ? 'climb2' : 'climb1';
      case 'fall': return 'fall';
      case 'dig': return 'dig';
      default: return 'stand';
    }
  }

  function drawActor(a, color, alpha, extra) {
    const cx = a.x * STEP + a.ox, cy = a.y * STEP + a.oy;
    let ix = cx, iy = cy;
    if (Math.abs(cx - a.px) <= 2 && Math.abs(cy - a.py) <= 2) { // interpolate between rounds
      ix = a.px + (cx - a.px) * alpha; iy = a.py + (cy - a.py) * alpha;
    }
    const sx = Math.round(ix * TW / STEP), sy = Math.round(iy * TH / STEP);
    const name = poseSprite(a);
    ctx.drawImage(sprite(name, color, a.face < 0 && name !== 'climb1' && name !== 'climb2'), sx, sy);
    if (extra) extra(sx, sy);
  }

  function drawHud(g) {
    const y = H * TH;
    ctx.fillStyle = '#1b1b1b'; ctx.fillRect(0, y, canvas.width, HUD);
    ctx.fillStyle = COL.brick; ctx.fillRect(0, y, canvas.width, PX);
    ctx.font = 'bold 14px "Courier New", monospace';
    ctx.textBaseline = 'middle';
    const pad = (n, w) => String(n).padStart(w, '0');
    const items = [
      ['SCORE', pad(g.score, 7)], ['MEN', pad(g.lives, 3)], ['LEVEL', pad(g.levelNo, 3)],
      ['GOLD', pad(g.goldLeft, 2)], ['HI', pad(Math.max(hiScore, g.score), 7)],
    ];
    let x = 10;
    for (const [k, v] of items) {
      ctx.fillStyle = COL.hudDim; ctx.fillText(k, x, y + HUD / 2 + 1); x += ctx.measureText(k + ' ').width;
      ctx.fillStyle = COL.hud; ctx.fillText(v, x, y + HUD / 2 + 1); x += ctx.measureText(v + '  ').width;
    }
    ctx.fillStyle = COL.hudDim;
    ctx.textAlign = 'right';
    ctx.fillText((g.difficulty ? 'D' + g.difficulty + ' ' : '') + 'SPD ' + (9 - speed) + (muted ? ' MUTE' : ''), canvas.width - 10, y + HUD / 2 + 1);
    ctx.textAlign = 'left';
  }

  function banner(lines, sub) {
    const w = 380, h = 34 + lines.length * 24 + (sub ? 22 : 0);
    const x = (canvas.width - w) / 2, y = (H * TH - h) / 2;
    ctx.fillStyle = 'rgba(0,0,0,0.85)'; ctx.fillRect(x, y, w, h);
    ctx.strokeStyle = COL.brick; ctx.lineWidth = 2; ctx.strokeRect(x + 1, y + 1, w - 2, h - 2);
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.font = 'bold 20px "Courier New", monospace'; ctx.fillStyle = COL.gold;
    lines.forEach((l, i) => ctx.fillText(l, canvas.width / 2, y + 28 + i * 24));
    if (sub) { ctx.font = '14px "Courier New", monospace'; ctx.fillStyle = COL.hud; ctx.fillText(sub, canvas.width / 2, y + h - 18); }
    ctx.textAlign = 'left';
  }

  function render(alpha) {
    if (screen === 'title') { drawTitle(); return; }
    const g = game;
    drawField(g);
    for (const gd of g.guards) {
      if (gd.state === 'dead') continue;
      drawActor(gd, COL.guard, alpha, gd.carry ? (sx, sy) => {
        ctx.fillStyle = COL.guardGold; ctx.fillRect(sx + 4 * PX, sy - PX, 2 * PX, PX);
      } : null);
    }
    const r = g.runner;
    const blink = g.state === 'ready' && (Math.floor(performance.now() / 300) & 1);
    if (g.state === 'dying') {
      const f = g.stateT;
      drawActor(r, f & 1 ? '#ff3030' : COL.runner, 1);
    } else if (!blink) drawActor(r, COL.runner, g.state === 'play' ? alpha : 1);
    drawHud(g);
    if (g.state === 'ready') banner(['LEVEL ' + String(g.levelNo).padStart(3, '0')], 'PRESS AN ARROW KEY TO START');
    else if (g.state === 'complete') banner(['LEVEL COMPLETE', '+' + g.tally], null);
    else if (g.state === 'over') banner(['GAME OVER', 'SCORE ' + g.score], 'ENTER: PLAY AGAIN   ESC: TITLE');
    else if (paused) banner(['PAUSED'], 'P TO RESUME');
  }

  // ---------- title screen ----------
  let titleGame = null;
  function drawTitle() {
    if (!titleGame || titleGame.levelNo !== startLevel) {
      titleGame = new Game(levels); titleGame.levelNo = startLevel; titleGame.loadLevel();
    }
    drawField(titleGame);
    for (const gd of titleGame.guards) drawActor(gd, COL.guard, 1);
    drawActor(titleGame.runner, COL.runner, 1);
    ctx.fillStyle = 'rgba(0,0,0,0.72)'; ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    const cx = canvas.width / 2;
    ctx.font = 'bold 44px "Courier New", monospace';
    ctx.fillStyle = COL.brick; ctx.fillText('CLONE RUNNER', cx + 3, 63);
    ctx.fillStyle = COL.gold; ctx.fillText('CLONE RUNNER', cx, 60);
    ctx.font = '14px "Courier New", monospace'; ctx.fillStyle = COL.hudDim;
    ctx.fillText('THE 150 CLASSIC LEVELS', cx, 92);
    ctx.font = 'bold 22px "Courier New", monospace'; ctx.fillStyle = COL.hud;
    ctx.fillText('<  LEVEL ' + String(startLevel).padStart(3, '0') + '  >', cx, 140);
    ctx.font = '15px "Courier New", monospace';
    const help = [
      'ARROWS / WASD   RUN, CLIMB, HANG, DROP',
      'Z or Q   DIG LEFT      X or E   DIG RIGHT',
      'P PAUSE   M MUTE   + / - SPEED   R RESTART LEVEL',
      '', 'Collect all the gold, then climb to the top.',
      'Dig holes to trap guards. Holes refill!',
    ];
    help.forEach((l, i) => { ctx.fillStyle = i < 3 ? COL.hud : COL.hudDim; ctx.fillText(l, cx, 185 + i * 22); });
    ctx.font = 'bold 18px "Courier New", monospace';
    ctx.fillStyle = (Math.floor(performance.now() / 500) & 1) ? COL.gold : COL.hud;
    ctx.fillText('PRESS ENTER OR SPACE TO PLAY', cx, 340);
    ctx.font = '14px "Courier New", monospace'; ctx.fillStyle = COL.hudDim;
    ctx.fillText('HIGH SCORE ' + String(hiScore).padStart(7, '0'), cx, 368);
    ctx.textAlign = 'left';
  }

  // ---------- sound ----------
  let actx = null;
  function audio() {
    if (muted) return null;
    if (!actx) { try { actx = new (window.AudioContext || window.webkitAudioContext)(); } catch (e) { return null; } }
    if (actx.state === 'suspended') actx.resume();
    return actx;
  }
  function tone(freq, dur, type, vol, slideTo, delay) {
    const a = audio(); if (!a) return;
    const t0 = a.currentTime + (delay || 0);
    const o = a.createOscillator(), gn = a.createGain();
    o.type = type || 'square';
    o.frequency.setValueAtTime(freq, t0);
    if (slideTo) o.frequency.exponentialRampToValueAtTime(slideTo, t0 + dur);
    gn.gain.setValueAtTime(vol || 0.06, t0);
    gn.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
    o.connect(gn).connect(a.destination);
    o.start(t0); o.stop(t0 + dur + 0.02);
  }
  const SOUNDS = {
    gold: () => { tone(880, 0.06); tone(1320, 0.08, 'square', 0.06, null, 0.06); },
    dig: () => tone(200, 0.25, 'sawtooth', 0.05, 60),
    trap: () => tone(500, 0.15, 'triangle', 0.08, 250),
    guarddie: () => tone(300, 0.3, 'square', 0.05, 40),
    rebirth: () => tone(150, 0.2, 'triangle', 0.06, 600),
    death: () => { for (let i = 0; i < 6; i++) tone(600 - i * 80, 0.12, 'square', 0.07, null, i * 0.12); },
    reveal: () => { [523, 659, 784, 1046].forEach((f, i) => tone(f, 0.15, 'square', 0.06, null, i * 0.1)); },
    complete: () => {},
    gameover: () => { [392, 330, 262, 196].forEach((f, i) => tone(f, 0.3, 'triangle', 0.08, null, i * 0.3)); },
    fallstart: () => tone(900, 0.5, 'triangle', 0.035, 250),
  };
  function playEvents(g) {
    for (const e of g.events) {
      if (typeof e === 'object' && e.type === 'tally') tone(300 + e.n * 40, 0.07, 'square', 0.05);
      else if (SOUNDS[e]) SOUNDS[e]();
    }
    g.events.length = 0;
  }

  // ---------- input ----------
  const held = [];                    // direction keys, most recent last
  let digQueued = null, dirQueued = null, digHeld = { left: false, right: false };
  const KEYDIR = {
    ArrowLeft: 'left', ArrowRight: 'right', ArrowUp: 'up', ArrowDown: 'down',
    a: 'left', d: 'right', w: 'up', s: 'down', j: 'left', l: 'right', i: 'up', k: 'down',
  };
  const KEYDIG = { z: 'left', q: 'left', u: 'left', x: 'right', e: 'right', o: 'right' };

  function pressDir(d) { dirQueued = d; const i = held.indexOf(d); if (i >= 0) held.splice(i, 1); held.push(d); }
  function releaseDir(d) { const i = held.indexOf(d); if (i >= 0) held.splice(i, 1); }
  function pressDig(s) { digQueued = s; digHeld[s] = true; }
  function releaseDig(s) { digHeld[s] = false; }

  function currentInput() {
    const dig = digQueued || (digHeld.left ? 'left' : digHeld.right ? 'right' : null);
    // a tap shorter than one logic round still counts once
    return { dir: held.length ? held[held.length - 1] : dirQueued, dig };
  }

  function startGame(level) {
    game = new Game(levels);
    game.newGame(level);
    screen = 'game'; paused = false;
    store.set('lastLevel', level);
    held.length = 0; digQueued = null; dirQueued = null;
  }

  function saveHi() {
    if (game && game.score > hiScore) { hiScore = game.score; store.set('hiScore', hiScore); }
  }

  window.addEventListener('keydown', (ev) => {
    const k = ev.key.length === 1 ? ev.key.toLowerCase() : ev.key;
    audio();
    if (screen === 'title') {
      if (k === 'ArrowLeft' || k === 'a') startLevel = startLevel > 1 ? startLevel - 1 : levels.length;
      else if (k === 'ArrowRight' || k === 'd') startLevel = startLevel < levels.length ? startLevel + 1 : 1;
      else if (k === 'ArrowUp' || k === 'w') startLevel = Math.min(levels.length, startLevel + 10);
      else if (k === 'ArrowDown' || k === 's') startLevel = Math.max(1, startLevel - 10);
      else if (k === 'Enter' || k === ' ') startGame(startLevel);
      else if (k === 'm') toggleMute();
      else return;
      ev.preventDefault();
      return;
    }
    if (KEYDIR[k]) { pressDir(KEYDIR[k]); ev.preventDefault(); return; }
    if (KEYDIG[k]) { pressDig(KEYDIG[k]); ev.preventDefault(); return; }
    if (k === 'p' || (k === 'Escape' && game.state === 'play')) { paused = !paused; }
    else if (k === 'm') toggleMute();
    else if (k === '+' || k === '=') speed = Math.max(3, speed - 1);
    else if (k === '-' || k === '_') speed = Math.min(8, speed + 1);
    else if (k === 'r' && (game.state === 'play' || game.state === 'ready')) { paused = false; game.state = 'play'; game.killRunner(); }
    else if (game.state === 'over' && k === 'Enter') { saveHi(); startGame(game.levelNo); }
    else if (k === 'Escape') { saveHi(); screen = 'title'; }
    else if (k === ']' || k === 'PageDown') { game.nextLevel(1); store.set('lastLevel', game.levelNo); }
    else if (k === '[' || k === 'PageUp') { game.nextLevel(-1); store.set('lastLevel', game.levelNo); }
    else return;
    ev.preventDefault();
  });
  window.addEventListener('keyup', (ev) => {
    const k = ev.key.length === 1 ? ev.key.toLowerCase() : ev.key;
    if (KEYDIR[k]) releaseDir(KEYDIR[k]);
    if (KEYDIG[k]) releaseDig(KEYDIG[k]);
  });
  window.addEventListener('blur', () => { held.length = 0; digHeld.left = digHeld.right = false; if (screen === 'game' && game.state === 'play') paused = true; });

  function toggleMute() { muted = !muted; store.set('muted', muted); }

  // touch controls
  document.querySelectorAll('[data-dir],[data-dig],[data-act]').forEach((b) => {
    const down = (ev) => {
      ev.preventDefault(); audio();
      if (screen === 'title') { startGame(startLevel); return; }
      if (b.dataset.dir) pressDir(b.dataset.dir);
      if (b.dataset.dig) pressDig(b.dataset.dig);
      if (b.dataset.act === 'pause') paused = !paused;
      if (b.dataset.act === 'start' && game.state === 'over') startGame(game.levelNo);
    };
    const up = (ev) => {
      ev.preventDefault();
      if (b.dataset.dir) releaseDir(b.dataset.dir);
      if (b.dataset.dig) releaseDig(b.dataset.dig);
    };
    b.addEventListener('pointerdown', down);
    b.addEventListener('pointerup', up);
    b.addEventListener('pointercancel', up);
    b.addEventListener('pointerleave', up);
  });
  canvas.addEventListener('pointerdown', () => { audio(); if (screen === 'title') startGame(startLevel); });

  // ---------- scaling ----------
  function fit() {
    const touch = document.body.classList.contains('touch');
    const availW = window.innerWidth - 16, availH = window.innerHeight - (touch ? 190 : 24);
    let s = Math.min(availW / canvas.width, availH / canvas.height);
    if (s >= 1) s = Math.floor(s * 2) / 2;
    canvas.style.width = Math.floor(canvas.width * s) + 'px';
    canvas.style.height = Math.floor(canvas.height * s) + 'px';
  }
  if (window.matchMedia('(pointer: coarse)').matches) document.body.classList.add('touch');
  window.addEventListener('resize', fit);
  fit();

  // ---------- main loop ----------
  function frame(now) {
    const interval = speed * 20;      // 50 Hz IRQ x LR_GameSpeed
    if (!lastTick) lastTick = now;
    acc += Math.min(250, now - lastTick);
    lastTick = now;
    if (screen === 'game' && !paused) {
      while (acc >= interval) {
        acc -= interval;
        game.tick(currentInput());
        digQueued = null; dirQueued = null;
        playEvents(game);
        if (game.state === 'over') saveHi();
      }
    } else acc = 0;
    render(screen === 'game' ? Math.min(1, acc / interval) : 1);
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
  window.lodeRunner = { get game() { return game; } };   // console access for debugging
})();

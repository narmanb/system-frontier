#!/usr/bin/env node
// Generates regression fixtures by evaluating the *effective* (final-override) legacy
// JavaScript from the frozen HTML reference. Analysis/CI tooling only — never shipped.
//
//   node tools/gen_fixtures.mjs legacy/<file>.html tests/fixtures
//
// Each snippet below is sliced verbatim from the legacy file; the harness only supplies
// stubs for DOM/game globals that the sliced code touches.
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";

const [src, outDir] = process.argv.slice(2);
if (!src || !outDir) { console.error("usage: gen_fixtures.mjs <legacy.html> <outdir>"); process.exit(2); }
const T = fs.readFileSync(src, "utf8");

// --- tiny string-aware bracket matcher -------------------------------------------------
function matchEnd(text, open) {
  const pairs = { "{": "}", "[": "]", "(": ")" };
  const stack = [];
  for (let i = open; i < text.length; i++) {
    const ch = text[i];
    if (ch === '"' || ch === "'" || ch === "`") {
      const q = ch; i++;
      while (i < text.length && text[i] !== q) { if (text[i] === "\\") i++; i++; }
      continue;
    }
    if (pairs[ch]) stack.push(pairs[ch]);
    else if (ch === "}" || ch === "]" || ch === ")") {
      if (stack.pop() !== ch) throw new Error("bracket mismatch at " + i);
      if (!stack.length) return i;
    }
  }
  throw new Error("unterminated from " + open);
}
function sliceFrom(marker, { nth = 0, from = 0 } = {}) {
  let idx = from - 1;
  for (let k = 0; k <= nth; k++) { idx = T.indexOf(marker, idx + 1); if (idx < 0) throw new Error("missing " + marker); }
  let end;
  if (/function\s*[\w$]*\s*\(/.test(marker)) {
    const paren = T.indexOf("(", idx + marker.search(/function/));
    end = matchEnd(T, T.indexOf("{", matchEnd(T, paren)));
  } else {
    const firstBracket = Math.min(...["{", "["].map(c => { const j = T.indexOf(c, idx + marker.length - 1); return j < 0 ? 1e12 : j; }));
    end = matchEnd(T, firstBracket);
  }
  return T.slice(idx, end + 1) + ";\n";
}
const fn = (name, opts) => sliceFrom(`function ${name}(`, opts);
const line = (startsWith) => { const l = T.split("\n").find(x => x.startsWith(startsWith)); if (!l) throw new Error("no line " + startsWith); return l + "\n"; };

// --- assemble the effective engineering code ------------------------------------------
const v61Marker = T.indexOf("// v6.1: selectable 24/32/48");
let code = "";
code += line("const clamp=");
code += "const TAU=Math.PI*2;\n";
code += line("const palette=");
code += fn("defaultThrusters") + fn("normalizeThrusters");
code += T.slice(T.indexOf("const V6_STAT_BUDGET="), T.indexOf("function v6Clone(o)"));
code += fn("v6Stats") + fn("v6Modules") + fn("v6SpecialFromModules") + fn("v6ModuleInfo");
code += fn("v6ApplyComponentStats") + fn("v6DefaultHardpoints") + fn("v6NormalizeHardpoints") + fn("v6HardpointWorld");
code += "var v6Performance;\n" + sliceFrom("v6Performance=function(shipLike", { from: v61Marker }); // FINAL override (v6.1)
code += fn("v6EffectiveShip");
code += line("const V65_STARTER_HULLS=");
// Built-in ship definitions as patched by v6ApplyBuiltins + v68ApplyRedFalconDefault
code += `const BASE_SHIPS=[{id:"dart",team:"Avengers"},{id:"skull",team:"Pirates"},{id:"mantis",team:"Predators"},{id:"wedge",team:"Renegades"},{id:"fuzz",team:"Fuzzy"},{id:"lance",team:"Knights"},{id:"needle",team:"Speed"}];\nconst RED_FALCON_GRID=[];\n`;
code += fn("v6ApplyBuiltins") + fn("v68ApplyRedFalconDefault");
code += "v6ApplyBuiltins();v68ApplyRedFalconDefault();\n";
// NPC archetype defs (v6.9) with grid arrays stubbed
code += "const GRUNT_GRID=0,QUICK_GRID=0,BEAM_GRID=0,HUNTER_GRID=0,RAIDER_GRID=0,POLICE_GRID=0;\n";
// v6.9 ramps, NPC defs and v69FactionRecolor (sliced as one range from the v6.9 IIFE)
code += T.slice(T.indexOf("const V69_FACTION_RAMPS="), T.indexOf("function v69BuildShipGrid"));
// v7.2.4 faction recolor helpers (inside an IIFE in the original; sliced as-is)
code += T.slice(T.indexOf("const V724_STYLES="), T.indexOf("function v724ApplyFactionPalette"));
// v7.2.4 final faction colours
const factionsSrc = sliceFrom("const FACTIONS=");
code += factionsSrc;
code += T.slice(T.indexOf("Object.assign(FACTIONS.Avengers"), T.indexOf("const V724_STYLES="));

const ctx = { Math, JSON, Number, Object, Array, String, console, Set, Map };
vm.createContext(ctx);
vm.runInContext(code + "\nthis.__exports={v6Performance,v6Stats,v6Modules,v6EffectiveShip,v6HardpointWorld,V6_MODULES,V6_ARCHETYPES,V6_COMPONENTS,V6_RARE_TECH,V6_STAT_ORDER,V6_STAT_LABELS,V6_STAT_BUDGET,V6_MOUNT_BUDGET,V65_STARTER_HULLS,BASE_SHIPS,V69_NPC_DEFS,FACTIONS,v69FactionRecolor,v724MaterialPixel,V724_STYLES};", ctx);
const L = ctx.__exports;

const round = (v) => typeof v === "number" ? Math.round(v * 1e9) / 1e9 : v;
const clean = (o) => JSON.parse(JSON.stringify(o, (k, v) => round(v)));
const write = (name, obj) => { fs.mkdirSync(outDir, { recursive: true }); fs.writeFileSync(path.join(outDir, name), JSON.stringify(clean(obj), null, 1) + "\n"); console.log("wrote", name); };

// --- 1. performance fixtures ------------------------------------------------------------
const PERF_KEYS = ["mass","demand","capacity","rawPowerRatio","powerFactor","overloadAmount","accelPowerFactor","turnPowerFactor","weaponPowerFactor","modulePowerFactor","criticalOverload","speedPowerFactor","thrusterMult","maxSpeed","acceleration","turnRate","passiveLoss","coastDrag","maxHull","maxFuel","fuelBurn","fuelSeconds","damage","fireInterval","cooling","heatPerShot","missileBonus","missileDamage","shield","cloak","repair","pickupRadius","salvageMult","scannerRange"];
const cases = [];
const add = (name, ship, components = {}, rare = {}) => {
  const p = L.v6Performance(ship, components, rare);
  const expected = Object.fromEntries(PERF_KEYS.map(k => [k, p[k]]));
  expected.mods = p.mods; expected.stats = p.stats;
  cases.push({ name, input: { ship, components, rare }, expected });
};
for (const [id, h] of Object.entries(L.V65_STARTER_HULLS)) add("starter:" + id, { ...h, gridSize: 48 });
for (const s of L.BASE_SHIPS) add("builtin:" + s.id, { stats: s.stats, modules: s.modules, thrusters: s.thrusters, gridSize: s.gridSize || 24 });
for (const [id, a] of Object.entries(L.V6_ARCHETYPES)) add("archetype:" + id, { stats: a.stats, modules: a.modules, gridSize: 48 });
// Reactor overload sweep: heavy demand, low reactor
for (const r of [1, 2, 3, 4, 6, 10]) add("overload:reactor" + r, { stats: { reactor: r, hull: 8, weaponPower: 8 }, modules: { primary: "heavy", secondary: "emp", defense: "cloak", utility: "repair", scanner: "longRange" }, thrusters: [{ id: "left", enabled: true }, { id: "right", enabled: true }], gridSize: 48 });
// Legacy field aliases (pre-v6 'brake','armor','fuel','laser') must migrate exactly like v6Stats
add("legacy-aliases", { stats: { acceleration: 4, maxSpeed: 7, brake: 4, turn: 5, armor: 5, fuel: 4, laser: 5, cargo: 6 }, special: "tractor" });
add("components+rare", { ...L.V65_STARTER_HULLS.redFalcon, gridSize: 48 }, { lightweight: true, recycler: true }, { nobleOverdrive: true, dragonShield: true, demonCooling: true });
add("empty", {});
// Effective ship with campaign upgrades + components (startWave path)
const camp = { ship: { ...L.V65_STARTER_HULLS.redFalcon, gridSize: 48 }, upgrades: { acceleration: 2, maxSpeed: 1, turn: 3, hull: 1 }, components: { engineCore: true, governor: true, coolingJacket: true } };
const eff = L.v6EffectiveShip(camp);
add("campaign-effective:redFalcon", eff, camp.components, {});
cases.at(-1).input.campaign = camp; cases.at(-1).effectiveStats = eff.stats;
write("performance.json", { source: path.basename(src), generator: "tools/gen_fixtures.mjs", cases });

// --- 2. flight fixture: run the FINAL update() (block 1 override) for scripted inputs ---
const updSrc = sliceFrom("update=function(dt){const p=game.player,c=game.campaign||{};p.fire-=dt;p.missileCd-=dt;p.thrusting=false;p.weaponHeat");
const flightCode = line("const clamp=") + "const TAU=Math.PI*2;\n" + fn("wrapObj") + "var update;\n" + updSrc;
const flightRuns = [];
for (const [name, hull] of [["redFalcon", L.V65_STARTER_HULLS.redFalcon], ["blockadeRam", L.V65_STARTER_HULLS.blockadeRam], ["wispNeedle", L.V65_STARTER_HULLS.wispNeedle]]) {
  const perf = L.v6Performance({ ...hull, gridSize: 48 }, {}, {});
  const fctx = { Math, performance: { now: () => 0 }, msg() {}, firePlayer() {}, fireMissile() {}, updateBullets() {}, updateShips() {}, updateItems() {}, updateHazards() {}, updateParticles() {}, updateMission() {}, updateHUD() {}, updateStrategy() {}, editor: { testOptions: {} } };
  vm.createContext(fctx);
  vm.runInContext(flightCode + "\nthis.__update=update;", fctx);
  const p = { x: 1300, y: 900, a: -Math.PI / 2, vx: 0, vy: 0, r: 18, hull: perf.maxHull, maxHull: perf.maxHull, fuel: perf.maxFuel, maxFuel: perf.maxFuel, maxSpeed: perf.maxSpeed, acceleration: perf.acceleration, turnRate: perf.turnRate, fuelBurn: perf.fuelBurn, coastDrag: perf.coastDrag, fire: 0, fireInterval: perf.fireInterval, weaponCooling: perf.cooling, weaponHeat: 0, heatPerShot: perf.heatPerShot, missileCd: 0, shieldHP: perf.shield, maxShield: perf.shield, shield: perf.shield > 0 ? 1 : 0, shieldRechargeFactor: perf.shieldRechargeFactor, cloakChance: perf.cloak, cloak: 0, repairRate: perf.repair, lastDamageAt: 0, invuln: 4, stats: perf.stats, ships: [] };
  fctx.game = { player: p, campaign: { mode: "action" }, keys: {}, ships: [], test: false, w: 2600, h: 1800, messageTimer: 0 };
  const dt = 1 / 60, samples = [];
  // script: 0-3s thrust, 3-6s coast, 6-7s turn right while coasting, 7-9s thrust (counter-thrust after turn)
  const keysAt = (t) => ({ ArrowUp: t < 3 || (t >= 7 && t < 9), ArrowRight: t >= 6 && t < 7 });
  for (let i = 0; i <= 9 * 60; i++) {
    const t = i * dt;
    if (i % 15 === 0) samples.push({ t, x: p.x, y: p.y, vx: p.vx, vy: p.vy, a: p.a, fuel: p.fuel, speed: Math.hypot(p.vx, p.vy) });
    fctx.game.keys = keysAt(t);
    fctx.__update(dt);
  }
  flightRuns.push({ hull: name, dt, script: "0-3s thrust; 3-6s coast; 6-7s turn right; 7-9s thrust", perf: { maxSpeed: perf.maxSpeed, acceleration: perf.acceleration, turnRate: perf.turnRate, coastDrag: perf.coastDrag, fuelBurn: perf.fuelBurn, maxFuel: perf.maxFuel }, samples });
}
write("flight.json", { source: path.basename(src), world: { w: 2600, h: 1800 }, runs: flightRuns });

// --- 3. faction recolor fixture (v7.2.4 v724MaterialPixel) ------------------------------
const gridOf = (name) => JSON.parse(T.match(new RegExp("const " + name + "=(\\[[^\\]]*\\])"))[1]);
const recolor = [];
for (const [arch, gname] of [["grunt", "GRUNT_GRID"], ["skirmisher", "QUICK_GRID"], ["beam", "BEAM_GRID"], ["hunter", "HUNTER_GRID"], ["raider", "RAIDER_GRID"]]) {
  const raw = gridOf(gname);
  for (const team of ["Avengers", "Pirates", "Predators", "Speed"]) {
    // Effective chain: v69 spawn recolor (only for recolor:true defs) -> v723 stores that as
    // v723OriginalGrid -> v724 material palette is applied to it at draw time.
    const g = L.V69_NPC_DEFS[arch].recolor ? L.v69FactionRecolor(raw, team, arch) : raw;
    const out = g.map((px, i) => L.v724MaterialPixel(px, i, team, arch));
    recolor.push({ archetype: arch, team, grid: out });
  }
}
write("recolor.json", { source: path.basename(src), note: "v724MaterialPixel output for each 48x48 NPC grid (null = transparent)", cases: recolor });

// --- 4. canonical data extracted from effective code -> data/*.json ---------------------
const dataDir = path.join(path.dirname(outDir), "..", "data");
fs.mkdirSync(dataDir, { recursive: true });
const writeData = (name, obj) => { fs.writeFileSync(path.join(dataDir, name), JSON.stringify(clean(obj), null, 1) + "\n"); console.log("wrote data/" + name); };
writeData("engineering.json", { statOrder: L.V6_STAT_ORDER, statLabels: L.V6_STAT_LABELS, statBudget: L.V6_STAT_BUDGET, mountBudget: L.V6_MOUNT_BUDGET, factoryStatCap: 8, modules: L.V6_MODULES, components: L.V6_COMPONENTS, rareTech: L.V6_RARE_TECH, archetypes: L.V6_ARCHETYPES });
const finalStarters = ["redFalcon", "novaSting", "wispNeedle", "blockadeRam", "cargoWarden"]; // v6.9 retained five
const starterArt = { redFalcon: "red_falcon.png", novaSting: "nova_sting.png", wispNeedle: "wisp_needle.png", blockadeRam: "blockade_ram.png", cargoWarden: "cargo_warden.png" };
writeData("starter_hulls.json", { order: finalStarters, hulls: Object.fromEntries(finalStarters.map(id => [id, { ...L.V65_STARTER_HULLS[id], gridSize: 48, art: "res://assets/ships/" + starterArt[id] }])) });
const npc = {};
for (const [id, d] of Object.entries(L.V69_NPC_DEFS)) { const { grid, ...rest } = d; npc[id] = { ...rest, art: "res://assets/ships/npc_" + id + ".png" }; }
writeData("npc_archetypes.json", { archetypes: npc, hostileWeights: { grunt: 42, skirmisher: 24, beam: 16, hunter: 11, raider: 7 }, collectorWeights: { grunt: 58, skirmisher: 18, raider: 14, beam: 10 } });
const factions = {};
for (const [id, f] of Object.entries(L.FACTIONS)) factions[id] = { ...f, playable: id !== "Enforcers", style: L.V724_STYLES[id] || null };
writeData("factions.json", { factions, defaultStyle: L.V724_STYLES.Default });

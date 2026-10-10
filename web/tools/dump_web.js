// Node twin of dump_godot.gd: the same seeds through web/core.js.
//   node web/tools/dump_web.js out.json
const fs = require("fs");
const path = require("path");
const core = require(path.join(__dirname, "..", "core.js"));
const seeds = [20261010, 20250101, 20271231, ...core.SETLIST];
for (let i = 0; i < 24; i++) seeds.push(1000 + i * 7919);
const out = seeds.map((seed) => {
  const spec = core.specForSeed(seed);
  const song = core.compose(spec.style, spec.seed, spec.bpm);
  const charts = {};
  for (const d of core.DIFFICULTIES) charts[d] = core.buildChart(song, d);
  return { spec, song, charts };
});
fs.writeFileSync(process.argv[2], JSON.stringify(out));
console.log(`dumped ${out.length} songs`);

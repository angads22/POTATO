// Headless-Chromium playthrough of Physics Quest 12. Creates a wizard, walks,
// wins a battle (multiple choice), loses a question on purpose (journal),
// wins one with typed answers, beats the Dynamics guardian (gate + pet +
// mastery spell), practises in the Codex, takes a unit test, buys from the
// shop, reloads to check the save, and fails on any page error.
// Runs in a landscape and a phone viewport. Prints "PHYSICS QUEST SMOKE OK".
//   npm i playwright && npx playwright install chromium
//   node physics-quest/tools/smoke.js physics-quest/index.html
const path = require("path");
const { chromium } = require(process.env.PW_PATH || "playwright");

const probe = (page) => page.evaluate(() => window.__pq());
function check(cond, msg, log) { if (!cond) { log.push("FAIL: " + msg); return false; } return true; }

async function answer(page, st, wrong) {
  const q = st.question;
  if (q.typed) {
    await page.fill("#typedInput", wrong ? "123456789" : q.answerText);
    await page.click("#typedSubmit");
  } else {
    await page.click(`.choice[data-i="${wrong ? (q.correct + 1) % 4 : q.correct}"]`);
  }
}

// Plays the current battle to the end. wrongFirst answers the first question wrong.
async function fight(page, { wrongFirst = false, maxTurns = 60 } = {}) {
  let wrongLeft = wrongFirst ? 1 : 0, typedSeen = 0, asked = 0;
  for (let i = 0; i < maxTurns * 10; i++) {
    const st = await probe(page);
    if (st.state !== "battle") return { st, typedSeen, asked };
    if (st.qOpen && st.question) {
      if (st.question.phase === "ask") {
        asked++; if (st.question.typed) typedSeen++;
        await answer(page, st, wrongLeft > 0); wrongLeft = 0;
      } else if (st.question.phase === "feedback") await page.click("#qContinue");
    } else if (await page.$("#bContinue")) {
      await page.click("#bContinue");
    } else if (st.battle && st.battle.phase === "menu" && (await page.$(".spell-btn"))) {
      const eff = await page.$(".spell-btn .eff");
      if (eff) await eff.evaluate((e) => e.parentElement.click()); else await page.click(".spell-btn");
    }
    await page.waitForTimeout(120);
  }
  return { st: await probe(page), typedSeen, asked };
}

async function run(browser, file, vp) {
  const log = [];
  const page = await browser.newPage({ viewport: vp });
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
  await page.goto("file://" + file);
  await page.evaluate(() => localStorage.clear());
  await page.reload();
  await page.waitForTimeout(400);

  // map sanity
  const problems = await page.evaluate(() => window.__pqDebug.mapCheck());
  check(problems.length === 0, "map: " + problems.join("; "), log);

  // create a wizard
  await page.fill("#nameInput", "Tester");
  await page.click(".swatch[data-k='robe']:nth-child(3)");
  await page.click("#btnStart");
  await page.waitForTimeout(200);
  for (let i = 0; i < 5; i++) { await page.click("#dlgNext"); await page.waitForTimeout(60); }
  let st = await probe(page);
  check(st.state === "world" && st.modal === null, "world after intro " + JSON.stringify(st), log);

  // walk with the keyboard
  const x0 = st.pos.x;
  await page.keyboard.down("ArrowRight"); await page.waitForTimeout(600); await page.keyboard.up("ArrowRight");
  st = await probe(page);
  check(st.pos.x > x0 + 40, `keyboard walk moved ${st.pos.x - x0}px`, log);

  // battle 1: first answer wrong (fills the journal), then win with multiple choice
  await page.evaluate(() => window.__pqDebug.battle(1, false));
  let r = await fight(page, { wrongFirst: true });
  st = r.st;
  check(st.state === "world", "battle 1 ended in world", log);
  check(st.xp > 0 || st.level > 1, "battle 1 gave XP " + JSON.stringify(st), log);
  check(st.coins > 25, "battle 1 gave coins", log);
  check(st.journal >= 1, "wrong answer saved to journal", log);
  check(st.answered >= 2 && st.correctCount >= 1, "answers recorded", log);

  // battle 2: typed answers
  await page.evaluate(() => window.__pqDebug.set({ settings: { mode: "type", sound: false, allTopics: false } }));
  await page.evaluate(() => window.__pqDebug.battle(1, false));
  r = await fight(page);
  check(r.st.state === "world", "typed battle ended", log);
  check(r.typedSeen >= 1, `typed questions seen: ${r.typedSeen} of ${r.asked}`, log);
  const afterTyped = await probe(page);
  check(afterTyped.correctCount >= st.correctCount + 1, "typed answers were accepted", log);
  await page.evaluate(() => window.__pqDebug.set({ settings: { mode: "mc", sound: false, allTopics: false } }));

  // boss: the Dynamics guardian opens the gate and gives a pet + mastery spell
  check(!(await page.evaluate(() => window.__pqDebug.reachable(47, 9))), "gate to Momentum Mines starts sealed", log);
  await page.evaluate(() => window.__pqDebug.set({ level: 7 }));
  await page.evaluate(() => window.__pqDebug.battle(1, true));
  r = await fight(page);
  st = r.st;
  check(st.state === "world" && st.bosses.includes("dyn"), "boss defeated " + JSON.stringify(st), log);
  check(st.unlocked >= 2 && (await page.evaluate(() => window.__pqDebug.reachable(47, 9))), "gate opened", log);
  check(st.pet === "newtie", "boss pet awarded", log);
  // the mastery spell shows up in the next battle
  await page.evaluate(() => window.__pqDebug.battle(2, false));
  await page.waitForTimeout(300);
  const spellNames = await page.$$eval(".spell-btn", (els) => els.map((e) => e.textContent));
  check(spellNames.some((t) => t.includes("Newton's Hammer")) && spellNames.some((t) => t.includes("Momentum Crash")), "spells after boss: " + spellNames.join(" | "), log);
  r = await fight(page);
  check(r.st.state === "world", "battle in zone 2 ended", log);

  // codex practice
  await page.click("#btnCodex");
  await page.waitForTimeout(150);
  check((await probe(page)).modal === "codex", "codex opens", log);
  await page.click("details:has(.practice[data-id='kin_accel']) summary");
  await page.click(".practice[data-id='kin_accel']");
  await page.waitForTimeout(150);
  st = await probe(page);
  check(st.qOpen && st.question && st.question.skill === "kin_accel", "practice question opens", log);
  await answer(page, st, false); await page.waitForTimeout(100);
  await page.click(".qbtn[data-a='done']"); await page.waitForTimeout(150);
  check((await probe(page)).modal === "codex", "practice returns to codex", log);

  // a full unit test
  await page.click(".tab[data-t='tests']"); await page.waitForTimeout(100);
  await page.click(".runtest[data-u='wav']"); await page.waitForTimeout(150);
  for (let i = 0; i < 10; i++) {
    st = await probe(page);
    if (!st.question) break;
    await answer(page, st, i === 3); await page.waitForTimeout(80);
    await page.click("#qContinue"); await page.waitForTimeout(80);
  }
  st = await probe(page);
  check(st.modal === "testresult", "unit test finished", log);
  const scoreText = await page.$eval("#sheet h2", (e) => e.textContent);
  check(scoreText.includes("9/10"), "unit test score " + scoreText, log);
  await page.click("#sheetClose"); await page.waitForTimeout(100);

  // shop
  const coins0 = (await probe(page)).coins;
  await page.evaluate(() => window.__pqDebug.teleport(5, 6)); await page.waitForTimeout(150);
  await page.keyboard.press("KeyE"); await page.waitForTimeout(150);
  check((await probe(page)).modal === "shop", "shop opens next to the shop building", log);
  await page.click(".buy[data-id='potion']"); await page.waitForTimeout(100);
  check((await probe(page)).coins === coins0 - 15, "potion bought", log);
  await page.click("#sheetClose"); await page.waitForTimeout(100);

  // reload: the save persists
  const before = await probe(page);
  await page.reload(); await page.waitForTimeout(400);
  await page.click("#btnContinue"); await page.waitForTimeout(200);
  st = await probe(page);
  check(st.state === "world" && st.level === before.level && st.coins === before.coins && st.bosses.includes("dyn") && st.journal === before.journal, "save restored " + JSON.stringify(st), log);

  check(errors.length === 0, "page errors: " + JSON.stringify(errors), log);
  await page.close();
  return log;
}

(async () => {
  const file = path.resolve(process.argv[2] || "physics-quest/index.html");
  const browser = await chromium.launch();
  let ok = true;
  for (const vp of [{ width: 1280, height: 760 }, { width: 400, height: 860 }]) {
    const log = await run(browser, file, vp);
    console.log(`${vp.width}x${vp.height}: ${log.length ? "\n  " + log.join("\n  ") : "pass"}`);
    ok = ok && log.length === 0;
  }
  await browser.close();
  console.log(ok ? "PHYSICS QUEST SMOKE OK" : "PHYSICS QUEST SMOKE FAIL");
  process.exit(ok ? 0 : 1);
})();

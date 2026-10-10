// Headless-Chromium smoke test for the web edition: boots the bundled page,
// starts a setlist song, lets the in-page test autoplay (window.__bot) play
// it through, and checks the song clears with every note hit and no page
// errors. Prints WEB SMOKE OK.
//   npm i playwright && npx playwright install chromium
//   python3 web/build.py && node web/tools/smoke.js web/dist/SliceIt-Web.html
const path = require("path");
const { chromium } = require(process.env.PW_PATH || "playwright");

(async () => {
  const file = path.resolve(process.argv[2] || "web/dist/SliceIt-Web.html");
  const browser = await chromium.launch({ args: ["--autoplay-policy=no-user-gesture-required"] });
  let ok = true;
  for (const vp of [{ width: 1280, height: 760 }, { width: 430, height: 900 }]) {
    const page = await browser.newPage({ viewport: vp });
    const errors = [];
    page.on("pageerror", (e) => errors.push(e.message));
    page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
    await page.goto("file://" + file);
    await page.waitForTimeout(500);
    await page.mouse.click(vp.width / 2, vp.height / 2);            // title -> song select
    await page.waitForTimeout(300);
    await page.evaluate(() => { window.__bot = true; });
    await page.keyboard.press("ArrowDown");                          // first setlist song
    await page.keyboard.press("Enter");
    const t0 = Date.now();
    let st = null;
    while (Date.now() - t0 < 150000) {
      st = await page.evaluate(() => window.__slice());
      if (st.state === "results") break;
      await page.waitForTimeout(250);
    }
    const pass = st && st.state === "results" && st.cleared && st.miss === 0 && st.perfect === st.notes && errors.length === 0;
    console.log(`${vp.width}x${vp.height}: ${JSON.stringify(st)} errors=${JSON.stringify(errors)} -> ${pass ? "pass" : "FAIL"}`);
    ok = ok && pass;
    await page.close();
  }
  await browser.close();
  console.log(ok ? "WEB SMOKE OK" : "WEB SMOKE FAIL");
  process.exit(ok ? 0 : 1);
})();

"use strict";

const path = require("path");
const fs = require("fs");
const express = require("express");
const session = require("express-session");
const FileStore = require("session-file-store")(session);

const config = require("./lib/config");
const authRoutes = require("./routes/auth");
const tripRoutes = require("./routes/trips");

const app = express();
app.disable("x-powered-by");
app.use(express.json({ limit: "1mb" }));

// Persist sessions to disk so logins survive the server being turned off/on.
const SESSIONS_DIR = path.join(__dirname, "data", "sessions");
if (!fs.existsSync(SESSIONS_DIR)) fs.mkdirSync(SESSIONS_DIR, { recursive: true });

app.use(
  session({
    store: new FileStore({
      path: SESSIONS_DIR,
      retries: 1,
      logFn: () => {},
    }),
    secret: config.SESSION_SECRET,
    resave: false,
    saveUninitialized: false,
    rolling: true,
    cookie: {
      httpOnly: true,
      sameSite: "lax",
      maxAge: config.SESSION_MAX_AGE,
    },
  })
);

// API
app.use("/api/auth", authRoutes);
app.use("/api/trips", tripRoutes);
app.get("/api/health", (req, res) => res.json({ ok: true, uptime: process.uptime() }));

// Static frontend
app.use(express.static(path.join(__dirname, "public")));

// SPA-ish fallback: send the app shell for any non-API route.
app.get("*", (req, res) => {
  if (req.path.startsWith("/api/")) {
    return res.status(404).json({ error: "Not found." });
  }
  res.sendFile(path.join(__dirname, "public", "index.html"));
});

// Write our PID so stop-server.bat can find and stop us reliably.
const PID_FILE = path.join(__dirname, "data", "server.pid");
try {
  fs.writeFileSync(PID_FILE, String(process.pid), "utf8");
} catch { /* non-fatal */ }

const server = app.listen(config.PORT, config.HOST, () => {
  const lan = localAddresses();
  console.log("");
  console.log("  🧳  Trip Planner is running!");
  console.log("  ----------------------------------------");
  console.log(`  On this computer:  http://localhost:${config.PORT}`);
  for (const ip of lan) {
    console.log(`  On your network:   http://${ip}:${config.PORT}`);
  }
  console.log("  ----------------------------------------");
  console.log("  Press Ctrl+C in this window (or run stop-server.bat) to turn it off.");
  console.log("");
});

// Graceful shutdown so the "off button" closes cleanly.
function shutdown() {
  console.log("\n  Shutting down Trip Planner...");
  try { fs.unlinkSync(PID_FILE); } catch { /* already gone */ }
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 3000).unref();
}
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);

function localAddresses() {
  const os = require("os");
  const out = [];
  const nets = os.networkInterfaces();
  for (const name of Object.keys(nets)) {
    for (const net of nets[name] || []) {
      if (net.family === "IPv4" && !net.internal) out.push(net.address);
    }
  }
  return out;
}

"use strict";

// Bulk-import trips from a JSON file into the planner.
//
//   node scripts/import-trips.js my-trips.json
//
// The JSON should be either a single trip object or an array of them.
// Minimal example:
//   [{ "title": "Weekend in Lisbon", "destination": "Lisbon, Portugal",
//      "startDate": "2026-09-12", "endDate": "2026-09-15", "emoji": "🇵🇹",
//      "color": "sunset", "summary": "Pastéis, miradouros, and Fado." }]
//
// Trips with the same title + start date are skipped so re-running is safe.

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const db = require("../lib/db");

const file = process.argv[2] || path.join(__dirname, "..", "trips.sample.json");
if (!fs.existsSync(file)) {
  console.error(`No file found at ${file}`);
  process.exit(1);
}

let payload;
try {
  payload = JSON.parse(fs.readFileSync(file, "utf8"));
} catch (e) {
  console.error("Could not parse JSON:", e.message);
  process.exit(1);
}

const incoming = Array.isArray(payload) ? payload : [payload];
const now = new Date().toISOString();
const existing = db.getTrips();
let added = 0;
let skipped = 0;

for (const raw of incoming) {
  const dup = existing.find(
    (t) =>
      (t.title || "").toLowerCase() === String(raw.title || "").toLowerCase() &&
      (t.startDate || "") === (raw.startDate || "")
  );
  if (dup) {
    skipped++;
    console.log(`  · skipped (already exists): ${raw.title}`);
    continue;
  }
  const trip = {
    id: crypto.randomUUID(),
    title: raw.title || "Untitled trip",
    destination: raw.destination || "",
    startDate: raw.startDate || "",
    endDate: raw.endDate || "",
    emoji: raw.emoji || "✈️",
    color: raw.color || "sunset",
    summary: raw.summary || "",
    budget: raw.budget || "",
    companions: raw.companions || "",
    notes: raw.notes || "",
    days: Array.isArray(raw.days) ? raw.days : [],
    packing: Array.isArray(raw.packing) ? raw.packing : [],
    links: Array.isArray(raw.links) ? raw.links : [],
    createdBy: "import",
    createdByName: raw.createdByName || "Import",
    createdAt: now,
    updatedAt: now,
  };
  // Give nested items stable ids if missing.
  trip.days.forEach((d) => {
    d.id = d.id || crypto.randomUUID();
    (d.activities || []).forEach((a) => (a.id = a.id || crypto.randomUUID()));
  });
  trip.packing.forEach((p) => (p.id = p.id || crypto.randomUUID()));
  trip.links.forEach((l) => (l.id = l.id || crypto.randomUUID()));

  db.addTrip(trip);
  existing.push(trip);
  added++;
  console.log(`  ✓ added: ${trip.title}`);
}

console.log(`\nDone. ${added} added, ${skipped} skipped.`);

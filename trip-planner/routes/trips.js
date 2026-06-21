"use strict";

const express = require("express");
const crypto = require("crypto");
const db = require("../lib/db");
const { requireAuth } = require("../lib/auth-middleware");

const router = express.Router();
router.use(requireAuth);

const str = (v, max = 2000) => String(v == null ? "" : v).slice(0, max).trim();
const id = () => crypto.randomUUID();

// Normalize whatever the client sends into a clean, predictable trip object.
function normalizeTrip(body, base = {}) {
  const days = Array.isArray(body.days) ? body.days : [];
  const packing = Array.isArray(body.packing) ? body.packing : [];
  const links = Array.isArray(body.links) ? body.links : [];

  return {
    title: str(body.title, 120) || "Untitled trip",
    destination: str(body.destination, 160),
    startDate: str(body.startDate, 20),
    endDate: str(body.endDate, 20),
    emoji: str(body.emoji, 8) || "✈️",
    color: str(body.color, 20) || "sunset",
    summary: str(body.summary, 4000),
    budget: str(body.budget, 60),
    companions: str(body.companions, 400),
    notes: str(body.notes, 8000),
    days: days.map((d) => ({
      id: str(d.id, 60) || id(),
      date: str(d.date, 20),
      title: str(d.title, 160),
      activities: (Array.isArray(d.activities) ? d.activities : []).map((a) => ({
        id: str(a.id, 60) || id(),
        time: str(a.time, 20),
        title: str(a.title, 200),
        note: str(a.note, 1000),
      })),
    })),
    packing: packing.map((p) => ({
      id: str(p.id, 60) || id(),
      label: str(p.label, 200),
      done: !!p.done,
    })),
    links: links.map((l) => ({
      id: str(l.id, 60) || id(),
      label: str(l.label, 160),
      url: str(l.url, 600),
    })),
    ...base,
  };
}

// List all trips (everyone in the household sees the same shared board).
router.get("/", (req, res) => {
  const trips = db.getTrips().sort((a, b) => {
    const ax = a.startDate || a.createdAt || "";
    const bx = b.startDate || b.createdAt || "";
    return ax.localeCompare(bx);
  });
  res.json({ trips });
});

router.get("/:id", (req, res) => {
  const trip = db.findTripById(req.params.id);
  if (!trip) return res.status(404).json({ error: "Trip not found." });
  res.json({ trip });
});

router.post("/", (req, res) => {
  const now = new Date().toISOString();
  const trip = normalizeTrip(req.body || {}, {
    id: id(),
    createdBy: req.user.id,
    createdByName: req.user.displayName,
    createdAt: now,
    updatedAt: now,
  });
  db.addTrip(trip);
  res.status(201).json({ trip });
});

router.put("/:id", (req, res) => {
  const existing = db.findTripById(req.params.id);
  if (!existing) return res.status(404).json({ error: "Trip not found." });
  const patch = normalizeTrip(req.body || {}, {
    createdBy: existing.createdBy,
    createdByName: existing.createdByName,
    createdAt: existing.createdAt,
  });
  const updated = db.updateTrip(req.params.id, patch);
  res.json({ trip: updated });
});

router.delete("/:id", (req, res) => {
  const ok = db.deleteTrip(req.params.id);
  if (!ok) return res.status(404).json({ error: "Trip not found." });
  res.json({ ok: true });
});

module.exports = router;

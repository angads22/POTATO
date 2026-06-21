"use strict";

const db = require("./db");

// Gate the API: every /api/trips call requires a logged-in member.
function requireAuth(req, res, next) {
  if (!req.session || !req.session.userId) {
    return res.status(401).json({ error: "Please log in." });
  }
  const user = db.findUserById(req.session.userId);
  if (!user) {
    return res.status(401).json({ error: "Session expired, please log in again." });
  }
  req.user = user;
  next();
}

module.exports = { requireAuth };

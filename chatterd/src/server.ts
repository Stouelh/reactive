import express from "express";
import cors from "cors";
import dotenv from "dotenv";
import pg from "pg";

dotenv.config();

const app = express();
app.use(cors());
app.use(express.json());

const { Pool } = pg;

const pool = new Pool({
  connectionString: process.env.DATABASE_URL
});

// -------------------
// health
// -------------------
app.get("/health", (req, res) => {
  res.json({ ok: true });
});

// -------------------
// GET chatts
// -------------------
app.get("/getchatts", async (req, res) => {
  try {
    const result = await pool.query(
      "SELECT * FROM chatts ORDER BY time DESC"
    );
    res.json(result.rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "db error" });
  }
});

// -------------------
// POST chatt
// -------------------
app.post("/postchatt/", async (req, res) => {
  const { name, message } = req.body;

  try {
    await pool.query(
      "INSERT INTO chatts (name, message, id) VALUES ($1, $2, gen_random_uuid())",
      [name, message]
    );

    res.json({ ok: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "db error" });
  }
});

const PORT = process.env.PORT ? Number(process.env.PORT) : 8000;

// Proxy Ollama streaming endpoint to the iOS app
app.post("/llmDraft", async (req, res) => {
  try {
    const ollamaResp = await fetch("http://127.0.0.1:11434/api/generate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(req.body),
    });

    res.status(ollamaResp.status);
    res.setHeader("Content-Type", "application/x-ndjson");

    if (!ollamaResp.body) {
      res.end();
      return;
    }

    const reader = ollamaResp.body.getReader();
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      if (value) res.write(Buffer.from(value));
    }
    res.end();
  } catch (err) {
    res.status(500).json({ error: "llmDraft  proxy failed", detail: String(err) });
  }
});


app.listen(PORT, "0.0.0.0", () => {
  console.log(`Server listening on http://0.0.0.0:${PORT}`);
});

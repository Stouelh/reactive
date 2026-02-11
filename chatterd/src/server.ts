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

app.listen(PORT, "0.0.0.0", () => {
  console.log(`Server listening on http://0.0.0.0:${PORT}`);
});

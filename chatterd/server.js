import express from 'express';
import cors from 'cors';
import pg from 'pg';

const { Pool } = pg;
const app = express();

app.use(cors());
app.use(express.json());

const pool = new Pool({
  user: 'chatter',
  password: 'chattchatt',
  database: 'chatterdb',
  host: 'localhost',
  port: 5432,
});

pool.connect()
  .then(() => console.log('✅ PostgreSQL connected'))
  .catch(err => console.error('❌ Database error:', err));

app.get('/', (req, res) => {
  res.send('chatterd is running!');
});

app.get('/getchatts', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT id, name, message, time FROM chatts ORDER BY time ASC'
    );
    const chatts = result.rows.map(row => ({
      id: row.id,
      name: row.name,
      message: row.message,
      time: row.time.toISOString()
    }));
    console.log(`📥 getchatts: ${chatts.length} chatts`);
    res.json(chatts);
  } catch (err) {
    console.error('❌ getchatts error:', err);
    res.status(500).json({ error: 'Database error' });
  }
});

app.post('/postchatt', async (req, res) => {
  try {
    const { name, message } = req.body;
    if (!name || name.length > 32) {
      return res.status(400).json({ error: 'Name required, max 32 chars' });
    }
    if (!message) {
      return res.status(400).json({ error: 'Message required' });
    }
    await pool.query(
      'INSERT INTO chatts (name, message, id) VALUES ($1, $2, gen_random_uuid())',
      [name, message]
    );
    console.log(`📤 postchatt: ${name}`);
    res.json({});
  } catch (err) {
    console.error('❌ postchatt error:', err);
    res.status(500).json({ error: 'Database error' });
  }
});

app.post('/llmDraft', async (req, res) => {
  try {
    const { model, prompt } = req.body;
    if (!model || !prompt) {
      return res.status(400).json({ error: 'model and prompt required' });
    }
    console.log(`🤖 llmDraft: ${model}`);
    const ollamaResp = await fetch('http://127.0.0.1:11434/api/generate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ model, prompt, stream: true }),
    });
    if (!ollamaResp.ok) {
      return res.status(ollamaResp.status).json({ error: 'Ollama error' });
    }
    res.status(200);
    res.setHeader('Content-Type', 'application/x-ndjson');
    if (!ollamaResp.body) {
      res.end();
      return;
    }
    const reader = ollamaResp.body.getReader();
    const decoder = new TextDecoder();
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      if (value) {
        res.write(decoder.decode(value, { stream: true }));
      }
    }
    console.log('✅ llmDraft complete');
    res.end();
  } catch (err) {
    console.error('❌ llmDraft error:', err);
    if (!res.headersSent) {
      res.status(500).json({ error: 'Ollama failed' });
    }
  }
});

const PORT = 8000;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`✅ Server running on http://18.227.21.234:${PORT}`);
});

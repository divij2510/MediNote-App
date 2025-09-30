const express = require('express');
const cors = require('cors');
const WebSocket = require('ws');
const http = require('http');
const path = require('path');
const fs = require('fs');
const sqlite3 = require('sqlite3').verbose();
const { v4: uuidv4 } = require('uuid');

// Function to analyze PCM data and determine sample rate
function analyzePcmData(pcmData) {
  const dataLength = pcmData.length;
  const bytesPerSample = 2; // 16-bit = 2 bytes per sample
  const channels = 1; // mono
  const totalSamples = dataLength / (bytesPerSample * channels);
  
  console.log(`🔍 PCM Analysis: ${dataLength} bytes, ${totalSamples} samples`);
  
  // Try to estimate sample rate based on common chunk sizes
  // Current chunks are 2560 bytes, that's 1280 samples per chunk
  const samplesPerChunk = 2560 / (bytesPerSample * channels); // 1280 samples
  console.log(`🔍 Samples per chunk: ${samplesPerChunk}`);
  
  // Common sample rates to try
  const commonRates = [16000, 48000, 44100, 22050, 8000, 32000, 24000];
  
  for (const rate of commonRates) {
    const chunkDuration = samplesPerChunk / rate; // seconds per chunk
    console.log(`🔍 ${rate}Hz: ${chunkDuration.toFixed(3)}s per chunk`);
  }
  
  // Use 16kHz to match the configured sample rate in the app
  // This matches the Dart example's approach for medical recordings
  return 16000; // Match the app configuration for medical quality
}

// Function to stream audio chunks directly without creating WAV files
function streamAudioChunks(chunks, res) {
  console.log(`🎵 Streaming ${chunks.length} chunks directly to client`);
  
  // Set appropriate headers for audio streaming
  res.setHeader('Content-Type', 'application/octet-stream');
  res.setHeader('Transfer-Encoding', 'chunked');
  res.setHeader('Cache-Control', 'no-cache');
  
  // Stream each chunk in order
  chunks.forEach((chunk, index) => {
    try {
      // Parse the amplitude_data JSON to extract the actual audio chunk
      const amplitudeData = JSON.parse(chunk.amplitude_data);
      const chunkData = amplitudeData.chunk_data;
      
      if (chunkData && typeof chunkData === 'string') {
        const audioBuffer = Buffer.from(chunkData, 'base64');
        console.log(`📦 Streaming chunk ${index + 1}/${chunks.length}: ${audioBuffer.length} bytes`);
        res.write(audioBuffer);
      } else if (chunkData && typeof chunkData === 'object' && chunkData.chunk_data) {
        // Handle case where chunk_data is an object with nested chunk_data property
        const nestedChunkData = chunkData.chunk_data;
        if (typeof nestedChunkData === 'string') {
          const audioBuffer = Buffer.from(nestedChunkData, 'base64');
          console.log(`📦 Streaming chunk ${index + 1}/${chunks.length}: ${audioBuffer.length} bytes (nested)`);
          res.write(audioBuffer);
        } else {
          console.log(`⚠️ No valid nested chunk data in chunk ${index + 1}/${chunks.length} - skipping`);
          console.log(`🔍 Nested chunk data type: ${typeof nestedChunkData}, value:`, nestedChunkData);
        }
      } else {
        console.log(`⚠️ No valid chunk data in chunk ${index + 1}/${chunks.length} - skipping`);
        console.log(`🔍 Chunk data type: ${typeof chunkData}, value:`, chunkData);
      }
    } catch (parseError) {
      console.error(`❌ Error parsing chunk ${index + 1}/${chunks.length}:`, parseError);
      console.log(`🔍 Raw amplitude_data:`, chunk.amplitude_data);
    }
  });
  
  res.end();
  console.log(`✅ Completed streaming ${chunks.length} chunks`);
}

const app = express();
const PORT = process.env.PORT || 8000;

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static('public'));

// Request logging middleware
app.use((req, res, next) => {
  const timestamp = new Date().toISOString();
  const method = req.method;
  const url = req.url;
  const userAgent = req.get('User-Agent') || 'Unknown';
  const ip = req.ip || req.connection.remoteAddress || 'Unknown';
  
  console.log(`📡 [${timestamp}] ${method} ${url} - IP: ${ip} - UA: ${userAgent}`);
  
  // Log request body for POST/PUT requests (excluding sensitive data)
  if ((method === 'POST' || method === 'PUT') && req.body) {
    const sanitizedBody = { ...req.body };
    // Remove sensitive fields from logging
    if (sanitizedBody.medical_history) {
      sanitizedBody.medical_history = sanitizedBody.medical_history.substring(0, 50) + '...';
    }
    console.log(`📦 Request Body:`, JSON.stringify(sanitizedBody, null, 2));
  }
  
  // Log response when it's sent
  const originalSend = res.send;
  res.send = function(data) {
    const statusCode = res.statusCode;
    const responseTime = Date.now() - req.startTime;
    console.log(`📤 [${timestamp}] Response: ${statusCode} - Time: ${responseTime}ms`);
    if (statusCode >= 400) {
      console.log(`❌ Error Response:`, data);
    }
    originalSend.call(this, data);
  };
  
  req.startTime = Date.now();
  next();
});

// Create public directory for audio files
const publicDir = path.join(__dirname, 'public');
const audioDir = path.join(publicDir, 'audio');
if (!fs.existsSync(publicDir)) fs.mkdirSync(publicDir);
if (!fs.existsSync(audioDir)) fs.mkdirSync(audioDir);

// Database setup
const db = new sqlite3.Database('./medinote.db');

// Initialize database tables
db.serialize(() => {
  // Patients table
  db.run(`CREATE TABLE IF NOT EXISTS patients (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    age INTEGER,
    phone TEXT,
    email TEXT,
    medical_history TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
  )`);

  // Audio sessions table
  db.run(`CREATE TABLE IF NOT EXISTS audio_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    patient_id INTEGER,
    session_id TEXT UNIQUE,
    filename TEXT,
    duration INTEGER DEFAULT 0,
    file_size INTEGER DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    is_completed BOOLEAN DEFAULT 0,
    FOREIGN KEY (patient_id) REFERENCES patients (id)
  )`);

  // Audio chunks table for real-time chunk storage
  db.run(`CREATE TABLE IF NOT EXISTS audio_chunks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    chunk_id TEXT NOT NULL,
    amplitude_data TEXT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    chunk_order INTEGER,
    FOREIGN KEY (session_id) REFERENCES audio_sessions (session_id)
  )`);
});

// WebSocket connection manager
class WebSocketManager {
  constructor() {
    this.activeConnections = new Map();
    this.sessionData = new Map();
  }

  addConnection(sessionId, ws) {
    this.activeConnections.set(sessionId, ws);
    this.sessionData.set(sessionId, {
      startTime: new Date(),
      amplitudeData: [],
      isActive: true,
      isPaused: false
    });
    console.log(`🔌 WebSocket connected: ${sessionId} (Total connections: ${this.activeConnections.size})`);
  }

  pauseSession(sessionId) {
    if (this.sessionData.has(sessionId)) {
      this.sessionData.get(sessionId).isPaused = true;
      console.log(`⏸️ Session paused: ${sessionId}`);
    }
  }

  resumeSession(sessionId) {
    if (this.sessionData.has(sessionId)) {
      this.sessionData.get(sessionId).isPaused = false;
      console.log(`▶️ Session resumed: ${sessionId}`);
    }
  }

  isSessionPaused(sessionId) {
    return this.sessionData.has(sessionId) && this.sessionData.get(sessionId).isPaused;
  }

  removeConnection(sessionId) {
    this.activeConnections.delete(sessionId);
    this.sessionData.delete(sessionId);
    console.log(`🔌 WebSocket disconnected: ${sessionId} (Remaining connections: ${this.activeConnections.size})`);
  }

  isSessionActive(sessionId) {
    return this.activeConnections.has(sessionId);
  }

  addAmplitudeData(sessionId, amplitudeData) {
    if (this.sessionData.has(sessionId)) {
      this.sessionData.get(sessionId).amplitudeData.push(amplitudeData);
    }
  }

  // Store audio chunk in database immediately
  storeAudioChunk(sessionId, chunkId, audioData, chunkOrder) {
    const stmt = db.prepare(`
      INSERT INTO audio_chunks (session_id, chunk_id, amplitude_data, chunk_order)
      VALUES (?, ?, ?, ?)
    `);
    
    stmt.run([
      sessionId,
      chunkId,
      JSON.stringify(audioData),
      chunkOrder
    ], function(err) {
      if (err) {
        console.error('❌ Error storing audio chunk:', err);
      } else {
        console.log(`💾 Stored chunk ${chunkId} for session ${sessionId}`);
      }
    });
    
    stmt.finalize();
  }

  // Get all chunks for a session
  getSessionChunks(sessionId, callback) {
    db.all(`
      SELECT chunk_id, amplitude_data, timestamp, chunk_order
      FROM audio_chunks 
      WHERE session_id = ? 
      ORDER BY chunk_order ASC
    `, [sessionId], callback);
  }

  finalizeSession(sessionId, totalBytes, totalChunks) {
    if (this.sessionData.has(sessionId)) {
      const session = this.sessionData.get(sessionId);
      session.isActive = false;
      session.totalBytes = totalBytes;
      session.totalChunks = totalChunks;
    }
  }

  sendMessage(sessionId, message) {
    const ws = this.activeConnections.get(sessionId);
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(message));
      return true;
    }
    return false;
  }
}

const wsManager = new WebSocketManager();

// Create HTTP server
const server = http.createServer(app);

// WebSocket server
const wss = new WebSocket.Server({ 
  server,
  // Allow connections from any origin for dev tunnel
  verifyClient: (info) => {
    console.log('🔍 WebSocket connection attempt from:', info.origin);
    return true; // Allow all connections
  }
});

wss.on('connection', (ws, req) => {
  console.log('🔌 New WebSocket connection established');
  console.log('📡 Connection details:', {
    origin: req.headers.origin,
    userAgent: req.headers['user-agent'],
    remoteAddress: req.connection.remoteAddress
  });
  
  let sessionId = null;
  let connectionActive = true;
  let sessionProperlyEnded = false;

  ws.on('message', (data) => {
    if (!connectionActive) return;

    try {
      const message = JSON.parse(data.toString());
      const msgType = message.type;
      sessionId = message.session_id;

      switch (msgType) {
        case 'session_start':
          console.log(`🎬 Audio streaming session started: ${sessionId}`);
          wsManager.addConnection(sessionId, ws);
          
          ws.send(JSON.stringify({
            type: 'session_confirmed',
            session_id: sessionId,
            status: 'started'
          }));
          break;

        case 'audio_chunk': {
          // Check if this is an offline chunk upload (session not active but exists in DB)
          const isOfflineUpload = !wsManager.isSessionActive(sessionId);
          
          if (wsManager.isSessionActive(sessionId) && !wsManager.isSessionPaused(sessionId)) {
            console.log(`🎵 Received audio chunk for active session: ${sessionId} (${message.chunk_size} bytes)`);
            
            // Store audio chunk in database with actual audio data
            const chunkId = `audio_chunk_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
            const audioData = {
              chunk_data: message.chunk_data,
              chunk_size: message.chunk_size,
              timestamp: message.timestamp
            };
            
            wsManager.storeAudioChunk(sessionId, chunkId, audioData, 0);
            
            ws.send(JSON.stringify({
              type: 'audio_chunk_received',
              session_id: sessionId,
              chunk_id: chunkId
            }));
          } else if (isOfflineUpload) {
            console.log(`📤 Received offline chunk for session: ${sessionId} (${message.chunk_size} bytes)`);
            
            // Store offline chunk in database - append to existing session
            const chunkId = `offline_chunk_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
            const audioData = {
              chunk_data: message.chunk_data,
              chunk_size: message.chunk_size,
              timestamp: message.timestamp
            };
            
            // Get the next chunk order for this session
            db.get(`
              SELECT MAX(chunk_order) as max_order 
              FROM audio_chunks 
              WHERE session_id = ?
            `, [sessionId], (err, row) => {
              if (err) {
                console.error('❌ Error getting max chunk order:', err);
                return;
              }
              
              const nextOrder = (row?.max_order || 0) + 1;
              console.log(`📊 Session ${sessionId} current max order: ${row?.max_order || 0}, next order: ${nextOrder}`);
              
              wsManager.storeAudioChunk(sessionId, chunkId, audioData, nextOrder);
              
              console.log(`💾 Stored offline chunk ${chunkId} for session ${sessionId} (order: ${nextOrder})`);
            });
            
            ws.send(JSON.stringify({
              type: 'offline_chunk_received',
              session_id: sessionId,
              chunk_id: chunkId
            }));
          } else if (wsManager.isSessionPaused(sessionId)) {
            console.log(`⏸️ Ignoring audio chunk for paused session: ${sessionId}`);
          }
          break;
        }

        case 'session_end':
          // Handle both active sessions and offline uploads
          const isActiveSession = wsManager.isSessionActive(sessionId);
          
          const isOfflineSessionEnd = !isActiveSession;
          console.log(`🎬 Session ended for: ${sessionId} (${isOfflineSessionEnd ? 'offline upload' : 'active session'})`);
          console.log(`🔍 sessionProperlyEnded before: ${sessionProperlyEnded}`);
          
          // Get chunk count and total size from database
          db.get(`
              SELECT 
                COUNT(*) as chunk_count,
                SUM(LENGTH(amplitude_data)) as total_size
              FROM audio_chunks 
              WHERE session_id = ?
            `, [sessionId], (err, row) => {
              if (err) {
                console.error('❌ Error getting session data:', err);
                return;
              }
              
              const chunkCount = row ? row.chunk_count : 0;
              const totalSize = row ? row.total_size : 0;
              console.log(`📊 Session ${sessionId} had ${chunkCount} chunks, total size: ${totalSize} bytes`);
              
              if (chunkCount > 0) {
                // Check if this session already exists (for resumed sessions)
                db.get('SELECT id, is_completed, file_size FROM audio_sessions WHERE session_id = ?', [sessionId], (err, existingSession) => {
                  if (err) {
                    console.error('❌ Error checking existing session:', err);
                    return;
                  }
                  
                  if (existingSession) {
                    // Update existing session to complete with new size
                    db.run(`
                      UPDATE audio_sessions 
                      SET is_completed = 1, 
                          file_size = ? 
                      WHERE session_id = ?
                    `, [totalSize, sessionId], (err) => {
                      if (err) {
                        console.error('❌ Error updating session to complete:', err);
                      } else {
                        console.log(`✅ Updated existing session ${sessionId} to complete with ${totalSize} bytes`);
                      }
                    });
                  } else {
                    // Create new complete session
                    saveAudioSession(sessionId, totalSize, chunkCount, true);
                    console.log(`✅ Created new complete session ${sessionId} with ${chunkCount} chunks`);
                  }
                });
              }
            });
            
            ws.send(JSON.stringify({
              type: 'session_ended',
              session_id: sessionId
            }));
            
            // Mark session as properly ended to prevent auto-save
            sessionProperlyEnded = true;
            console.log(`🔍 sessionProperlyEnded after: ${sessionProperlyEnded}`);
          break;


        case 'session_pause':
          wsManager.pauseSession(sessionId);
          ws.send(JSON.stringify({
            type: 'session_paused',
            session_id: sessionId
          }));
          break;

        case 'session_resume':
          console.log(`🔄 Session resume requested: ${sessionId}`);
          wsManager.resumeSession(sessionId);
          
          // Check if session already has data
          const sessionData = wsManager.sessionData.get(sessionId);
          if (sessionData && sessionData.amplitudeData.length > 0) {
            console.log(`📊 Resuming session with ${sessionData.amplitudeData.length} existing amplitude chunks`);
          }
          
          ws.send(JSON.stringify({
            type: 'session_resumed',
            session_id: sessionId,
            existing_chunks: sessionData ? sessionData.amplitudeData.length : 0
          }));
          break;

        // Duplicate session_end handler removed - handled above
      }
    } catch (error) {
      console.error('❌ Error processing message:', error);
      connectionActive = false;
      ws.close();
    }
  });

  ws.on('close', () => {
    console.log(`🔌 WebSocket connection closed: ${sessionId}`);
    console.log(`🔍 sessionProperlyEnded on close: ${sessionProperlyEnded}`);
    if (sessionId) {
      // Only auto-save if session wasn't properly ended
      if (!sessionProperlyEnded) {
        console.log(`🔄 Session not properly ended, auto-saving: ${sessionId}`);
        _autoSaveSessionOnClose(sessionId);
      } else {
        console.log(`✅ Session properly ended, skipping auto-save: ${sessionId}`);
      }
      wsManager.removeConnection(sessionId);
    }
  });

  ws.on('error', (error) => {
    console.error('❌ WebSocket error:', error);
    if (sessionId) {
      // Auto-save session on error (always save on error)
      console.log(`🔄 WebSocket error, auto-saving: ${sessionId}`);
      _autoSaveSessionOnClose(sessionId);
      wsManager.removeConnection(sessionId);
    }
  });
});

// Auto-save session when WebSocket closes abruptly
function _autoSaveSessionOnClose(sessionId) {
  console.log(`🔄 Auto-saving session on close: ${sessionId}`);
  
  // Get chunk count and total size from database
  db.get(`
    SELECT 
      COUNT(*) as chunk_count,
      SUM(LENGTH(amplitude_data)) as total_size
    FROM audio_chunks 
    WHERE session_id = ?
  `, [sessionId], (err, row) => {
    if (err) {
      console.error('❌ Error getting session data:', err);
      return;
    }
    
    const chunkCount = row ? row.chunk_count : 0;
    const totalSize = row ? row.total_size : 0;
    console.log(`📊 Session ${sessionId} had ${chunkCount} chunks before close`);
    
    if (chunkCount > 0) {
      // Check if session already exists
      db.get('SELECT id, is_completed FROM audio_sessions WHERE session_id = ?', [sessionId], (err, existingSession) => {
        if (err) {
          console.error('❌ Error checking existing session:', err);
          return;
        }
        
        if (existingSession) {
          // Update existing session with new data (keep as incomplete)
          db.run(`
            UPDATE audio_sessions 
            SET file_size = ? 
            WHERE session_id = ?
          `, [totalSize, sessionId], (err) => {
            if (err) {
              console.error('❌ Error updating session:', err);
            } else {
              console.log(`✅ Updated existing session ${sessionId} with ${totalSize} bytes (incomplete)`);
            }
          });
        } else {
          // Create new incomplete session
          saveAudioSession(sessionId, totalSize, chunkCount, false);
          console.log(`✅ Auto-saved incomplete session ${sessionId} with ${chunkCount} chunks`);
        }
      });
    } else {
      console.log(`⚠️ Session ${sessionId} had no chunks, not saving`);
    }
  });
}

// API Routes
app.get('/', (req, res) => {
  res.json({ message: 'MediNote API', version: '1.0.0' });
});

app.get('/health', (req, res) => {
  console.log('🏥 Health check requested');
  res.json({
    status: 'healthy',
    message: 'MediNote Backend is running',
    timestamp: new Date().toISOString(),
    version: '1.0.0'
  });
});

// Patient CRUD operations
app.get('/patients/', (req, res) => {
  const { skip = 0, limit = 100 } = req.query;
  console.log(`👥 GET /patients/ - Skip: ${skip}, Limit: ${limit}`);
  
  db.all(
    'SELECT * FROM patients ORDER BY created_at DESC LIMIT ? OFFSET ?',
    [parseInt(limit), parseInt(skip)],
    (err, rows) => {
      if (err) {
        console.error('❌ Database error in GET /patients/:', err.message);
        res.status(500).json({ error: err.message });
        return;
      }
      console.log(`✅ Found ${rows.length} patients`);
      // Ensure all rows have proper date format
      const formattedRows = rows.map(row => ({
        ...row,
        created_at: row.created_at || new Date().toISOString(),
        updated_at: row.updated_at || new Date().toISOString()
      }));
      res.json(formattedRows);
    }
  );
});

app.get('/patients/:id', (req, res) => {
  const { id } = req.params;
  console.log(`👤 GET /patients/${id} - Fetching patient details`);
  
  db.get('SELECT * FROM patients WHERE id = ?', [id], (err, row) => {
    if (err) {
      console.error('❌ Database error in GET /patients/:id:', err.message);
      res.status(500).json({ error: err.message });
      return;
    }
    if (!row) {
      console.log(`❌ Patient with ID ${id} not found`);
      res.status(404).json({ error: 'Patient not found' });
      return;
    }
    console.log(`✅ Found patient: ${row.name}`);
    // Ensure proper date format
    const formattedRow = {
      ...row,
      created_at: row.created_at || new Date().toISOString(),
      updated_at: row.updated_at || new Date().toISOString()
    };
    res.json(formattedRow);
  });
});

app.post('/patients/', (req, res) => {
  const { name, age, phone, email, medical_history } = req.body;
  console.log(`➕ POST /patients/ - Creating patient: ${name}`);
  
  db.run(
    'INSERT INTO patients (name, age, phone, email, medical_history) VALUES (?, ?, ?, ?, ?)',
    [name, age, phone, email, medical_history],
    function(err) {
      if (err) {
        console.error('❌ Database error in POST /patients/:', err.message);
        res.status(500).json({ error: err.message });
        return;
      }
      
      console.log(`✅ Patient created successfully with ID: ${this.lastID}`);
      // Return the created patient with proper format
      const now = new Date().toISOString();
      res.json({ 
        id: this.lastID, 
        name, 
        age, 
        phone, 
        email, 
        medical_history,
        created_at: now,
        updated_at: now
      });
    }
  );
});

app.put('/patients/:id', (req, res) => {
  const { id } = req.params;
  const { name, age, phone, email, medical_history } = req.body;
  console.log(`✏️ PUT /patients/${id} - Updating patient: ${name}`);
  
  db.run(
    'UPDATE patients SET name = ?, age = ?, phone = ?, email = ?, medical_history = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?',
    [name, age, phone, email, medical_history, id],
    function(err) {
      if (err) {
        console.error('❌ Database error in PUT /patients/:id:', err.message);
        res.status(500).json({ error: err.message });
        return;
      }
      if (this.changes === 0) {
        console.log(`❌ Patient with ID ${id} not found for update`);
        res.status(404).json({ error: 'Patient not found' });
        return;
      }
      
      console.log(`✅ Patient updated successfully: ${name}`);
      // Return the updated patient with proper format
      const now = new Date().toISOString();
      res.json({ 
        id: parseInt(id), 
        name, 
        age, 
        phone, 
        email, 
        medical_history,
        created_at: now, // In a real app, you'd fetch this from DB
        updated_at: now
      });
    }
  );
});

app.delete('/patients/:id', (req, res) => {
  const { id } = req.params;
  console.log(`🗑️ DELETE /patients/${id} - Deleting patient`);
  
  db.run('DELETE FROM patients WHERE id = ?', [id], function(err) {
    if (err) {
      console.error('❌ Database error in DELETE /patients/:id:', err.message);
      res.status(500).json({ error: err.message });
      return;
    }
    if (this.changes === 0) {
      console.log(`❌ Patient with ID ${id} not found for deletion`);
      res.status(404).json({ error: 'Patient not found' });
      return;
    }
    console.log(`✅ Patient deleted successfully (ID: ${id})`);
    res.json({ message: 'Patient deleted successfully' });
  });
});

// Audio session operations
app.get('/patients/:patientId/sessions', (req, res) => {
  const { patientId } = req.params;
  console.log(`🎵 GET /patients/${patientId}/sessions - Fetching audio sessions`);
  
  db.all(
    'SELECT * FROM audio_sessions WHERE patient_id = ? ORDER BY created_at DESC',
    [patientId],
    (err, rows) => {
      if (err) {
        console.error('❌ Database error in GET /patients/:patientId/sessions:', err.message);
        res.status(500).json({ error: err.message });
        return;
      }
      console.log(`✅ Found ${rows.length} audio sessions for patient ${patientId}`);
      res.json(rows);
    }
  );
});


app.get('/sessions/:sessionId/audio', (req, res) => {
  const { sessionId } = req.params;
  console.log(`🎧 GET /sessions/${sessionId}/audio - Fetching audio file`);
  
  db.get(
    'SELECT * FROM audio_sessions WHERE session_id = ?',
    [sessionId],
    (err, row) => {
      if (err) {
        console.error('❌ Database error in GET /sessions/:sessionId/audio:', err.message);
        res.status(500).json({ error: err.message });
        return;
      }
      if (!row) {
        console.log(`❌ Audio session ${sessionId} not found`);
        res.status(404).json({ error: 'Audio session not found' });
        return;
      }
      if (!row.filename) {
        console.log(`❌ Audio file not found for session ${sessionId}`);
        res.status(404).json({ error: 'Audio file not found' });
        return;
      }
      console.log(`✅ Audio file found: ${row.filename}`);
      res.json({ audio_url: `/audio/${row.filename}` });
    }
  );
});

// Get session chunks for playback
app.get('/sessions/:sessionId/chunks', (req, res) => {
  const { sessionId } = req.params;
  console.log(`🎵 GET /sessions/${sessionId}/chunks - Fetching session chunks`);
  
  wsManager.getSessionChunks(sessionId, (err, chunks) => {
    if (err) {
      console.error('❌ Error fetching session chunks:', err);
      res.status(500).json({ error: 'Database error' });
      return;
    }
    
    console.log(`✅ Found ${chunks.length} chunks for session ${sessionId}`);
    res.json({
      session_id: sessionId,
      chunks: chunks,
      total_chunks: chunks.length
    });
  });
});

// Check if session exists and get its status
app.get('/sessions/:sessionId/status', (req, res) => {
  const { sessionId } = req.params;
  console.log(`🔍 GET /sessions/${sessionId}/status - Checking session status`);
  
  const stmt = db.prepare(`
    SELECT 
      s.session_id,
      s.patient_id,
      s.is_completed,
      s.created_at,
      COUNT(c.id) as chunk_count
    FROM audio_sessions s
    LEFT JOIN audio_chunks c ON s.session_id = c.session_id
    WHERE s.session_id = ?
    GROUP BY s.session_id
  `);
  
  stmt.get([sessionId], (err, row) => {
    if (err) {
      console.error('❌ Error checking session status:', err);
      res.status(500).json({ error: 'Database error' });
      return;
    }
    
    if (!row) {
      console.log(`❌ Session not found: ${sessionId}`);
      res.status(404).json({ error: 'Session not found' });
      return;
    }
    
    console.log(`✅ Session ${sessionId} found with ${row.chunk_count} chunks`);
    res.json({
      session_id: row.session_id,
      patient_id: row.patient_id,
      is_completed: row.is_completed,
      created_at: row.created_at,
      chunk_count: row.chunk_count,
      exists: true
    });
  });
  
  stmt.finalize();
});

// Stream audio reconstructed from audio chunks
app.get('/sessions/:sessionId/audio-stream', (req, res) => {
  const { sessionId } = req.params;
  console.log(`🎧 GET /sessions/${sessionId}/audio-stream - Streaming audio chunks directly`);
  
  // Get all audio chunks for this session
  const stmt = db.prepare(`
    SELECT amplitude_data, chunk_order, timestamp
    FROM audio_chunks 
    WHERE session_id = ? 
    ORDER BY chunk_order ASC
  `);
  
  stmt.all([sessionId], (err, chunks) => {
    if (err) {
      console.error('❌ Error fetching chunks for audio stream:', err);
      res.status(500).json({ error: 'Failed to fetch audio chunks' });
      return;
    }
    
    if (chunks.length === 0) {
      console.log(`⚠️ No chunks found for session ${sessionId}`);
      res.status(404).json({ error: 'No audio data found for this session' });
      return;
    }
    
    console.log(`🎵 Streaming ${chunks.length} chunks directly to client`);
    
    // Stream chunks directly without creating WAV files
    streamAudioChunks(chunks, res);
  });
  
  stmt.finalize();
});

// Helper function to save audio session
function saveAudioSession(sessionId, totalBytes, totalChunks, isComplete = true) {
  console.log(`💾 Saving audio session: ${sessionId} (${totalBytes} bytes, ${totalChunks} chunks, complete: ${isComplete})`);
  
  // Extract patient ID from session ID (format: session_timestamp_patientId)
  const sessionParts = sessionId.split('_');
  const patientId = sessionParts.length > 2 ? sessionParts[2] : null;
  
  if (!patientId) {
    console.error('❌ Could not extract patient ID from session ID:', sessionId);
    return;
  }
  
  // For amplitude-based audio, we don't have a physical file
  // The audio is reconstructed from amplitude data on-demand
  const filename = `amplitude_stream_${sessionId}`;
  const fileSize = totalChunks * 8; // Estimate based on chunk count
  
  console.log(`📁 Using amplitude-based audio: ${filename} (${fileSize} bytes estimated)`);
  
  db.run(
    'INSERT OR REPLACE INTO audio_sessions (patient_id, session_id, filename, file_size, is_completed) VALUES (?, ?, ?, ?, ?)',
    [patientId, sessionId, filename, fileSize, isComplete ? 1 : 0],
    function(err) {
      if (err) {
        console.error('❌ Error saving audio session:', err);
      } else {
        console.log(`✅ Audio session saved successfully: ${sessionId} (ID: ${this.lastID}, Patient: ${patientId}, Complete: ${isComplete})`);
      }
    }
  );
}

// Start server
server.listen(PORT, () => {
  console.log(`🚀 MediNote Backend running on port ${PORT}`);
  console.log(`📁 Audio files served from: ${audioDir}`);
});

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\n🛑 Shutting down server...');
  db.close((err) => {
    if (err) {
      console.error('❌ Error closing database:', err);
    } else {
      console.log('✅ Database connection closed');
    }
    process.exit(0);
  });
});

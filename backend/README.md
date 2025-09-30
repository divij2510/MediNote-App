# MediNote Backend - Node.js

A robust Node.js backend for the MediNote medical audio recording application with reliable WebSocket support.

## Features

- **Reliable WebSocket Handling**: No more infinite loops or connection issues
- **Patient Management**: Full CRUD operations for patient records
- **Audio Session Management**: Track and store audio recording sessions
- **Static File Serving**: Serve audio files efficiently
- **SQLite Database**: Lightweight, file-based database
- **CORS Support**: Cross-origin resource sharing enabled

## Installation

1. Install Node.js dependencies:
```bash
npm install
```

2. Start the server:
```bash
npm start
```

For development with auto-restart:
```bash
npm run dev
```

## API Endpoints

### Health Check
- `GET /health` - Server health status

### Patients
- `GET /patients` - List all patients
- `GET /patients/:id` - Get specific patient
- `POST /patients` - Create new patient
- `PUT /patients/:id` - Update patient
- `DELETE /patients/:id` - Delete patient

### Audio Sessions
- `GET /patients/:patientId/sessions` - Get patient's audio sessions
- `GET /sessions/:sessionId/audio` - Get audio file URL

## WebSocket Endpoints

### Audio Streaming
- `ws://localhost:8000` - Main WebSocket connection for audio streaming

#### Message Types:
- `session_start` - Start audio recording session
- `audio_chunk` - Send amplitude data
- `session_pause` - Pause recording
- `session_resume` - Resume recording
- `session_end` - End recording session

## Database Schema

### Patients Table
- `id` (INTEGER PRIMARY KEY)
- `name` (TEXT)
- `age` (INTEGER)
- `phone` (TEXT)
- `email` (TEXT)
- `medical_history` (TEXT)
- `created_at` (DATETIME)
- `updated_at` (DATETIME)

### Audio Sessions Table
- `id` (INTEGER PRIMARY KEY)
- `patient_id` (INTEGER)
- `session_id` (TEXT UNIQUE)
- `filename` (TEXT)
- `duration` (INTEGER)
- `file_size` (INTEGER)
- `created_at` (DATETIME)
- `is_completed` (BOOLEAN)

## Advantages over FastAPI

1. **Reliable WebSocket Handling**: Node.js WebSocket implementation is more stable
2. **Better Error Handling**: No infinite loops or connection issues
3. **Efficient Static Serving**: Built-in Express static file serving
4. **Simpler Architecture**: Less complex than FastAPI WebSocket handling
5. **Better Performance**: Node.js is optimized for I/O operations

## Development

The server runs on `http://localhost:8000` by default. Audio files are served from the `public/audio` directory.

## Logging

The backend includes comprehensive logging for all API operations:

### Request Logging
- **Timestamp**: ISO format for all requests
- **Method & URL**: HTTP method and endpoint
- **Client Info**: IP address and User Agent
- **Request Body**: Sanitized request data (sensitive fields truncated)
- **Response Info**: Status code and response time
- **Error Details**: Full error messages for debugging

### Database Logging
- **Query Results**: Number of records found/affected
- **Error Handling**: Database connection and query errors
- **Transaction Status**: Success/failure of database operations

### WebSocket Logging
- **Connection Events**: Connect/disconnect with session tracking
- **Message Types**: Session start, audio chunks, pause/resume, end
- **Amplitude Data**: Periodic logging of audio data chunks
- **Connection Count**: Active WebSocket connections

### Log Examples
```
📡 [2025-09-29T18:20:40.721Z] GET /patients/ - IP: 127.0.0.1 - UA: MediNote-Flutter-App
👥 GET /patients/ - Skip: 0, Limit: 100
✅ Found 3 patients
📤 [2025-09-29T18:20:40.721Z] Response: 200 - Time: 45ms

🔌 WebSocket connected: session_123 (Total connections: 1)
📊 Session session_123: 10 amplitude chunks received
💾 Saving audio session: session_123 (1024 bytes, 50 chunks)
✅ Audio session saved successfully: session_123 (ID: 5)
```

### Monitoring Logs
```bash
# Start the server with logging
npm start

# View logs in a separate terminal
npm run logs
```

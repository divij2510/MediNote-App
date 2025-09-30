# MediNote API Documentation

## Base URL
- **Production**: `https://medinote-app-production.up.railway.app`
- **Local Development**: `http://localhost:3000`

## Authentication
All API endpoints require proper CORS headers and are designed for mobile app consumption.

## Endpoints

### Health Check
**GET** `/health`
- **Description**: Check if the backend server is running
- **Response**: 
  ```json
  {
    "status": "healthy",
    "timestamp": "2024-01-01T00:00:00.000Z"
  }
  ```

### Patients Management

#### Get All Patients
**GET** `/patients`
- **Description**: Retrieve all patients
- **Response**:
  ```json
  [
    {
      "id": 1,
      "name": "John Doe",
      "age": 30,
      "phone": "+1234567890",
      "email": "john@example.com",
      "created_at": "2024-01-01T00:00:00.000Z"
    }
  ]
  ```

#### Get Patient by ID
**GET** `/patients/:id`
- **Description**: Retrieve a specific patient
- **Parameters**: `id` (integer) - Patient ID
- **Response**:
  ```json
  {
    "id": 1,
    "name": "John Doe",
    "age": 30,
    "phone": "+1234567890",
    "email": "john@example.com",
    "created_at": "2024-01-01T00:00:00.000Z"
  }
  ```

#### Create Patient
**POST** `/patients`
- **Description**: Create a new patient
- **Request Body**:
  ```json
  {
    "name": "John Doe",
    "age": 30,
    "phone": "+1234567890",
    "email": "john@example.com"
  }
  ```
- **Response**:
  ```json
  {
    "id": 1,
    "name": "John Doe",
    "age": 30,
    "phone": "+1234567890",
    "email": "john@example.com",
    "created_at": "2024-01-01T00:00:00.000Z"
  }
  ```

#### Update Patient
**PUT** `/patients/:id`
- **Description**: Update an existing patient
- **Parameters**: `id` (integer) - Patient ID
- **Request Body**:
  ```json
  {
    "name": "John Smith",
    "age": 31,
    "phone": "+1234567890",
    "email": "johnsmith@example.com"
  }
  ```
- **Response**:
  ```json
  {
    "id": 1,
    "name": "John Smith",
    "age": 31,
    "phone": "+1234567890",
    "email": "johnsmith@example.com",
    "created_at": "2024-01-01T00:00:00.000Z"
  }
  ```

#### Delete Patient
**DELETE** `/patients/:id`
- **Description**: Delete a patient
- **Parameters**: `id` (integer) - Patient ID
- **Response**: `200 OK` with success message

### Audio Sessions

#### Get All Sessions
**GET** `/sessions`
- **Description**: Retrieve all audio recording sessions
- **Response**:
  ```json
  [
    {
      "id": 1,
      "patient_id": 1,
      "session_id": "session_123",
      "status": "completed",
      "created_at": "2024-01-01T00:00:00.000Z",
      "ended_at": "2024-01-01T00:05:00.000Z"
    }
  ]
  ```

#### Get Session by ID
**GET** `/sessions/:id`
- **Description**: Retrieve a specific session
- **Parameters**: `id` (integer) - Session ID
- **Response**:
  ```json
  {
    "id": 1,
    "patient_id": 1,
    "session_id": "session_123",
    "status": "completed",
    "created_at": "2024-01-01T00:00:00.000Z",
    "ended_at": "2024-01-01T00:05:00.000Z"
  }
  ```

#### Get Sessions by Patient
**GET** `/sessions/patient/:patientId`
- **Description**: Retrieve all sessions for a specific patient
- **Parameters**: `patientId` (integer) - Patient ID
- **Response**: Array of session objects

#### Create Session
**POST** `/sessions`
- **Description**: Create a new audio recording session
- **Request Body**:
  ```json
  {
    "patient_id": 1,
    "session_id": "session_123"
  }
  ```
- **Response**:
  ```json
  {
    "id": 1,
    "patient_id": 1,
    "session_id": "session_123",
    "status": "active",
    "created_at": "2024-01-01T00:00:00.000Z"
  }
  ```

#### End Session
**PUT** `/sessions/:id/end`
- **Description**: Mark a session as ended
- **Parameters**: `id` (integer) - Session ID
- **Response**:
  ```json
  {
    "id": 1,
    "patient_id": 1,
    "session_id": "session_123",
    "status": "completed",
    "created_at": "2024-01-01T00:00:00.000Z",
    "ended_at": "2024-01-01T00:05:00.000Z"
  }
  ```

### WebSocket Connection

#### Audio Streaming
**WebSocket** `/ws`
- **Description**: Real-time audio streaming for recording sessions
- **Connection**: `wss://medinote-app-production.up.railway.app/ws`
- **Events**:
  - `audio_chunk`: Send audio data chunks
  - `session_start`: Initialize new session
  - `session_end`: End current session
  - `health_check`: Ping for connection status

#### WebSocket Message Format
```json
{
  "type": "audio_chunk",
  "sessionId": "session_123",
  "chunkIndex": 1,
  "data": "base64_encoded_audio_data",
  "timestamp": "2024-01-01T00:00:00.000Z"
}
```

## Error Responses

### 400 Bad Request
```json
{
  "error": "Invalid request data",
  "message": "Missing required fields"
}
```

### 404 Not Found
```json
{
  "error": "Not found",
  "message": "Patient not found"
}
```

### 500 Internal Server Error
```json
{
  "error": "Internal server error",
  "message": "Database connection failed"
}
```

## CORS Configuration
The API supports CORS for the following:
- **Origins**: All origins (for mobile app compatibility)
- **Methods**: GET, POST, PUT, DELETE, OPTIONS
- **Headers**: Content-Type, Authorization, X-Requested-With

## Rate Limiting
- No rate limiting implemented
- Designed for single-user mobile app usage

## Database Schema

### Patients Table
```sql
CREATE TABLE patients (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  age INTEGER,
  phone TEXT,
  email TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

### Sessions Table
```sql
CREATE TABLE sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  patient_id INTEGER,
  session_id TEXT UNIQUE NOT NULL,
  status TEXT DEFAULT 'active',
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  ended_at DATETIME,
  FOREIGN KEY (patient_id) REFERENCES patients (id)
);
```

## WebSocket Session Management
- Sessions are automatically cleaned up after 24 hours of inactivity
- Audio chunks are stored temporarily and processed in real-time
- Session state is maintained in memory for active connections

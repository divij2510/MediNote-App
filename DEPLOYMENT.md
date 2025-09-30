# MediNote Backend - Docker Deployment

Simple Docker deployment for the MediNote backend service.

## 🚀 Quick Start

### Prerequisites
- Docker Desktop (Windows/Mac) or Docker Engine (Linux)
- Docker Compose

### Deploy

```bash
# Start the backend service
docker-compose up -d

# View logs
docker-compose logs -f

# Stop services
docker-compose down
```

## 📋 What's Included

- **Backend Service**: Node.js API server
- **Database**: SQLite with persistent storage
- **Audio Storage**: Persistent audio file storage
- **Health Checks**: Automatic health monitoring
- **Auto Restart**: Service restarts on failure

## 🌐 API Endpoints

Once deployed, the service is available at `http://localhost:8000`:

- `GET /health` - Health check
- `GET /api/patients` - List patients
- `POST /api/patients` - Create patient
- `GET /api/patients/:id` - Get patient
- `PUT /api/patients/:id` - Update patient
- `DELETE /api/patients/:id` - Delete patient
- `GET /api/patients/:id/sessions` - Get audio sessions
- `GET /api/audio/:sessionId` - Get audio file
- `WS /ws` - WebSocket for real-time audio streaming

## 📊 Monitoring

### Health Check
```bash
curl http://localhost:8000/health
```

### View Logs
```bash
docker-compose logs -f backend
```

### Container Status
```bash
docker-compose ps
```

## 💾 Data Persistence

- **Database**: `./backend/medinote.db` (SQLite)
- **Audio Files**: `./backend/public/audio/` directory

## 🔧 Management Commands

```bash
# Start services
docker-compose up -d

# Stop services
docker-compose down

# Restart services
docker-compose restart

# View logs
docker-compose logs -f

# Check status
docker-compose ps

# Access container
docker-compose exec backend sh
```

## 🛠️ Troubleshooting

### Port Already in Use
```bash
# Check what's using port 8000
netstat -tulpn | grep :8000
```

### Permission Issues
```bash
# Fix audio directory permissions
sudo chown -R $USER:$USER ./backend/public/audio
```

### Reset Database
```bash
# Remove database and restart
rm ./backend/medinote.db
docker-compose restart backend
```

## 📈 Scaling

To run multiple instances:

```bash
# Scale to 3 instances
docker-compose up -d --scale backend=3
```

## 🔄 Updates

```bash
# Pull latest changes
git pull

# Rebuild and restart
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

---

**That's it! Your backend is now running with `docker-compose up -d`** 🚀

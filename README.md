# MediNote - Medical Audio Recording App

A comprehensive medical note-taking application that allows healthcare professionals to record patient consultations with real-time audio streaming, offline capabilities, and seamless patient management.

## 📱 Download

**Android APK**: [Download MediNote v1.0.0](https://github.com/divij2510/MediNote-App/releases/download/beta/MediNote-v1.0.0-arm64.apk)

## 🎥 Demo Video

**Complete Feature Walkthrough**: [Watch Demo Video](https://drive.google.com/file/d/1bLocaZpdS3UVvh4mwmC0i3jsOy5YnJSc/view?usp=drivesdk)

## 🚀 Quick Start

### Prerequisites
- **Flutter**: 3.32.8 (Dart 3.8.1)
- **Docker**: Latest version
- **Node.js**: 18+ (for backend development)

### Backend Setup (Docker)

1. **Clone the repository**
   ```bash
   git clone https://github.com/divij2510/MediNote-App.git
   cd MediNote-App
   ```

2. **Start the backend with Docker**
   ```bash
   cd backend
   docker-compose up
   ```

3. **Verify backend is running**
   ```bash
   curl http://localhost:3000/health
   ```

The backend will be available at:
- **Production**: `https://medinote-app-production.up.railway.app`
- **Local**: `http://localhost:3000`

### Flutter App Setup

1. **Navigate to the app directory**
   ```bash
   cd medinote_app
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the app**
   ```bash
   flutter run
   ```

## 🏗️ Project Structure

```
MediNote-App/
├── backend/                 # Node.js backend
│   ├── server.js           # Main server file
│   ├── package.json        # Dependencies
│   ├── docker-compose.yml  # Docker configuration
│   ├── Dockerfile          # Docker build file
│   └── API_DOCUMENTATION.md # Complete API docs
├── medinote_app/           # Flutter mobile app
│   ├── lib/
│   │   ├── screens/        # UI screens
│   │   ├── services/       # Business logic
│   │   └── models/         # Data models
│   └── pubspec.yaml        # Flutter dependencies
└── README.md              # This file
```

## 🔧 Backend Configuration

### Docker Setup
The backend uses Docker for easy deployment. The `docker-compose.yml` file is located in the `backend/` folder:

```yaml
# backend/docker-compose.yml
version: '3.8'
services:
  backend:
    build: .
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
      - PORT=3000
    volumes:
      - ./public/audio:/app/public/audio
      - ./medinote.db:/app/medinote.db
    restart: unless-stopped
```

### Environment Variables
- `NODE_ENV`: Set to `production` for live deployment
- `PORT`: Default 3000
- Database: SQLite (file-based, no external setup required)

## 📱 Mobile App Features

### Core Functionality
- **Real-time Audio Recording**: High-quality audio capture with amplitude visualization
- **Offline Support**: Record without internet, sync when connected
- **Patient Management**: Add, edit, delete patient records
- **Background Recording**: Continue recording when app is minimized
- **Call Interruption Handling**: Automatic pause/resume during phone calls

### Technical Features
- **WebSocket Streaming**: Real-time audio chunk transmission
- **Persistent Storage**: Local audio chunk storage
- **Health Monitoring**: Automatic backend connectivity checks
- **Session Management**: Track recording sessions per patient

## 🛠️ Development

### Backend Development
```bash
cd backend
npm install
npm start
```

### Flutter Development
```bash
cd medinote_app
flutter pub get
flutter run --debug
```

### Building Release APK
```bash
cd medinote_app
flutter build apk --release --split-per-abi
```

## 📚 API Documentation

Complete API documentation is available in the backend folder:
- **[API Documentation](backend/API_DOCUMENTATION.md)**

### Key Endpoints
- `GET /health` - Health check
- `GET /patients` - List all patients
- `POST /patients` - Create patient
- `DELETE /patients/:id` - Delete patient
- `WebSocket /ws` - Real-time audio streaming

## 🚀 Deployment

### Backend Deployment (Railway)
The backend is deployed on Railway:
- **URL**: `https://medinote-app-production.up.railway.app`
- **Health Check**: `https://medinote-app-production.up.railway.app/health`

### Mobile App Distribution
- **Android**: APK available in GitHub Releases
- **iOS**: Not currently supported (Flutter iOS build requires macOS)

## 🔒 Security & Privacy

- **Local Storage**: Audio files stored locally on device
- **Encrypted Transmission**: WebSocket connections use WSS in production
- **No Cloud Storage**: All data remains on device or your backend
- **Patient Privacy**: No patient data sent to third parties

## 🐛 Troubleshooting

### Common Issues

1. **Backend Connection Failed**
   - Check if backend is running: `curl https://medinote-app-production.up.railway.app/health`
   - Verify internet connection

2. **Audio Recording Issues**
   - Grant microphone permissions
   - Check device audio settings
   - Restart the app

3. **Offline Recording Not Working**
   - Ensure app has storage permissions
   - Check available device storage

### Debug Mode
```bash
flutter run --debug
```

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## 📞 Support

For issues and questions:
- Create an issue on GitHub
- Check the API documentation
- Review the demo video for usage examples

---

**MediNote** - Professional medical audio recording made simple.

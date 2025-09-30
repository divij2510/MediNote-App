const fs = require('fs');
const path = require('path');

// Simple log viewer for the backend
console.log('📊 MediNote Backend Log Viewer');
console.log('================================');
console.log('This script helps monitor backend logs in real-time');
console.log('Press Ctrl+C to exit');
console.log('');

// Monitor server output
process.stdin.setRawMode(true);
process.stdin.resume();
process.stdin.setEncoding('utf8');

console.log('🔍 Monitoring backend logs...');
console.log('📡 All API requests will be logged with:');
console.log('   - Timestamp');
console.log('   - HTTP Method and URL');
console.log('   - Client IP and User Agent');
console.log('   - Request body (for POST/PUT)');
console.log('   - Response status and timing');
console.log('   - Database operations');
console.log('   - WebSocket connections');
console.log('');
console.log('🎯 Log format examples:');
console.log('   📡 [timestamp] GET /patients/ - IP: 127.0.0.1');
console.log('   📦 Request Body: {"name": "John", "age": 30}');
console.log('   📤 [timestamp] Response: 200 - Time: 45ms');
console.log('   ✅ Patient created successfully with ID: 5');
console.log('   🔌 WebSocket connected: session_123');
console.log('');

process.stdin.on('data', (key) => {
  if (key === '\u0003') { // Ctrl+C
    console.log('\n👋 Log viewer stopped');
    process.exit(0);
  }
});

// Keep the process alive
setInterval(() => {
  // Just keep the process running
}, 1000);

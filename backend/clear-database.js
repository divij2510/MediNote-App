const sqlite3 = require('sqlite3').verbose();
const path = require('path');

// Connect to database
const dbPath = path.join(__dirname, 'medinote.db');
const db = new sqlite3.Database(dbPath);

console.log('🗑️  Clearing MediNote database...');

// Clear all tables
db.serialize(() => {
  // Delete all records from tables
  db.run('DELETE FROM audio_sessions', (err) => {
    if (err) {
      console.error('❌ Error clearing audio_sessions:', err.message);
    } else {
      console.log('✅ Cleared audio_sessions table');
    }
  });
  
  db.run('DELETE FROM patients', (err) => {
    if (err) {
      console.error('❌ Error clearing patients:', err.message);
    } else {
      console.log('✅ Cleared patients table');
    }
  });
  
  // Reset auto-increment counters
  db.run('DELETE FROM sqlite_sequence WHERE name="patients"', (err) => {
    if (err && !err.message.includes('no such table')) {
      console.error('❌ Error resetting patients sequence:', err.message);
    } else {
      console.log('✅ Reset patients auto-increment');
    }
  });
  
  db.run('DELETE FROM sqlite_sequence WHERE name="audio_sessions"', (err) => {
    if (err && !err.message.includes('no such table')) {
      console.error('❌ Error resetting audio_sessions sequence:', err.message);
    } else {
      console.log('✅ Reset audio_sessions auto-increment');
    }
  });
  
  // Show final table status
  setTimeout(() => {
    db.all('SELECT COUNT(*) as count FROM patients', (err, rows) => {
      if (err) {
        console.error('❌ Error checking patients count:', err.message);
      } else {
        console.log(`📊 Patients count: ${rows[0].count}`);
      }
    });
    
    db.all('SELECT COUNT(*) as count FROM audio_sessions', (err, rows) => {
      if (err) {
        console.error('❌ Error checking audio_sessions count:', err.message);
      } else {
        console.log(`📊 Audio sessions count: ${rows[0].count}`);
      }
      
      console.log('🎉 Database cleared successfully!');
      console.log('💡 You can now add new patients and test recordings.');
      db.close();
    });
  }, 1000);
});

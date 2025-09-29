from fastapi import WebSocket, WebSocketDisconnect, Depends, HTTPException
from fastapi.routing import APIRouter
from sqlalchemy.orm import Session
from typing import Dict, List
import json
import asyncio
import uuid
from datetime import datetime
import logging

from ..database import get_db
from ..models import Session as DBSession, AudioChunk
from ..auth import get_current_user
from ..supabase_service import supabase_service

router = APIRouter()
logger = logging.getLogger(__name__)

class ConnectionManager:
    def __init__(self):
        self.active_connections: Dict[str, WebSocket] = {}
        self.session_connections: Dict[str, str] = {}  # session_id -> connection_id
        
    async def connect(self, websocket: WebSocket, connection_id: str):
        await websocket.accept()
        self.active_connections[connection_id] = websocket
        logger.info(f"WebSocket connected: {connection_id}")
        
    def disconnect(self, connection_id: str):
        if connection_id in self.active_connections:
            del self.active_connections[connection_id]
        # Remove from session connections
        session_id = None
        for sid, cid in self.session_connections.items():
            if cid == connection_id:
                session_id = sid
                break
        if session_id:
            del self.session_connections[session_id]
        logger.info(f"WebSocket disconnected: {connection_id}")
        
    async def send_personal_message(self, message: str, connection_id: str):
        if connection_id in self.active_connections:
            await self.active_connections[connection_id].send_text(message)
            
    async def send_session_message(self, message: str, session_id: str):
        if session_id in self.session_connections:
            connection_id = self.session_connections[session_id]
            await self.send_personal_message(message, connection_id)
            
    def register_session(self, session_id: str, connection_id: str):
        self.session_connections[session_id] = connection_id
        logger.info(f"Session {session_id} registered with connection {connection_id}")

manager = ConnectionManager()

@router.websocket("/ws/audio-stream")
async def websocket_endpoint(websocket: WebSocket):
    connection_id = str(uuid.uuid4())
    await manager.connect(websocket, connection_id)
    
    # Start keepalive task
    keepalive_task = asyncio.create_task(keepalive_ping(websocket, connection_id))
    
    try:
        while True:
            # Receive message with timeout
            try:
                data = await asyncio.wait_for(websocket.receive(), timeout=30.0)
            except asyncio.TimeoutError:
                # Send ping to keep connection alive
                try:
                    await websocket.send_text(json.dumps({"type": "ping"}))
                except Exception as ping_error:
                    logger.error(f"Failed to send ping: {ping_error}")
                    break
                continue
                
            if data["type"] == "websocket.receive":
                if "text" in data:
                    # Handle text messages (session info, commands)
                    try:
                        message = json.loads(data["text"])
                        await handle_text_message(websocket, connection_id, message)
                    except Exception as text_error:
                        logger.error(f"Error handling text message: {text_error}")
                elif "bytes" in data:
                    # Handle binary data (audio stream)
                    try:
                        audio_data = data["bytes"]
                        await handle_audio_data(websocket, connection_id, audio_data)
                    except Exception as audio_error:
                        logger.error(f"Error handling audio data: {audio_error}")
            elif data["type"] == "websocket.ping":
                # Handle ping
                try:
                    await websocket.pong()
                except Exception as pong_error:
                    logger.error(f"Failed to send pong: {pong_error}")
                    
    except WebSocketDisconnect:
        logger.info(f"WebSocket disconnected: {connection_id}")
        manager.disconnect(connection_id)
    except Exception as e:
        logger.error(f"WebSocket error: {e}")
        manager.disconnect(connection_id)
    finally:
        keepalive_task.cancel()
        try:
            await keepalive_task
        except asyncio.CancelledError:
            pass

async def keepalive_ping(websocket: WebSocket, connection_id: str):
    """Send periodic ping to keep connection alive"""
    try:
        while True:
            await asyncio.sleep(10)  # Send ping every 10 seconds (more frequent)
            try:
                # Check if websocket is still connected
                if websocket.client_state.name == "CONNECTED":
                    # Send ping with timestamp
                    ping_data = {
                        "type": "ping",
                        "timestamp": datetime.now().isoformat(),
                        "connection_id": connection_id
                    }
                    await websocket.send_text(json.dumps(ping_data))
                    logger.debug(f"Sent keepalive ping to {connection_id}")
                else:
                    logger.info(f"WebSocket {connection_id} is no longer connected, stopping keepalive")
                    break
            except Exception as e:
                logger.error(f"Keepalive ping failed: {e}")
                break
    except asyncio.CancelledError:
        logger.debug(f"Keepalive task cancelled for {connection_id}")
        pass

async def handle_text_message(websocket: WebSocket, connection_id: str, message: dict):
    """Handle text messages from client"""
    message_type = message.get("type")
    
    if message_type == "session_start":
        await handle_session_start(websocket, connection_id, message)
    elif message_type == "pause_streaming":
        await handle_pause_streaming(websocket, connection_id, message)
    elif message_type == "resume_streaming":
        await handle_resume_streaming(websocket, connection_id, message)
    elif message_type == "stop_streaming":
        await handle_stop_streaming(websocket, connection_id, message)
    else:
        logger.warning(f"Unknown message type: {message_type}")

async def handle_session_start(websocket: WebSocket, connection_id: str, message: dict):
    """Handle session start message"""
    try:
        session_id = message.get("session_id")
        user_id = message.get("user_id")
        patient_id = message.get("patient_id")
        patient_name = message.get("patient_name")
        
        # Create session in database
        db = next(get_db())
        from datetime import datetime, date
        import uuid as uuid_lib
        
        # Check if session already exists
        existing_session = db.query(DBSession).filter(DBSession.id == session_id).first()
        
        if not existing_session:
            # Create new session
            new_session = DBSession(
                id=session_id,
                user_id=user_id or str(uuid_lib.uuid4()),
                patient_id=patient_id or str(uuid_lib.uuid4()),
                patient_name=patient_name or "Unknown Patient",
                status="recording",
                date=date.today(),
                start_time=datetime.now(),
                last_chunk_number=0,
                total_chunks_expected=None,
                is_resumable=True,
                last_activity=datetime.now(),
                pause_count=0,
                resume_count=0
            )
            
            db.add(new_session)
            db.commit()
            logger.info(f"Created new session {session_id} for patient {patient_name}")
        else:
            logger.info(f"Session {session_id} already exists")
        
        # Register session with connection
        manager.register_session(session_id, connection_id)
        
        # Send confirmation
        await websocket.send_text(json.dumps({
            "type": "session_confirmed",
            "session_id": session_id,
            "status": "ready"
        }))
        
        logger.info(f"Session {session_id} started for patient {patient_name}")
        
    except Exception as e:
        logger.error(f"Error handling session start: {e}")
        await websocket.send_text(json.dumps({
            "type": "error",
            "message": str(e)
        }))

async def handle_pause_streaming(websocket: WebSocket, connection_id: str, message: dict):
    """Handle pause streaming message"""
    try:
        session_id = message.get("session_id")
        
        # Update session status in database
        # This would typically update the session status to paused
        
        await websocket.send_text(json.dumps({
            "type": "streaming_paused",
            "session_id": session_id
        }))
        
        logger.info(f"Streaming paused for session {session_id}")
        
    except Exception as e:
        logger.error(f"Error handling pause streaming: {e}")

async def handle_resume_streaming(websocket: WebSocket, connection_id: str, message: dict):
    """Handle resume streaming message"""
    try:
        session_id = message.get("session_id")
        
        # Update session status in database
        # This would typically update the session status to streaming
        
        await websocket.send_text(json.dumps({
            "type": "streaming_resumed",
            "session_id": session_id
        }))
        
        logger.info(f"Streaming resumed for session {session_id}")
        
    except Exception as e:
        logger.error(f"Error handling resume streaming: {e}")

async def handle_stop_streaming(websocket: WebSocket, connection_id: str, message: dict):
    """Handle stop streaming message"""
    try:
        session_id = message.get("session_id")
        
        # Update session status in database
        db = None
        try:
            db = next(get_db())
            session = db.query(DBSession).filter(DBSession.id == session_id).first()
            
            if session:
                # Update session status to completed
                session.status = "completed"
                session.end_time = datetime.now()
                session.last_activity = datetime.now()
                db.commit()
                logger.info(f"Session {session_id} marked as completed")
            else:
                logger.warning(f"Session {session_id} not found for stop streaming")
                
        except Exception as db_error:
            logger.error(f"Error updating session status: {db_error}")
        finally:
            if db:
                db.close()
        
        # Send confirmation to client
        await websocket.send_text(json.dumps({
            "type": "streaming_stopped",
            "session_id": session_id,
            "status": "completed"
        }))
        
        logger.info(f"Streaming stopped for session {session_id}")
        
    except Exception as e:
        logger.error(f"Error handling stop streaming: {e}")
        await websocket.send_text(json.dumps({
            "type": "error",
            "message": f"Failed to stop streaming: {str(e)}"
        }))

async def handle_audio_data(websocket: WebSocket, connection_id: str, audio_data: bytes):
    """Handle incoming audio data"""
    try:
        # Get session ID for this connection
        session_id = None
        for sid, cid in manager.session_connections.items():
            if cid == connection_id:
                session_id = sid
                break
                
        if not session_id:
            logger.warning("No session found for connection")
            return
            
        # Process audio data
        await process_audio_chunk(session_id, audio_data)
        
        # Send acknowledgment
        await websocket.send_text(json.dumps({
            "type": "audio_received",
            "timestamp": datetime.now().isoformat()
        }))
        
    except Exception as e:
        logger.error(f"Error handling audio data: {e}")

async def process_audio_chunk(session_id: str, audio_data: bytes):
    """Process incoming audio chunk"""
    db = None
    try:
        # Get database session
        db = next(get_db())
        session = db.query(DBSession).filter(DBSession.id == session_id).first()
        
        if not session:
            logger.error(f"Session {session_id} not found - session should have been created during session start")
            return
            
        # Get next chunk number atomically
        next_chunk_number = session.last_chunk_number + 1
        
        # Create audio chunk record
        chunk = AudioChunk(
            id=str(uuid.uuid4()),
            session_id=session_id,
            chunk_number=next_chunk_number,
            gcs_path="",  # Will be set after upload
            mime_type="audio/mp4",
            file_size=len(audio_data)
        )
        
        # Upload to local storage (simple, reliable)
        chunk_path = f"sessions/{session_id}/chunk_{chunk.chunk_number}.mp3"
        
        try:
            upload_result = await supabase_service.upload_audio_chunk(
                chunk_path, 
                audio_data, 
                "audio/mp4"
            )
            
            if upload_result and upload_result.get("success"):
                chunk.gcs_path = chunk_path
                chunk.public_url = upload_result.get("public_url")
                chunk.is_processed = True
                chunk.upload_status = "uploaded"
                
                # Save to database
                db.add(chunk)
                db.commit()
                
                # Update session with atomic chunk number increment
                session.last_chunk_number = next_chunk_number
                session.last_activity = datetime.now()
                db.commit()
                
                logger.info(f"Audio chunk {chunk.chunk_number} saved locally for session {session_id}")
            else:
                error_msg = upload_result.get('error', 'Unknown upload error') if upload_result else 'Upload result is None'
                logger.error(f"Failed to save audio chunk for session {session_id}: {error_msg}")
                
                # Mark as failed
                chunk.upload_status = "failed"
                db.add(chunk)
                db.commit()
                
        except Exception as upload_error:
            logger.error(f"Error saving audio chunk for session {session_id}: {upload_error}")
            
            # Mark as failed
            chunk.upload_status = "failed"
            db.add(chunk)
            db.commit()
            
    except Exception as e:
        logger.error(f"Error processing audio chunk: {e}")
        if db:
            try:
                db.rollback()
            except Exception as rollback_error:
                logger.error(f"Error during rollback: {rollback_error}")
    finally:
        if db:
            try:
                db.close()
            except Exception as close_error:
                logger.error(f"Error closing database session: {close_error}")

@router.get("/ws/health")
async def websocket_health():
    """Health check for WebSocket service"""
    return {
        "status": "healthy",
        "active_connections": len(manager.active_connections),
        "active_sessions": len(manager.session_connections)
    }

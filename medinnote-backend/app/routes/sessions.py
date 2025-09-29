from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import Optional
import uuid
from .. import crud, schemas
from ..database import get_db
from ..config import settings
from ..supabase_service import supabase_service
from ..auth import get_hardcoded_user
import logging
import os

logger = logging.getLogger(__name__)
router = APIRouter()

def convert_session_to_dict(session):
    """Convert SQLAlchemy session model to dict with string UUIDs"""
    if not session:
        return None
    return {
        "id": str(session.id),
        "user_id": str(session.user_id),
        "patient_id": str(session.patient_id),
        "patient_name": session.patient_name,
        "session_title": session.session_title,
        "session_summary": session.session_summary,
        "transcript": session.transcript,
        "transcript_status": session.transcript_status,
        "status": session.status,
        "date": session.date,
        "start_time": session.start_time,
        "end_time": session.end_time,
        "duration": session.duration,
        "template_id": str(session.template_id) if session.template_id else None
    }

def convert_session_with_patient_to_dict(session, patient):
    """Convert session with patient details to dict"""
    base_dict = convert_session_to_dict(session)
    if base_dict and patient:
        base_dict.update({
            "pronouns": patient.pronouns,
            "email": patient.email,
            "background": patient.background,
            "medical_history": patient.medical_history,
            "family_history": patient.family_history,
            "social_history": patient.social_history,
            "previous_treatment": patient.previous_treatment,
            "patient_pronouns": patient.pronouns,
            "clinical_notes": []
        })
    return base_dict

@router.post("/v1/upload-session")
async def start_recording_session(
    session: schemas.SessionCreate,
    db: Session = Depends(get_db),
    current_user = Depends(get_hardcoded_user)
):
    """Initialize a new recording session"""
    # Use hardcoded user for MVP
    session.userId = str(current_user.id)
    
    # Verify patient exists
    patient = crud.get_patient_by_id(db, patient_id=session.patientId)
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    
    # Create session
    db_session = crud.create_session(db, session)
    if not db_session:
        raise HTTPException(status_code=400, detail="Failed to create session")
    
    return {"id": str(db_session.id)}

@router.post("/v1/get-presigned-url", response_model=schemas.ChunkUploadResponse)
async def get_presigned_url(
    request: schemas.ChunkUploadRequest,
    db: Session = Depends(get_db)
):
    """Generate presigned URL for audio chunk upload"""
    # Verify session exists
    session = crud.get_session_by_id(db, session_id=request.sessionId)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    
    # Generate file path
    file_extension = "wav" if "wav" in request.mimeType else "mp3"
    file_path = f"sessions/{request.sessionId}/chunk_{request.chunkNumber}.{file_extension}"
    
    # Use Supabase for presigned URL generation
    result = supabase_service.generate_presigned_url(
        file_path=file_path,
        bucket_name="recording_app",
        expires_in=3600
    )
    
    if result["success"]:
        return schemas.ChunkUploadResponse(
            url=result["presigned_url"],
            gcsPath=result["path"],
            publicUrl=result.get("public_url")
        )
    else:
        raise HTTPException(status_code=500, detail="Failed to generate upload URL")

@router.post("/v1/notify-chunk-uploaded")
async def notify_chunk_uploaded(
    notification: schemas.ChunkNotification,
    db: Session = Depends(get_db)
):
    """Handle chunk upload notification and trigger processing"""
    # Verify session exists
    session = crud.get_session_by_id(db, session_id=notification.sessionId)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    
    # Update session with chunk information
    crud.update_session_status(
        db=db,
        session_id=notification.sessionId,
        status='recording',  # Keep status as recording while chunks are being uploaded
        last_chunk_number=notification.chunkNumber,
        total_chunks_expected=notification.totalChunksClient if notification.isLast else None
    )
    
    # Store chunk information in database
    crud.create_audio_chunk(
        db=db,
        session_id=notification.sessionId,
        chunk_number=notification.chunkNumber,
        gcs_path=notification.gcsPath,
        mime_type=notification.mimeType,
        public_url=notification.publicUrl
    )
    
    # If this is the last chunk, update session status
    if notification.isLast:
        crud.update_session_status(
            db=db,
            session_id=notification.sessionId,
            status="processing",
            transcript_status="processing"
        )
        
        logger.info(f"Processing complete session {notification.sessionId} with {notification.totalChunksClient} chunks")
    
    return {"success": True}

@router.get("/v1/fetch-session-by-patient/{patient_id}", response_model=schemas.SessionsResponse)
async def get_sessions_by_patient(
    patient_id: str,
    db: Session = Depends(get_db)
):
    """Get all sessions for a specific patient"""
    # Verify patient exists
    patient = crud.get_patient_by_id(db, patient_id=patient_id)
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    
    sessions = crud.get_sessions_by_patient_id(db, patient_id=patient_id)
    sessions_dict = [convert_session_to_dict(s) for s in sessions]
    
    return schemas.SessionsResponse(sessions=sessions_dict)

@router.get("/v1/all-session", response_model=schemas.AllSessionsResponse)
async def get_all_sessions(
    userId: str = Query(..., description="User ID"),
    db: Session = Depends(get_db),
    current_user = Depends(get_hardcoded_user)
):
    """Get all sessions for a user with patient details"""
    # Use hardcoded user for MVP
    user_id = str(current_user.id)
    
    # Get all sessions for the user
    sessions = crud.get_all_sessions_by_user_id(db, user_id=user_id)
    
    # Build patient map and enrich session data
    patient_map = {}
    enriched_sessions = []
    
    for session in sessions:
        # Get patient details
        patient = crud.get_patient_by_id(db, patient_id=str(session.patient_id))
        
        if patient:
            # Add to patient map
            patient_map[str(patient.id)] = {
                "name": patient.name,
                "pronouns": patient.pronouns
            }
            
            # Convert session with patient details
            session_dict = convert_session_with_patient_to_dict(session, patient)
            enriched_sessions.append(session_dict)
    
    return schemas.AllSessionsResponse(
        sessions=enriched_sessions,
        patientMap=patient_map
    )

# Enhanced session management endpoints
@router.post("/v1/session/resume", response_model=schemas.SessionResumeResponse)
async def resume_session(
    request: schemas.SessionResumeRequest,
    db: Session = Depends(get_db)
):
    """Resume a paused or interrupted recording session"""
    # Verify session exists and belongs to user
    session = crud.get_session_by_id(db, session_id=request.sessionId)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    
    if str(session.user_id) != request.userId:
        raise HTTPException(status_code=403, detail="Session does not belong to user")
    
    # Get session progress
    progress = crud.get_session_progress(db, request.sessionId)
    if not progress:
        raise HTTPException(status_code=500, detail="Failed to get session progress")
    
    # Resume session if it was paused
    if session.status == "paused":
        crud.resume_session(db, request.sessionId)
    
    return schemas.SessionResumeResponse(
        sessionId=str(session.id),
        status=session.status,
        lastChunkNumber=session.last_chunk_number,
        totalChunksExpected=session.total_chunks_expected,
        isResumable=session.is_resumable,
        missingChunks=progress["missing_chunks"],
        sessionInfo={
            "patientName": session.patient_name,
            "startTime": session.start_time,
            "pauseCount": session.pause_count,
            "resumeCount": session.resume_count
        }
    )

@router.post("/v1/session/pause")
async def pause_session(
    request: schemas.SessionPauseRequest,
    db: Session = Depends(get_db)
):
    """Pause a recording session"""
    session = crud.get_session_by_id(db, session_id=request.sessionId)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    
    if session.status != "recording":
        raise HTTPException(status_code=400, detail="Session is not currently recording")
    
    crud.pause_session(db, request.sessionId, request.reason)
    return {"success": True, "status": "paused"}

@router.get("/v1/session/{session_id}/progress", response_model=schemas.SessionProgressResponse)
async def get_session_progress(
    session_id: str,
    db: Session = Depends(get_db)
):
    """Get session upload progress and status"""
    session = crud.get_session_by_id(db, session_id=session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    
    progress = crud.get_session_progress(db, session_id)
    if not progress:
        raise HTTPException(status_code=500, detail="Failed to get session progress")
    
    return schemas.SessionProgressResponse(
        sessionId=str(session.id),
        status=session.status,
        chunksUploaded=progress["chunks_uploaded"],
        totalChunksExpected=progress["total_expected"],
        progressPercentage=progress["progress_percentage"],
        lastChunkNumber=progress["last_chunk"],
        missingChunks=progress["missing_chunks"],
        isComplete=session.status == "processing",
        canResume=session.is_resumable and session.status in ["paused", "recording"]
    )

@router.post("/v1/session/{session_id}/retry-chunk")
async def retry_chunk_upload(
    session_id: str,
    request: schemas.ChunkRetryRequest,
    db: Session = Depends(get_db)
):
    """Retry uploading a failed chunk"""
    session = crud.get_session_by_id(db, session_id=session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    
    # Update chunk status to retrying
    crud.update_chunk_status(
        db=db,
        session_id=session_id,
        chunk_number=request.chunkNumber,
        status="retrying",
        retry_count=1  # This should be incremented from current value
    )
    
    return {"success": True, "chunkNumber": request.chunkNumber, "status": "retrying"}

@router.get("/v1/session/{session_id}/failed-chunks")
async def get_failed_chunks(
    session_id: str,
    db: Session = Depends(get_db)
):
    """Get list of chunks that failed to upload"""
    session = crud.get_session_by_id(db, session_id=session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    
    failed_chunks = crud.get_failed_chunks(db, session_id)
    
    return {
        "sessionId": session_id,
        "failedChunks": [
            {
                "chunkNumber": chunk.chunk_number,
                "status": chunk.upload_status,
                "retryCount": chunk.retry_count,
                "lastAttempt": chunk.created_at
            }
            for chunk in failed_chunks
        ]
    }

@router.put("/v1/session/{session_id}/status")
async def update_session_status(
    session_id: str,
    status_update: schemas.SessionStatusUpdate,
    db: Session = Depends(get_db),
    current_user = Depends(get_hardcoded_user)
):
    """Update session status"""
    session = crud.get_session_by_id(db, session_id=session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    
    update_data = {"status": status_update.status}
    if status_update.lastChunkNumber is not None:
        update_data["last_chunk_number"] = status_update.lastChunkNumber
    if status_update.totalChunksExpected is not None:
        update_data["total_chunks_expected"] = status_update.totalChunksExpected
    
    crud.update_session_status(db, session_id, **update_data)
    return {"success": True, "status": status_update.status}

# Add a simple PATCH endpoint for session status updates (used by Flutter app)
@router.patch("/v1/session/{session_id}")
async def patch_session_status(
    session_id: str,
    request: dict,
    db: Session = Depends(get_db),
    current_user = Depends(get_hardcoded_user)
):
    """Update session status - simple endpoint for Flutter app"""
    session = crud.get_session_by_id(db, session_id=session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    
    # Extract data from request body
    status = request.get("status", session.status)
    total_chunks = request.get("totalChunks", session.total_chunks_expected)
    end_time = request.get("endTime", session.end_time)
    duration = request.get("duration", None)
    
    update_data = {
        "status": status,
        "total_chunks_expected": total_chunks,
        "end_time": end_time
    }
    
    # Add duration if provided
    if duration is not None:
        update_data["duration"] = duration
    
    crud.update_session_status(db, session_id, **update_data)
    return {"success": True, "status": status}

@router.get("/v1/session/{session_id}/audio/stream")
async def get_audio_stream_url(
    session_id: str,
    db: Session = Depends(get_db),
    current_user = Depends(get_hardcoded_user)
):
    """Get audio stream URL for a session"""
    try:
        # Get session from database
        session = crud.get_session_by_id(db, session_id=session_id)
        if not session:
            raise HTTPException(status_code=404, detail="Session not found")
        
        # Check if session belongs to user
        if str(session.user_id) != str(current_user.id):
            raise HTTPException(status_code=403, detail="Access denied")
        
        # For now, return a placeholder URL
        # In production, this would generate a presigned URL or streaming URL
        stream_url = f"https://medinote-app-backend-api.onrender.com/v1/session/{session_id}/audio/play"
        
        return {"stream_url": stream_url}
        
    except Exception as e:
        logger.error(f"Error getting audio stream URL: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@router.get("/v1/session/{session_id}/audio/play")
async def stream_audio(
    session_id: str,
    db: Session = Depends(get_db),
    current_user = Depends(get_hardcoded_user)
):
    """Stream audio for a session"""
    try:
        # Get session from database
        session = crud.get_session_by_id(db, session_id=session_id)
        if not session:
            raise HTTPException(status_code=404, detail="Session not found")
        
        # Check if session belongs to user
        if str(session.user_id) != str(current_user.id):
            raise HTTPException(status_code=403, detail="Access denied")
        
        # Get audio chunks for this session
        audio_chunks = crud.get_audio_chunks_by_session(db, session_id=session_id)
        
        if not audio_chunks:
            raise HTTPException(status_code=404, detail="No audio chunks found for this session")
        
        # For now, return the first chunk's URL as a simple solution
        # In production, you'd want to merge chunks or create a playlist
        first_chunk = audio_chunks[0]
        if first_chunk.public_url:
            return {"audio_url": first_chunk.public_url}
        else:
            raise HTTPException(status_code=404, detail="Audio file not available")
        
    except Exception as e:
        logger.error(f"Error streaming audio: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

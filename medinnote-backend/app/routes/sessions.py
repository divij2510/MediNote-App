from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import Optional
import uuid
from .. import crud, schemas
from ..database import get_db
from ..config import settings
from ..supabase_service import supabase_service
import logging

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
    db: Session = Depends(get_db)
):
    """Initialize a new recording session"""
    # Verify user and patient exist
    user = crud.get_user_by_id(db, user_id=session.userId)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
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
    bucket_name = "medinnote-audio"
    result = supabase_service.generate_presigned_url(
        bucket_name=bucket_name,
        file_path=file_path,
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
        crud.update_session(
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
    db: Session = Depends(get_db)
):
    """Get all sessions for a user with patient details"""
    # Verify user exists
    user = crud.get_user_by_id(db, user_id=userId)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    # Get all sessions for the user
    sessions = crud.get_all_sessions_by_user_id(db, user_id=userId)
    
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

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List
from .. import crud
from ..database import get_db
from ..supabase_service import supabase_service
from ..auth import get_hardcoded_user

router = APIRouter()

@router.get("/v1/session/{session_id}/audio")
async def get_session_audio(
    session_id: str,
    db: Session = Depends(get_db),
    current_user = Depends(get_hardcoded_user)
):
    """Get all audio chunks for a session for playback"""
    # Verify session exists
    session = crud.get_session_by_id(db, session_id=session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    
    # Get audio chunks from database
    chunks = crud.get_chunks_by_session_id(db, session_id=session_id)
    
    # Get additional info from storage if available
    storage_chunks = supabase_service.get_session_audio_chunks(session_id)
    
    # Combine database and storage info
    result_chunks = []
    for db_chunk in chunks:
        chunk_info = {
            "id": str(db_chunk.id),
            "session_id": str(db_chunk.session_id),
            "chunk_number": db_chunk.chunk_number,
            "gcs_path": db_chunk.gcs_path,
            "public_url": db_chunk.public_url,
            "mime_type": db_chunk.mime_type,
            "is_processed": db_chunk.is_processed,
            "created_at": db_chunk.created_at
        }
        
        # Add storage info if available
        storage_info = next((s for s in storage_chunks if s['chunk_number'] == db_chunk.chunk_number), None)
        if storage_info:
            chunk_info.update({
                "file_size": storage_info.get('size', 0),
                "storage_url": storage_info.get('public_url')
            })
        
        result_chunks.append(chunk_info)
    
    return {
        "session_id": str(session.id),
        "patient_name": session.patient_name,
        "total_chunks": len(result_chunks),
        "chunks": result_chunks,
        "session_info": {
            "start_time": session.start_time,
            "end_time": session.end_time,
            "duration": session.duration,
            "status": session.status
        }
    }

@router.get("/v1/session/{session_id}/audio/stream")
async def stream_session_audio(
    session_id: str,
    db: Session = Depends(get_db),
    current_user = Depends(get_hardcoded_user)
):
    """Get streaming URLs for all chunks in order"""
    session = crud.get_session_by_id(db, session_id=session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    
    chunks = crud.get_chunks_by_session_id(db, session_id=session_id)
    
    streaming_urls = []
    for chunk in sorted(chunks, key=lambda x: x.chunk_number):
        if chunk.public_url:
            streaming_urls.append({
                "chunk_number": chunk.chunk_number,
                "url": chunk.public_url,
                "mime_type": chunk.mime_type
            })
    
    return {
        "session_id": str(session.id),
        "streaming_urls": streaming_urls,
        "playback_info": {
            "total_chunks": len(streaming_urls),
            "suggested_playback": "sequential"
        }
    }

# Enhanced audio playback endpoints
@router.get("/v1/session/{session_id}/audio/playlist")
async def get_audio_playlist(
    session_id: str,
    format: str = "m3u8",  # m3u8, json
    db: Session = Depends(get_db)
):
    """Get audio playlist for session playback"""
    session = crud.get_session_by_id(db, session_id=session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    
    chunks = crud.get_chunks_by_session_id(db, session_id=session_id)
    sorted_chunks = sorted(chunks, key=lambda x: x.chunk_number)
    
    if format == "m3u8":
        # Generate M3U8 playlist
        playlist = "#EXTM3U\n#EXT-X-VERSION:3\n"
        for chunk in sorted_chunks:
            if chunk.public_url:
                playlist += f"#EXTINF:10.0,\n{chunk.public_url}\n"
        playlist += "#EXT-X-ENDLIST\n"
        
        return {
            "content_type": "application/vnd.apple.mpegurl",
            "playlist": playlist
        }
    else:
        # JSON format
        return {
            "session_id": str(session.id),
            "patient_name": session.patient_name,
            "total_duration": session.duration,
            "chunks": [
                {
                    "chunk_number": chunk.chunk_number,
                    "url": chunk.public_url,
                    "mime_type": chunk.mime_type,
                    "file_size": chunk.file_size,
                    "duration_estimate": 10.0  # Default 10 seconds per chunk
                }
                for chunk in sorted_chunks
                if chunk.public_url
            ]
        }

@router.get("/v1/session/{session_id}/audio/chunk/{chunk_number}")
async def get_audio_chunk(
    session_id: str,
    chunk_number: int,
    db: Session = Depends(get_db)
):
    """Get specific audio chunk for playback"""
    session = crud.get_session_by_id(db, session_id=session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    
    chunks = crud.get_chunks_by_session_id(db, session_id=session_id)
    chunk = next((c for c in chunks if c.chunk_number == chunk_number), None)
    
    if not chunk:
        raise HTTPException(status_code=404, detail="Chunk not found")
    
    if not chunk.public_url:
        raise HTTPException(status_code=404, detail="Chunk not available for playback")
    
    return {
        "chunk_number": chunk.chunk_number,
        "url": chunk.public_url,
        "mime_type": chunk.mime_type,
        "file_size": chunk.file_size,
        "is_processed": chunk.is_processed,
        "upload_status": chunk.upload_status
    }

@router.get("/v1/session/{session_id}/audio/summary")
async def get_audio_summary(
    session_id: str,
    db: Session = Depends(get_db)
):
    """Get audio session summary for playback"""
    session = crud.get_session_by_id(db, session_id=session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    
    chunks = crud.get_chunks_by_session_id(db, session_id=session_id)
    uploaded_chunks = [c for c in chunks if c.upload_status == "uploaded"]
    failed_chunks = [c for c in chunks if c.upload_status in ["failed", "retrying"]]
    
    return {
        "session_id": str(session.id),
        "patient_name": session.patient_name,
        "session_title": session.session_title,
        "start_time": session.start_time,
        "end_time": session.end_time,
        "duration": session.duration,
        "status": session.status,
        "audio_summary": {
            "total_chunks": len(chunks),
            "uploaded_chunks": len(uploaded_chunks),
            "failed_chunks": len(failed_chunks),
            "completion_percentage": (len(uploaded_chunks) / len(chunks) * 100) if chunks else 0,
            "is_playable": len(uploaded_chunks) > 0,
            "missing_chunks": [c.chunk_number for c in failed_chunks]
        },
        "transcript_info": {
            "status": session.transcript_status,
            "transcript": session.transcript,
            "summary": session.session_summary
        }
    }
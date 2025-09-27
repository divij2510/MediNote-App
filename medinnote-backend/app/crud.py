from sqlalchemy.orm import Session
from sqlalchemy import and_
from typing import List, Optional
from . import models, schemas
from datetime import datetime
import uuid

def convert_to_uuid(value: str) -> uuid.UUID:
    """Convert string to UUID, handling various formats"""
    if isinstance(value, uuid.UUID):
        return value
    return uuid.UUID(value)

# User CRUD operations
def get_user_by_email(db: Session, email: str):
    return db.query(models.User).filter(models.User.email == email).first()

def create_user(db: Session, user: schemas.UserCreate):
    db_user = models.User(email=user.email)
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    return db_user

def get_user_by_id(db: Session, user_id: str):
    try:
        uuid_id = convert_to_uuid(user_id)
        return db.query(models.User).filter(models.User.id == uuid_id).first()
    except ValueError:
        return None

# Patient CRUD operations
def get_patients_by_user_id(db: Session, user_id: str):
    try:
        uuid_id = convert_to_uuid(user_id)
        return db.query(models.Patient).filter(models.Patient.user_id == uuid_id).all()
    except ValueError:
        return []

def create_patient(db: Session, patient: schemas.PatientCreate):
    try:
        user_uuid = convert_to_uuid(patient.userId)
        db_patient = models.Patient(
            name=patient.name,
            user_id=user_uuid,
            pronouns=patient.pronouns,
            email=patient.email,
            background=patient.background,
            medical_history=patient.medical_history,
            family_history=patient.family_history,
            social_history=patient.social_history,
            previous_treatment=patient.previous_treatment
        )
        db.add(db_patient)
        db.commit()
        db.refresh(db_patient)
        return db_patient
    except ValueError:
        return None

def get_patient_by_id(db: Session, patient_id: str):
    try:
        uuid_id = convert_to_uuid(patient_id)
        return db.query(models.Patient).filter(models.Patient.id == uuid_id).first()
    except ValueError:
        return None

# Session CRUD operations
def create_session(db: Session, session: schemas.SessionCreate):
    try:
        user_uuid = convert_to_uuid(session.userId)
        patient_uuid = convert_to_uuid(session.patientId)
        template_uuid = convert_to_uuid(session.templateId) if session.templateId else None
        
        db_session = models.Session(
            user_id=user_uuid,
            patient_id=patient_uuid,
            patient_name=session.patientName,
            status=session.status,
            start_time=session.startTime,
            template_id=template_uuid
        )
        db.add(db_session)
        db.commit()
        db.refresh(db_session)
        return db_session
    except ValueError:
        return None

def get_sessions_by_patient_id(db: Session, patient_id: str):
    try:
        uuid_id = convert_to_uuid(patient_id)
        return db.query(models.Session).filter(models.Session.patient_id == uuid_id).all()
    except ValueError:
        return []

def get_all_sessions_by_user_id(db: Session, user_id: str):
    try:
        uuid_id = convert_to_uuid(user_id)
        return db.query(models.Session).filter(models.Session.user_id == uuid_id).all()
    except ValueError:
        return []

def get_session_by_id(db: Session, session_id: str):
    try:
        uuid_id = convert_to_uuid(session_id)
        return db.query(models.Session).filter(models.Session.id == uuid_id).first()
    except ValueError:
        return None

def update_session(db: Session, session_id: str, **kwargs):
    try:
        uuid_id = convert_to_uuid(session_id)
        db.query(models.Session).filter(models.Session.id == uuid_id).update(kwargs)
        db.commit()
        return get_session_by_id(db, session_id)
    except ValueError:
        return None

# Template CRUD operations
def get_templates_by_user_id(db: Session, user_id: str):
    try:
        uuid_id = convert_to_uuid(user_id)
        return db.query(models.Template).filter(
            (models.Template.user_id == uuid_id) | (models.Template.user_id.is_(None))
        ).all()
    except ValueError:
        # Return only system templates if user_id is invalid
        return db.query(models.Template).filter(models.Template.user_id.is_(None)).all()

def create_template(db: Session, template: schemas.TemplateCreate):
    try:
        user_uuid = convert_to_uuid(template.user_id) if template.user_id else None
        db_template = models.Template(
            title=template.title,
            type=template.type,
            user_id=user_uuid
        )
        db.add(db_template)
        db.commit()
        db.refresh(db_template)
        return db_template
    except ValueError:
        return None

def get_template_by_id(db: Session, template_id: str):
    try:
        uuid_id = convert_to_uuid(template_id)
        return db.query(models.Template).filter(models.Template.id == uuid_id).first()
    except ValueError:
        return None

# Audio chunk CRUD operations
def create_audio_chunk(
    db: Session, 
    session_id: str, 
    chunk_number: int, 
    gcs_path: str, 
    mime_type: str,
    public_url: Optional[str] = None
):
    try:
        session_uuid = convert_to_uuid(session_id)
        db_chunk = models.AudioChunk(
            session_id=session_uuid,
            chunk_number=chunk_number,
            gcs_path=gcs_path,
            public_url=public_url,
            mime_type=mime_type
        )
        db.add(db_chunk)
        db.commit()
        db.refresh(db_chunk)
        return db_chunk
    except ValueError:
        return None

def get_chunks_by_session_id(db: Session, session_id: str):
    try:
        uuid_id = convert_to_uuid(session_id)
        return db.query(models.AudioChunk).filter(
            models.AudioChunk.session_id == uuid_id
        ).order_by(models.AudioChunk.chunk_number).all()
    except ValueError:
        return []

def mark_chunk_processed(db: Session, chunk_id: str):
    try:
        uuid_id = convert_to_uuid(chunk_id)
        db.query(models.AudioChunk).filter(models.AudioChunk.id == uuid_id).update(
            {"is_processed": True}
        )
        db.commit()
    except ValueError:
        pass

from sqlalchemy.orm import Session
from sqlalchemy import and_
from typing import List, Optional
from . import models, schemas
from datetime import datetime

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
    return db.query(models.User).filter(models.User.id == user_id).first()

# Patient CRUD operations
def get_patients_by_user_id(db: Session, user_id: str):
    return db.query(models.Patient).filter(models.Patient.user_id == user_id).all()

def create_patient(db: Session, patient: schemas.PatientCreate):
    db_patient = models.Patient(
        name=patient.name,
        user_id=patient.userId,
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

def get_patient_by_id(db: Session, patient_id: str):
    return db.query(models.Patient).filter(models.Patient.id == patient_id).first()

# Session CRUD operations
def create_session(db: Session, session: schemas.SessionCreate):
    db_session = models.Session(
        user_id=session.userId,
        patient_id=session.patientId,
        patient_name=session.patientName,
        status=session.status,
        start_time=session.startTime,
        template_id=session.templateId
    )
    db.add(db_session)
    db.commit()
    db.refresh(db_session)
    return db_session

def get_sessions_by_patient_id(db: Session, patient_id: str):
    return db.query(models.Session).filter(models.Session.patient_id == patient_id).all()

def get_all_sessions_by_user_id(db: Session, user_id: str):
    return db.query(models.Session).filter(models.Session.user_id == user_id).all()

def get_session_by_id(db: Session, session_id: str):
    return db.query(models.Session).filter(models.Session.id == session_id).first()

def update_session(db: Session, session_id: str, **kwargs):
    db.query(models.Session).filter(models.Session.id == session_id).update(kwargs)
    db.commit()
    return get_session_by_id(db, session_id)

# Template CRUD operations
def get_templates_by_user_id(db: Session, user_id: str):
    return db.query(models.Template).filter(
        (models.Template.user_id == user_id) | (models.Template.user_id.is_(None))
    ).all()

def create_template(db: Session, template: schemas.TemplateCreate):
    db_template = models.Template(
        title=template.title,
        type=template.type,
        user_id=template.user_id
    )
    db.add(db_template)
    db.commit()
    db.refresh(db_template)
    return db_template

def get_template_by_id(db: Session, template_id: str):
    return db.query(models.Template).filter(models.Template.id == template_id).first()

# Audio chunk CRUD operations
def create_audio_chunk(
    db: Session, 
    session_id: str, 
    chunk_number: int, 
    gcs_path: str, 
    mime_type: str,
    public_url: Optional[str] = None
):
    db_chunk = models.AudioChunk(
        session_id=session_id,
        chunk_number=chunk_number,
        gcs_path=gcs_path,
        public_url=public_url,
        mime_type=mime_type
    )
    db.add(db_chunk)
    db.commit()
    db.refresh(db_chunk)
    return db_chunk

def get_chunks_by_session_id(db: Session, session_id: str):
    return db.query(models.AudioChunk).filter(
        models.AudioChunk.session_id == session_id
    ).order_by(models.AudioChunk.chunk_number).all()

def mark_chunk_processed(db: Session, chunk_id: str):
    db.query(models.AudioChunk).filter(models.AudioChunk.id == chunk_id).update(
        {"is_processed": True}
    )
    db.commit()

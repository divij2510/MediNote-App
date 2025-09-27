from sqlalchemy import Column, String, Text, Boolean, Integer, DateTime, Date, ForeignKey
from sqlalchemy.orm import relationship
from sqlalchemy.ext.declarative import declarative_base
from datetime import datetime, date
import uuid

Base = declarative_base()

class User(Base):
    __tablename__ = "users"
    
    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    email = Column(String, unique=True, index=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    
    # Relationships
    patients = relationship("Patient", back_populates="user")
    sessions = relationship("Session", back_populates="user")
    templates = relationship("Template", back_populates="user")

class Patient(Base):
    __tablename__ = "patients"
    
    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    name = Column(String, nullable=False)
    user_id = Column(String, ForeignKey("users.id"), nullable=False)
    pronouns = Column(String, nullable=True)
    email = Column(String, nullable=True)
    background = Column(Text, nullable=True)
    medical_history = Column(Text, nullable=True)
    family_history = Column(Text, nullable=True)
    social_history = Column(Text, nullable=True)
    previous_treatment = Column(Text, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    
    # Relationships
    user = relationship("User", back_populates="patients")
    sessions = relationship("Session", back_populates="patient")

class Template(Base):
    __tablename__ = "templates"
    
    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    title = Column(String, nullable=False)
    type = Column(String, default="custom")
    user_id = Column(String, ForeignKey("users.id"), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    
    # Relationships
    user = relationship("User", back_populates="templates")
    sessions = relationship("Session", back_populates="template")

class Session(Base):
    __tablename__ = "sessions"
    
    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String, ForeignKey("users.id"), nullable=False)
    patient_id = Column(String, ForeignKey("patients.id"), nullable=False)
    patient_name = Column(String, nullable=False)
    session_title = Column(String, nullable=True)
    session_summary = Column(Text, nullable=True)
    transcript = Column(Text, nullable=True)
    transcript_status = Column(String, default="pending")
    status = Column(String, default="recording")
    date = Column(Date, default=date.today)
    start_time = Column(DateTime, default=datetime.utcnow)
    end_time = Column(DateTime, nullable=True)
    duration = Column(String, nullable=True)
    template_id = Column(String, ForeignKey("templates.id"), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    
    # Relationships
    user = relationship("User", back_populates="sessions")
    patient = relationship("Patient", back_populates="sessions")
    template = relationship("Template", back_populates="sessions")
    audio_chunks = relationship("AudioChunk", back_populates="session")

class AudioChunk(Base):
    __tablename__ = "audio_chunks"
    
    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    session_id = Column(String, ForeignKey("sessions.id"), nullable=False)
    chunk_number = Column(Integer, nullable=False)
    gcs_path = Column(String, nullable=False)
    public_url = Column(String, nullable=True)
    mime_type = Column(String, nullable=False)
    is_processed = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    
    # Relationships
    session = relationship("Session", back_populates="audio_chunks")

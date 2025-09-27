from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime, date
import uuid

# User schemas
class UserBase(BaseModel):
    email: str

class UserCreate(UserBase):
    pass

class User(UserBase):
    id: str = Field(..., description="UUID as string")
    created_at: datetime
    
    class Config:
        from_attributes = True

# Patient schemas
class PatientBase(BaseModel):
    name: str
    pronouns: Optional[str] = None
    email: Optional[str] = None
    background: Optional[str] = None
    medical_history: Optional[str] = None
    family_history: Optional[str] = None
    social_history: Optional[str] = None
    previous_treatment: Optional[str] = None

class PatientCreate(PatientBase):
    userId: str = Field(..., description="User UUID as string")

class PatientResponse(PatientBase):
    id: str = Field(..., description="UUID as string")
    user_id: str = Field(..., description="User UUID as string")
    created_at: datetime
    
    class Config:
        from_attributes = True

class Patient(PatientResponse):
    pass

# Template schemas
class TemplateBase(BaseModel):
    title: str
    type: str = "custom"

class TemplateCreate(TemplateBase):
    user_id: Optional[str] = Field(None, description="User UUID as string")

class Template(TemplateBase):
    id: str = Field(..., description="UUID as string")
    user_id: Optional[str] = Field(None, description="User UUID as string")
    created_at: datetime
    
    class Config:
        from_attributes = True

# Session schemas
class SessionCreate(BaseModel):
    patientId: str = Field(..., description="Patient UUID as string")
    userId: str = Field(..., description="User UUID as string")
    patientName: str
    status: str = "recording"
    startTime: datetime
    templateId: Optional[str] = Field(None, description="Template UUID as string")

class SessionResponse(BaseModel):
    id: str = Field(..., description="UUID as string")
    user_id: str = Field(..., description="User UUID as string")
    patient_id: str = Field(..., description="Patient UUID as string")
    patient_name: str
    session_title: Optional[str]
    session_summary: Optional[str]
    transcript: Optional[str]
    transcript_status: str
    status: str
    date: date
    start_time: datetime
    end_time: Optional[datetime]
    duration: Optional[str]
    template_id: Optional[str] = Field(None, description="Template UUID as string")
    
    class Config:
        from_attributes = True

class SessionWithPatientDetails(SessionResponse):
    pronouns: Optional[str] = None
    email: Optional[str] = None
    background: Optional[str] = None
    medical_history: Optional[str] = None
    family_history: Optional[str] = None
    social_history: Optional[str] = None
    previous_treatment: Optional[str] = None
    patient_pronouns: Optional[str] = None
    clinical_notes: List = []

# Audio chunk schemas
class ChunkUploadRequest(BaseModel):
    sessionId: str = Field(..., description="Session UUID as string")
    chunkNumber: int
    mimeType: str

class ChunkUploadResponse(BaseModel):
    url: str
    gcsPath: str
    publicUrl: Optional[str] = None

class ChunkNotification(BaseModel):
    sessionId: str = Field(..., description="Session UUID as string")
    gcsPath: str
    chunkNumber: int
    isLast: bool
    totalChunksClient: int
    publicUrl: Optional[str] = None
    mimeType: str
    selectedTemplate: Optional[str] = None
    selectedTemplateId: Optional[str] = None
    model: str = "fast"

# Response schemas
class PatientsResponse(BaseModel):
    patients: List[Patient]

class SessionsResponse(BaseModel):
    sessions: List[SessionResponse]

class AllSessionsResponse(BaseModel):
    sessions: List[SessionWithPatientDetails]
    patientMap: dict

class TemplatesResponse(BaseModel):
    success: bool
    data: List[Template]

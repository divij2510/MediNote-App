from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List
from .. import crud, schemas
from ..database import get_db

router = APIRouter()

@router.get("/v1/patients", response_model=schemas.PatientsResponse)
async def get_patients(
    userId: str = Query(..., description="User ID"),
    db: Session = Depends(get_db)
):
    """Get all patients for a user"""
    # Verify user exists
    user = crud.get_user_by_id(db, user_id=userId)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    patients = crud.get_patients_by_user_id(db, user_id=userId)
    return schemas.PatientsResponse(patients=patients)

@router.post("/v1/add-patient-ext")
async def create_patient(
    patient: schemas.PatientCreate,
    db: Session = Depends(get_db)
):
    """Create a new patient"""
    # Verify user exists
    user = crud.get_user_by_id(db, user_id=patient.userId)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    db_patient = crud.create_patient(db, patient)
    
    # Return in the expected format
    return {
        "patient": {
            "id": db_patient.id,
            "name": db_patient.name,
            "user_id": db_patient.user_id,
            "pronouns": db_patient.pronouns
        }
    }

@router.get("/v1/patient-details/{patient_id}")
async def get_patient_details(
    patient_id: str,
    db: Session = Depends(get_db)
):
    """Get detailed patient information"""
    patient = crud.get_patient_by_id(db, patient_id=patient_id)
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    
    return {
        "id": patient.id,
        "name": patient.name,
        "pronouns": patient.pronouns,
        "email": patient.email,
        "background": patient.background,
        "medical_history": patient.medical_history,
        "family_history": patient.family_history,
        "social_history": patient.social_history,
        "previous_treatment": patient.previous_treatment
    }

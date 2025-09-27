from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import Optional
from .. import crud, schemas
from ..database import get_db

router = APIRouter()

@router.get("/users/{user_id}")
async def get_user_by_email(
    user_id: str,
    email: str = Query(..., description="User email for lookup"),
    db: Session = Depends(get_db)
):
    """Get user by email - returns user ID for backend lookups"""
    user = crud.get_user_by_email(db, email=email)
    if user is None:
        # For MVP, create user if doesn't exist
        user_create = schemas.UserCreate(email=email)
        user = crud.create_user(db, user_create)
    
    return {"id": user.id}

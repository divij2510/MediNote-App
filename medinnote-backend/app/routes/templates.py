from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from .. import crud, schemas
from ..database import get_db

router = APIRouter()

@router.get("/v1/fetch-default-template-ext", response_model=schemas.TemplatesResponse)
async def get_user_templates(
    userId: str = Query(..., description="User ID"),
    db: Session = Depends(get_db)
):
    """Get templates for a user (includes system templates)"""
    # Verify user exists
    user = crud.get_user_by_id(db, user_id=userId)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    templates = crud.get_templates_by_user_id(db, user_id=userId)
    
    return schemas.TemplatesResponse(
        success=True,
        data=templates
    )

@router.post("/v1/templates")
async def create_template(
    template: schemas.TemplateCreate,
    db: Session = Depends(get_db)
):
    """Create a new template"""
    db_template = crud.create_template(db, template)
    return db_template

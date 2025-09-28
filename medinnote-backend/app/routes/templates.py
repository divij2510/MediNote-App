from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from .. import crud, schemas
from ..database import get_db

router = APIRouter()

def convert_template_to_dict(template):
    """Convert SQLAlchemy template model to dict with string UUIDs"""
    if not template:
        return None
    return {
        "id": str(template.id),
        "title": template.title,
        "type": template.type,
        "user_id": str(template.user_id) if template.user_id else None,
        "created_at": template.created_at
    }

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
    templates_dict = [convert_template_to_dict(t) for t in templates]
    
    return schemas.TemplatesResponse(
        success=True,
        data=templates_dict
    )

@router.post("/v1/templates")
async def create_template(
    template: schemas.TemplateCreate,
    db: Session = Depends(get_db)
):
    """Create a new template"""
    db_template = crud.create_template(db, template)
    if not db_template:
        raise HTTPException(status_code=400, detail="Failed to create template")
    
    return convert_template_to_dict(db_template)

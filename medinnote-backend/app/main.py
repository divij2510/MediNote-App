from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .database import engine
from . import models
from .routes import users, patients, templates, sessions
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Create database tables
models.Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="MediNote API",
    description="Backend API for MediNote medical consultation recording app",
    version="1.0.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(users.router, tags=["users"])
app.include_router(patients.router, tags=["patients"])
app.include_router(templates.router, tags=["templates"])
app.include_router(sessions.router, tags=["sessions"])

@app.get("/")
async def root():
    return {"message": "MediNote API is running", "version": "1.0.0"}

@app.get("/health")
async def health_check():
    return {"status": "healthy", "message": "API is operational"}

# Startup event to create default templates
@app.on_event("startup")
async def startup_event():
    logger.info("MediNote API starting up...")
    
    # Create default system templates
    from .database import SessionLocal
    from . import crud, schemas
    
    db = SessionLocal()
    try:
        # Check if system templates already exist
        existing_templates = db.query(models.Template).filter(
            models.Template.user_id.is_(None)
        ).first()
        
        if not existing_templates:
            # Create default system templates
            default_templates = [
                {"title": "New Patient Visit", "type": "default"},
                {"title": "Follow-up Visit", "type": "predefined"},
                {"title": "Consultation", "type": "predefined"},
                {"title": "Emergency Visit", "type": "predefined"}
            ]
            
            for template_data in default_templates:
                template_create = schemas.TemplateCreate(**template_data, user_id=None)
                crud.create_template(db, template_create)
            
            logger.info("Created default system templates")
    except Exception as e:
        logger.error(f"Error creating default templates: {e}")
    finally:
        db.close()
    
    logger.info("MediNote API startup complete")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)

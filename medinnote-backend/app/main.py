from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .routes import users, patients, templates, sessions, audio
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

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
app.include_router(audio.router, tags=["audio"])  

@app.get("/")
async def root():
    return {"message": "MediNote API is running", "version": "1.0.0"}

@app.get("/health")
async def health_check():
    """Health check endpoint that doesn't require database connection"""
    from .config import settings
    return {
        "status": "healthy", 
        "message": "API is operational",
        "database_configured": bool(settings.database_url),
        "supabase_configured": bool(settings.supabase_url and settings.supabase_service_role_key)
    }

# Startup event to initialize database and create default templates
@app.on_event("startup")
async def startup_event():
    logger.info("MediNote API starting up...")
    
    try:
        # Try to initialize database
        from .database import engine
        from . import models
        
        # Create database tables
        models.Base.metadata.create_all(bind=engine)
        logger.info("Database tables created successfully")
        
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
            else:
                logger.info("Default templates already exist")
                
        except Exception as e:
            logger.error(f"Error creating default templates: {e}")
        finally:
            db.close()
            
    except Exception as e:
        logger.error(f"Database initialization failed: {e}")
        logger.warning("API will run in limited mode without database")
    
    logger.info("MediNote API startup complete")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)

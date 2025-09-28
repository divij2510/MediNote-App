from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import NullPool
from sqlalchemy.exc import OperationalError
import time
import logging
from .config import settings

logger = logging.getLogger(__name__)

def create_database_engine():
    """Create database engine with retry logic"""
    database_url = settings.get_database_url()
    
    try:
        engine = create_engine(
            database_url,
            poolclass=NullPool,  # Disable connection pooling for Supabase
            pool_pre_ping=True,  # Test connections before use
            pool_recycle=300,    # Recycle connections every 5 minutes
            connect_args={
                "connect_timeout": 10,  # 10 second timeout
                "application_name": "medinnote_backend"
            }
        )
        
        # Test the connection
        with engine.connect() as conn:
            conn.execute("SELECT 1")
        logger.info("Database connection successful")
        return engine
        
    except Exception as e:
        logger.error(f"Database connection failed: {e}")
        raise

# Create engine with retry logic
max_retries = 3
retry_delay = 5

for attempt in range(max_retries):
    try:
        engine = create_database_engine()
        break
    except Exception as e:
        if attempt == max_retries - 1:
            logger.error(f"Failed to connect to database after {max_retries} attempts: {e}")
            raise
        else:
            logger.warning(f"Database connection attempt {attempt + 1} failed, retrying in {retry_delay} seconds...")
            time.sleep(retry_delay)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

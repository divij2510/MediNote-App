from pydantic import BaseSettings
from typing import Optional
import secrets

class Settings(BaseSettings):
    # Database (Supabase PostgreSQL)
    database_url: str = "postgresql://postgres:password@localhost:5432/medinnote"
    
    # JWT
    secret_key: str = secrets.token_urlsafe(32)
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 30
    
    # Supabase Configuration
    supabase_url: Optional[str] = None
    supabase_anon_key: Optional[str] = None
    supabase_service_role_key: Optional[str] = None
    
    # Development
    debug: bool = True
    
    class Config:
        env_file = ".env"

settings = Settings()

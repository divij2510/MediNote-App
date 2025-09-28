from pydantic_settings import BaseSettings
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
    
    def get_database_url(self) -> str:
        """Get the correct database URL based on environment"""
        # If we have Supabase URL, use Supabase connection
        if self.supabase_url:
            # Extract database connection details from Supabase URL
            # Format: postgresql://postgres:[password]@[host]:[port]/postgres
            # You need to replace this with your actual Supabase database URL
            return f"postgresql://postgres:[YOUR_DB_PASSWORD]@aws-1-ap-south-1.pooler.supabase.com:6543/postgres"
        return self.database_url
    
    class Config:
        env_file = ".env"

settings = Settings()

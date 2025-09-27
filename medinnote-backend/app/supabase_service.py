import os
from supabase import create_client, Client
from .config import settings
from typing import Optional
import logging

logger = logging.getLogger(__name__)

class SupabaseService:
    def __init__(self):
        self.supabase: Optional[Client] = None
        self._initialize_client()
    
    def _initialize_client(self):
        """Initialize Supabase client if credentials are available"""
        try:
            if settings.supabase_url and settings.supabase_service_role_key:
                self.supabase = create_client(
                    settings.supabase_url,
                    settings.supabase_service_role_key
                )
                logger.info("Supabase client initialized successfully")
            else:
                logger.warning("Supabase credentials not found, using mock storage")
        except Exception as e:
            logger.error(f"Failed to initialize Supabase client: {e}")
    
    def upload_audio_chunk(
        self, 
        bucket_name: str, 
        file_path: str, 
        file_data: bytes,
        content_type: str = "audio/wav"
    ) -> dict:
        """Upload audio chunk to Supabase Storage"""
        try:
            if not self.supabase:
                # Return mock response for development
                return {
                    "success": True,
                    "url": f"https://mock-storage.supabase.co/storage/v1/object/public/{bucket_name}/{file_path}",
                    "path": file_path,
                    "mock": True
                }
            
            # Upload to Supabase Storage
            result = self.supabase.storage.from_(bucket_name).upload(
                file_path,
                file_data,
                file_options={"content-type": content_type}
            )
            
            if result.status_code == 200:
                # Get public URL
                public_url = self.supabase.storage.from_(bucket_name).get_public_url(file_path)
                
                return {
                    "success": True,
                    "url": public_url,
                    "path": file_path,
                    "mock": False
                }
            else:
                logger.error(f"Upload failed: {result}")
                return {"success": False, "error": "Upload failed"}
                
        except Exception as e:
            logger.error(f"Error uploading to Supabase Storage: {e}")
            return {"success": False, "error": str(e)}
    
    def generate_presigned_url(
        self, 
        bucket_name: str, 
        file_path: str,
        expires_in: int = 3600
    ) -> dict:
        """Generate presigned URL for upload"""
        try:
            if not self.supabase:
                # Return mock presigned URL for development
                return {
                    "success": True,
                    "presigned_url": f"https://mock-storage.supabase.co/storage/v1/upload/sign/{bucket_name}/{file_path}",
                    "public_url": f"https://mock-storage.supabase.co/storage/v1/object/public/{bucket_name}/{file_path}",
                    "path": file_path,
                    "mock": True
                }
            
            # Create signed upload URL
            signed_url = self.supabase.storage.from_(bucket_name).create_signed_upload_url(file_path)
            
            if signed_url.get("signedURL"):
                public_url = self.supabase.storage.from_(bucket_name).get_public_url(file_path)
                
                return {
                    "success": True,
                    "presigned_url": signed_url["signedURL"],
                    "public_url": public_url,
                    "path": file_path,
                    "mock": False
                }
            else:
                return {"success": False, "error": "Failed to create signed URL"}
                
        except Exception as e:
            logger.error(f"Error generating presigned URL: {e}")
            # Return mock URL as fallback
            return {
                "success": True,
                "presigned_url": f"https://mock-storage.supabase.co/storage/v1/upload/sign/{bucket_name}/{file_path}",
                "public_url": f"https://mock-storage.supabase.co/storage/v1/object/public/{bucket_name}/{file_path}",
                "path": file_path,
                "mock": True
            }
    
    def delete_file(self, bucket_name: str, file_path: str) -> dict:
        """Delete file from Supabase Storage"""
        try:
            if not self.supabase:
                return {"success": True, "mock": True}
            
            result = self.supabase.storage.from_(bucket_name).remove([file_path])
            return {"success": True, "result": result}
            
        except Exception as e:
            logger.error(f"Error deleting file: {e}")
            return {"success": False, "error": str(e)}

# Global instance
supabase_service = SupabaseService()

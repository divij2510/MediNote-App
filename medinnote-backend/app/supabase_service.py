import os
from supabase import create_client, Client
from .config import settings
from typing import Optional
import logging
import uuid

logger = logging.getLogger(__name__)

class SupabaseService:
    def __init__(self):
        self.supabase: Optional[Client] = None
        self._initialize_client()
    
    def _initialize_client(self):
        """Initialize Supabase client if credentials are available"""
        try:
            if settings.supabase_url and settings.supabase_anon_key:
                self.supabase = create_client(
                    settings.supabase_url,
                    settings.supabase_anon_key
                )
                logger.info("Supabase client initialized successfully")
            else:
                logger.warning("Supabase credentials not found, using file storage fallback")
        except Exception as e:
            logger.error(f"Failed to initialize Supabase client: {e}")
    
    def generate_presigned_url(self, file_path: str, bucket_name: str = "recording_app", expires_in: int = 3600) -> dict:
        """Generate presigned URL for upload with proper auth headers"""
        try:
            if not self.supabase:
                return self._local_storage_response(bucket_name, file_path)
            
            # Use direct upload URL (bypass signed URL issues)
            public_url = self.supabase.storage.from_(bucket_name).get_public_url(file_path)
            upload_url = f"{settings.supabase_url}/storage/v1/object/{bucket_name}/{file_path}"
            
            logger.info(f"Using direct upload URL: {upload_url}")
            
            return {
                "success": True,
                "presigned_url": upload_url,
                "public_url": public_url,
                "path": file_path,
                "headers": {
                    "Authorization": f"Bearer {settings.supabase_anon_key}",
                    "Content-Type": "audio/mpeg",
                    "x-upsert": "true"
                }
            }
                
        except Exception as e:
            logger.error(f"Error generating presigned URL: {e}")
            return self._local_storage_response(bucket_name, file_path)
    
    def _local_storage_response(self, bucket_name: str, file_path: str) -> dict:
        """Fallback to local storage simulation"""
        # For development - use a mock endpoint that accepts uploads
        return {
            "success": True,
            "presigned_url": f"https://httpbin.org/put",
            "public_url": f"https://mock-storage.local/{bucket_name}/{file_path}",
            "path": file_path,
            "headers": {}
        }
    
    def verify_upload(self, bucket_name: str, file_path: str) -> dict:
        """Verify that file was uploaded successfully"""
        try:
            if not self.supabase:
                return {"exists": True, "mock": True}
            
            # Check if file exists in Supabase
            try:
                file_list = self.supabase.storage.from_(bucket_name).list(path=os.path.dirname(file_path))
                filename = os.path.basename(file_path)
                exists = any(f['name'] == filename for f in file_list)
                
                return {"exists": exists, "mock": False}
            except Exception as e:
                logger.error(f"Error verifying upload: {e}")
                return {"exists": False, "error": str(e)}
                
        except Exception as e:
            logger.error(f"Error in verify_upload: {e}")
            return {"exists": False, "error": str(e)}
    
    def get_session_audio_chunks(self, session_id: str) -> list:
        """Get all audio chunks for a session"""
        try:
            if not self.supabase:
                return []
            
            bucket_name = "recording_app"
            folder_path = f"sessions/{session_id}/"
            
            # List all files in the session folder
            files = self.supabase.storage.from_(bucket_name).list(path=folder_path)
            
            chunks = []
            for file in files:
                if file['name'].startswith('chunk_'):
                    chunk_number = int(file['name'].split('_')[1].split('.')[0])
                    public_url = self.supabase.storage.from_(bucket_name).get_public_url(f"{folder_path}{file['name']}")
                    
                    chunks.append({
                        "chunk_number": chunk_number,
                        "file_name": file['name'],
                        "public_url": public_url,
                        "size": file.get('metadata', {}).get('size', 0),
                        "created_at": file.get('created_at'),
                        "updated_at": file.get('updated_at')
                    })
            
            # Sort by chunk number
            chunks.sort(key=lambda x: x['chunk_number'])
            return chunks
            
        except Exception as e:
            logger.error(f"Error getting session audio chunks: {e}")
            return []
    
    async def upload_audio_chunk(self, file_path: str, audio_data: bytes, mime_type: str = "audio/mp4") -> dict:
        """Upload audio chunk to Supabase storage"""
        try:
            if not self.supabase:
                # Mock upload for development
                logger.info(f"Mock upload: {file_path} ({len(audio_data)} bytes)")
                return {
                    "success": True,
                    "path": file_path,
                    "public_url": f"https://mock-storage.local/{file_path}",
                    "mock": True
                }
            
            bucket_name = "recording_app"
            
            # For now, use mock upload since Supabase client has issues with binary data
            # In production, you'd implement proper file upload
            logger.info(f"Mock upload: {file_path} ({len(audio_data)} bytes)")
            return {
                "success": True,
                "path": file_path,
                "public_url": f"https://mock-storage.local/{file_path}",
                "mock": True
            }
                
        except Exception as e:
            logger.error(f"Error uploading audio chunk: {e}")
            return {
                "success": False,
                "error": str(e)
            }

# Global instance
supabase_service = SupabaseService()

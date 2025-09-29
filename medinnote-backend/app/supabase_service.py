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
                logger.error("Supabase client not initialized")
                return {"success": False, "error": "Supabase not configured"}
            
            bucket_name = "recording_app"
            
            # Ensure bucket exists
            try:
                buckets = self.supabase.storage.list_buckets()
                bucket_exists = any(bucket['name'] == bucket_name for bucket in buckets)
                if not bucket_exists:
                    logger.info(f"Creating bucket: {bucket_name}")
                    self.supabase.storage.create_bucket(bucket_name, public=True)
            except Exception as e:
                logger.warning(f"Could not check/create bucket: {e}")
            
            # Upload directly from bytes without temporary file
            try:
                # Method 1: Direct bytes upload
                result = self.supabase.storage.from_(bucket_name).upload(
                    path=file_path,
                    file=audio_data,
                    file_options={
                        "content-type": mime_type,
                        "upsert": True
                    }
                )
                
                # Handle different response types
                if result is True:
                    # Boolean True means success
                    public_url = self.supabase.storage.from_(bucket_name).get_public_url(file_path)
                    logger.info(f"Audio chunk uploaded successfully: {file_path}")
                    return {
                        "success": True,
                        "path": file_path,
                        "public_url": public_url
                    }
                elif isinstance(result, dict):
                    if result.get('error'):
                        error_msg = result.get('error', 'Upload failed')
                        logger.error(f"Upload failed: {error_msg}")
                        return {"success": False, "error": error_msg}
                    else:
                        public_url = self.supabase.storage.from_(bucket_name).get_public_url(file_path)
                        logger.info(f"Audio chunk uploaded successfully: {file_path}")
                        return {
                            "success": True,
                            "path": file_path,
                            "public_url": public_url
                        }
                else:
                    # Try to get public URL anyway
                    try:
                        public_url = self.supabase.storage.from_(bucket_name).get_public_url(file_path)
                        logger.info(f"Audio chunk uploaded (unknown result type): {file_path}")
                        return {
                            "success": True,
                            "path": file_path,
                            "public_url": public_url
                        }
                    except Exception as url_error:
                        logger.error(f"Could not get public URL: {url_error}")
                        return {"success": False, "error": f"Upload result unclear: {type(result)}"}
                        
            except Exception as upload_error:
                logger.error(f"Direct upload failed: {upload_error}")
                
                # Fallback: Use temporary file method
                import tempfile
                import os
                
                with tempfile.NamedTemporaryFile(delete=False, suffix='.mp3') as temp_file:
                    temp_file.write(audio_data)
                    temp_file_path = temp_file.name
                
                try:
                    with open(temp_file_path, 'rb') as f:
                        result = self.supabase.storage.from_(bucket_name).upload(
                            path=file_path,
                            file=f,
                            file_options={
                                "content-type": mime_type,
                                "upsert": True
                            }
                        )
                    
                    if result is True or (isinstance(result, dict) and not result.get('error')):
                        public_url = self.supabase.storage.from_(bucket_name).get_public_url(file_path)
                        logger.info(f"Audio chunk uploaded via temp file: {file_path}")
                        return {
                            "success": True,
                            "path": file_path,
                            "public_url": public_url
                        }
                    else:
                        error_msg = result.get('error', 'Upload failed') if isinstance(result, dict) else 'Upload failed'
                        logger.error(f"Temp file upload failed: {error_msg}")
                        return {"success": False, "error": error_msg}
                        
                finally:
                    # Clean up temporary file
                    if os.path.exists(temp_file_path):
                        os.unlink(temp_file_path)
                
        except Exception as e:
            logger.error(f"Error uploading audio chunk: {e}")
            return {"success": False, "error": str(e)}

# Global instance
supabase_service = SupabaseService()

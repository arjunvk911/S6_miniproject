import firebase_admin
from firebase_admin import credentials, firestore
import os
import glob

print("=========================================")
print("  POTHOLE DATABASE & IMAGE CLEAR TOOL")
print("=========================================")

# 1. Clear Firebase Firestore
try:
    print("\n1. Connecting to Firebase...")
    print("   [SKIPPED] Google Cloud Firebase has temporarily blocked your")
    print("             database due to the 429 Quota Exceeded free tier limit.")
    print("             This step is skipped to prevent the script from freezing.")
except Exception as e:
    print(f"   ❌ Error clearing Firebase: {e}")

# 2. Clear Local Uploaded Images
try:
    print("\n2. Clearing local images in 'images/uploads/'...")
    image_files = glob.glob(os.path.join("images", "uploads", "*.jpg"))
    img_count = 0
    for file_path in image_files:
        os.remove(file_path)
        img_count += 1
        
    print(f"   ✅ Successfully deleted {img_count} images from local storage!")
except Exception as e:
    print(f"   ❌ Error clearing images: {e}")

print("\n=========================================")
print("  DONE! Restart your FastAPI server (main.py)")
print("  and clear your browser cache.")
print("=========================================")

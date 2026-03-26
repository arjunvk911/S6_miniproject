"""
================================================
 PHASE 2: FASTAPI BACKEND - GROUP 4
 College of Engineering and Management Punnapra
 Members: Adithyan, Arjun, Anandhu, Chirag

 Run: python main.py
 API will start at: http://localhost:8000
================================================
"""

from fastapi import FastAPI, File, UploadFile, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import firebase_admin
from firebase_admin import credentials, firestore
from ultralytics import YOLO
import cv2
import numpy as np
import uuid
import os
import base64
from datetime import datetime

# ─────────────────────────────────────────────
# SETUP
# ─────────────────────────────────────────────
app = FastAPI(title="Pothole Detection API - Group 4")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

os.makedirs("images/uploads", exist_ok=True)
from fastapi.staticfiles import StaticFiles
app.mount("/images", StaticFiles(directory="images"), name="images")

import urllib.request
import json
import asyncio

def get_jurisdiction(lat, lon):
    try:
        url = f"https://nominatim.openstreetmap.org/reverse?format=json&lat={lat}&lon={lon}&zoom=18&addressdetails=1"
        req = urllib.request.Request(url, headers={'User-Agent': 'PotholeDetectionApp/1.0'})
        with urllib.request.urlopen(req, timeout=3) as response:
            data = json.loads(response.read().decode())
            address = data.get('address', {})
            road = data.get('name', '').lower()
            ref = (address.get('road', '') + " " + address.get('highway', '')).lower()
            if 'nh' in ref or 'national highway' in ref or 'nh' in road:
                return "NHAI"
    except Exception:
        pass
    return "PWD"

# Load YOLO model
MODEL_PATH = "runs/detect/pothole_model/weights/best.pt"
model = YOLO(MODEL_PATH)
print("✅ YOLO model loaded!")

# Connect to Firebase
cred = credentials.Certificate("firebase_key.json")
firebase_admin.initialize_app(cred)
db = firestore.client()
print("✅ Firebase connected!")

# ─────────────────────────────────────────────
# SEVERITY CLASSIFICATION
# ─────────────────────────────────────────────
def get_severity(box_area, image_area):
    ratio = box_area / image_area
    if ratio > 0.05:
        return "HIGH"
    elif ratio > 0.01:
        return "MEDIUM"
    else:
        return "LOW"

# ─────────────────────────────────────────────
# ROUTES
# ─────────────────────────────────────────────

@app.get("/")
def root():
    from fastapi.responses import HTMLResponse
    try:
        with open("dashboard.html", "r", encoding="utf-8") as f:
            return HTMLResponse(content=f.read())
    except Exception:
        return {"status": "running", "project": "Pothole Detection - Group 4"}

# ─────────────────────────────────────────────
# MAIN: DETECT POTHOLES FROM IMAGE
# ─────────────────────────────────────────────
@app.post("/detect")
@app.post("/detect")
async def detect_pothole(
    file: UploadFile = File(...),
    latitude: float  = Form(0.0),
    longitude: float = Form(0.0),
    confidence: float = Form(0.20),
):
    try:
        jurisdiction = await asyncio.to_thread(get_jurisdiction, latitude, longitude)
        contents = await file.read()
        
        is_video = False
        content_type = file.content_type
        if content_type and content_type.startswith('video'):
            is_video = True
        elif file.filename.lower().endswith(('.mp4', '.avi', '.mov', '.mkv', '.webm')):
            is_video = True
            
        if is_video:
            import tempfile
            with tempfile.NamedTemporaryFile(delete=False, suffix=".mp4") as tmp:
                tmp.write(contents)
                tmp_path = tmp.name
                
            cap = cv2.VideoCapture(tmp_path)
            best_image = None
            best_predictions = []
            best_overall = "NONE"
            best_score = -1
            first_frame = None
            frame_count = 0
            checks = 0
            
            sev_rank = {"HIGH": 3, "MEDIUM": 2, "LOW": 1, "NONE": 0}
            
            while cap.isOpened() and checks < 20:
                ret, frame = cap.read()
                if not ret:
                    break
                    
                if first_frame is None:
                    first_frame = frame.copy()
                    
                frame_count += 1
                if frame_count % 15 != 0:
                    continue
                    
                checks += 1
                img_h, img_w = frame.shape[:2]
                image_area = img_h * img_w
                
                results = model(frame, verbose=False)
                predictions = []
                for result in results:
                    if result.boxes is None: continue
                    for box in result.boxes:
                        conf = float(box.conf[0])
                        if conf < confidence: continue
                        x1, y1, x2, y2 = map(int, box.xyxy[0])
                        w_pad = int((x2 - x1) * 0.20)
                        h_pad = int((y2 - y1) * 0.20)
                        x1 = max(0, x1 - w_pad)
                        y1 = max(0, y1 - h_pad)
                        x2 = min(img_w, x2 + w_pad)
                        y2 = min(img_h, y2 + h_pad)
                        box_area = (x2 - x1) * (y2 - y1)
                        severity = get_severity(box_area, image_area)
                        predictions.append({
                            "severity":   severity,
                            "confidence": round(conf * 100, 1),
                            "box": {"x1": x1, "y1": y1, "x2": x2, "y2": y2}
                        })
                        
                overall = "NONE"
                if predictions:
                    if any(p["severity"] == "HIGH"   for p in predictions): overall = "HIGH"
                    elif any(p["severity"] == "MEDIUM" for p in predictions): overall = "MEDIUM"
                    else: overall = "LOW"
                    
                score = sev_rank[overall] * 100 + len(predictions)
                if score > best_score:
                    best_score = score
                    best_image = results[0].plot(line_width=2, font_size=1) if len(predictions) > 0 else frame.copy()
                    best_predictions = predictions
                    best_overall = overall
                    
            cap.release()
            try:
                os.remove(tmp_path)
            except:
                pass
                
            image = best_image if best_image is not None else first_frame
            if image is None:
                return JSONResponse({"error": "Failed to read video frames"}, status_code=400)
                
            predictions = best_predictions
            overall = best_overall
        else:
            np_arr   = np.frombuffer(contents, np.uint8)
            image    = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)

            if image is None:
                return JSONResponse({"error": "Invalid image"}, status_code=400)

            img_h, img_w = image.shape[:2]
            image_area   = img_h * img_w

            results     = model(image, verbose=False)
            predictions = []

            for result in results:
                if result.boxes is None:
                    continue
                for box in result.boxes:
                    conf = float(box.conf[0])
                    if conf < confidence:
                        continue

                    x1, y1, x2, y2 = map(int, box.xyxy[0])
                    
                    w_pad = int((x2 - x1) * 0.20)
                    h_pad = int((y2 - y1) * 0.20)
                    x1 = max(0, x1 - w_pad)
                    y1 = max(0, y1 - h_pad)
                    x2 = min(img_w, x2 + w_pad)
                    y2 = min(img_h, y2 + h_pad)
                    
                    box_area = (x2 - x1) * (y2 - y1)
                    severity = get_severity(box_area, image_area)

                    predictions.append({
                        "severity":   severity,
                        "confidence": round(conf * 100, 1),
                        "box": {"x1": x1, "y1": y1, "x2": x2, "y2": y2}
                    })

            overall = "NONE"
            if predictions:
                if any(p["severity"] == "HIGH"   for p in predictions): overall = "HIGH"
                elif any(p["severity"] == "MEDIUM" for p in predictions): overall = "MEDIUM"
                else: overall = "LOW"

            if results and len(predictions) > 0:
                image = results[0].plot(line_width=2, font_size=1)

        report_id = str(uuid.uuid4())[:8]
        image_path = f"images/uploads/{report_id}.jpg"
        cv2.imwrite(image_path, image)
        image_url = f"/images/uploads/{report_id}.jpg"

        # Save to Firebase
        report = {
            "id":           report_id,
            "timestamp":    datetime.now().isoformat(),
            "latitude":     latitude,
            "longitude":    longitude,
            "total":        len(predictions),
            "severity":     overall,
            "detections":   predictions,
            "status":       "Pending",
            "jurisdiction": jurisdiction,
            "image_url":    image_url,   # ← Full high-res image URL stored for dashboard
        }

        if predictions:
            try:
                db.collection("potholes_v2").document(report_id).set(report)
            except Exception as e:
                print("Firebase Write Warning (Quota):", e)
            print(f"  ✅ Saved report {report_id} — {overall} — {len(predictions)} pothole(s)")
            
            # Push into memory fallback cache for offline resiliency
            if "LOCAL_REPORTS_CACHE" in globals():
                LOCAL_REPORTS_CACHE.insert(0, report)

        return {
            "success":    True,
            "report_id":  report_id,
            "total":      len(predictions),
            "severity":   overall,
            "jurisdiction": jurisdiction,
            "detections": predictions,
            "image_url":  image_url,
            "saved_to_db": len(predictions) > 0
        }

    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)

# ─────────────────────────────────────────────
# GET ALL REPORTS (for dashboard)
# ─────────────────────────────────────────────
LOCAL_REPORTS_CACHE = []
LAST_CACHE_TIME = 0

@app.get("/reports")
def get_reports():
    global LOCAL_REPORTS_CACHE, LAST_CACHE_TIME
    import time
    try:
        now = time.time()
        if (now - LAST_CACHE_TIME) < 5 and LOCAL_REPORTS_CACHE:
            return {"success": True, "count": len(LOCAL_REPORTS_CACHE), "reports": LOCAL_REPORTS_CACHE, "cached": True}

        docs    = db.collection("potholes_v2").stream()
        reports = [doc.to_dict() for doc in docs]
        reports.sort(key=lambda x: x.get("timestamp", ""), reverse=True)
        
        LOCAL_REPORTS_CACHE = reports
        LAST_CACHE_TIME = now
        return {"success": True, "count": len(reports), "reports": reports}
    except Exception as e:
        print("Firebase Quota/Network Warning:", e)
        if not LOCAL_REPORTS_CACHE:
            LOCAL_REPORTS_CACHE = [
                {"id": "demo001", "timestamp": datetime.now().isoformat(), "latitude": 9.45, "longitude": 76.33, "total": 3, "severity": "HIGH", "jurisdiction": "PWD", "status": "Pending", "image_url": ""},
                {"id": "demo002", "timestamp": datetime.now().isoformat(), "latitude": 9.46, "longitude": 76.35, "total": 1, "severity": "LOW", "jurisdiction": "NHAI", "status": "Work in Progress", "image_url": ""}
            ]
        return {"success": True, "count": len(LOCAL_REPORTS_CACHE), "reports": LOCAL_REPORTS_CACHE, "cached": True, "quota_warning": True}

# ─────────────────────────────────────────────
# UPDATE REPORT STATUS
# ─────────────────────────────────────────────
@app.put("/reports/{report_id}/status")
def update_status(report_id: str, status: str):
    global LOCAL_REPORTS_CACHE
    try:
        valid = ["Pending", "Work in Progress", "Repaired"]
        if status not in valid:
            return JSONResponse({"error": f"Status must be one of {valid}"}, status_code=400)
            
        try:
            db.collection("potholes_v2").document(report_id).update({"status": status})
        except Exception as e:
            print("Firebase Update Warning (Quota):", e)
            
        for r in LOCAL_REPORTS_CACHE:
            if r.get("id") == report_id:
                r["status"] = status
                break
                
        return {"success": True, "report_id": report_id, "status": status}
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)

@app.delete("/reports/{report_id}")
def delete_report(report_id: str):
    global LOCAL_REPORTS_CACHE
    try:
        db.collection("potholes_v2").document(report_id).delete()
    except Exception as e:
        print("Firebase Delete Warning (Quota):", e)
        
    # Always remove from memory cache so standard users no longer see it
    LOCAL_REPORTS_CACHE = [r for r in LOCAL_REPORTS_CACHE if r.get("id") != report_id]
    return {"success": True, "deleted_id": report_id}


# ─────────────────────────────────────────────
# RUN SERVER
# ─────────────────────────────────────────────
if __name__ == "__main__":
    import uvicorn
    print("\n====================================")
    print("  POTHOLE DETECTION API - GROUP 4")
    print("  Running at: http://localhost:8000")
    print("  API Docs:   http://localhost:8000/docs")
    print("====================================\n")
    uvicorn.run(app, host="0.0.0.0", port=8000)

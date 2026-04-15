"""
================================================
 PHASE 2: FASTAPI BACKEND - GROUP 4
 College of Engineering and Management Punnapra
 Members: Adithyan, Arjun, Anandhu, Chirag

 Run: python main.py
 API will start at: http://localhost:8000
================================================
"""

from fastapi import FastAPI, File, UploadFile, Form, Query
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
import json
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
import asyncio

# ─────────────────────────────────────────────
# LOCAL JSON PERSISTENCE
# ─────────────────────────────────────────────
LOCAL_JSON_PATH = "pothole_reports.json"

def load_local_reports():
    """Load reports from local JSON file"""
    try:
        if os.path.exists(LOCAL_JSON_PATH):
            with open(LOCAL_JSON_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
                return data if isinstance(data, list) else []
    except Exception as e:
        print(f"⚠️ Error loading local reports: {e}")
    return []

def save_local_reports(reports):
    """Save reports to local JSON file"""
    try:
        with open(LOCAL_JSON_PATH, "w", encoding="utf-8") as f:
            json.dump(reports, f, indent=2, default=str)
    except Exception as e:
        print(f"⚠️ Error saving local reports: {e}")

def add_local_report(report):
    """Add a single report to local JSON"""
    reports = load_local_reports()
    # Avoid duplicates
    reports = [r for r in reports if r.get("id") != report.get("id")]
    reports.insert(0, report)
    save_local_reports(reports)

# ─────────────────────────────────────────────
# GEOCODING
# ─────────────────────────────────────────────
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

# Load persisted reports into memory cache on startup
LOCAL_REPORTS_CACHE = load_local_reports()
LAST_CACHE_TIME = 0
print(f"✅ Loaded {len(LOCAL_REPORTS_CACHE)} reports from local backup")

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

def draw_detections_on_image(image, predictions):
    """Draw thin bounding boxes + small labels so potholes remain visible"""
    severity_colors = {
        "HIGH":   (0, 0, 220),
        "MEDIUM": (0, 140, 255),
        "LOW":    (30, 180, 30),
    }
    font = cv2.FONT_HERSHEY_SIMPLEX
    font_scale = 0.45
    thickness = 1

    for p in predictions:
        b = p["box"]
        x1, y1, x2, y2 = b["x1"], b["y1"], b["x2"], b["y2"]
        color = severity_colors.get(p["severity"], (200, 200, 200))

        # Thin bounding box (1px)
        cv2.rectangle(image, (x1, y1), (x2, y2), color, 1)

        # Small corner accents
        cl = min(10, (x2-x1)//4, (y2-y1)//4)
        cv2.line(image, (x1, y1), (x1+cl, y1), color, 2)
        cv2.line(image, (x1, y1), (x1, y1+cl), color, 2)
        cv2.line(image, (x2, y1), (x2-cl, y1), color, 2)
        cv2.line(image, (x2, y1), (x2, y1+cl), color, 2)
        cv2.line(image, (x1, y2), (x1+cl, y2), color, 2)
        cv2.line(image, (x1, y2), (x1, y2-cl), color, 2)
        cv2.line(image, (x2, y2), (x2-cl, y2), color, 2)
        cv2.line(image, (x2, y2), (x2, y2-cl), color, 2)

        # Small label ABOVE the box so pothole is visible
        label = f"{p['severity']} {p['confidence']:.0f}%"
        (tw, th), _ = cv2.getTextSize(label, font, font_scale, thickness)
        label_y = max(th + 4, y1 - 4)
        cv2.rectangle(image, (x1, label_y - th - 4), (x1 + tw + 6, label_y + 2), color, -1)
        cv2.putText(image, label, (x1 + 3, label_y - 1), font, font_scale, (255, 255, 255), thickness, cv2.LINE_AA)

    return image

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
# FAST DETECT — For live webcam (no geocoding, no Firebase)
# ─────────────────────────────────────────────
@app.post("/detect-fast")
async def detect_fast(
    file: UploadFile = File(...),
    confidence: float = Form(0.50),
):
    """Lightweight detection for live webcam — returns detections only, no DB save"""
    try:
        contents = await file.read()
        np_arr = np.frombuffer(contents, np.uint8)
        image = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
        if image is None:
            return JSONResponse({"error": "Invalid image"}, status_code=400)

        # Use smaller input size for speed
        img_h, img_w = image.shape[:2]
        image_area = img_h * img_w
        results = model(image, verbose=False, imgsz=320)
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
                    "severity": severity,
                    "confidence": round(conf * 100, 1),
                    "box": {"x1": x1, "y1": y1, "x2": x2, "y2": y2}
                })

        overall = "NONE"
        if predictions:
            if any(p["severity"] == "HIGH" for p in predictions): overall = "HIGH"
            elif any(p["severity"] == "MEDIUM" for p in predictions): overall = "MEDIUM"
            else: overall = "LOW"

        return {
            "success": True,
            "total": len(predictions),
            "severity": overall,
            "detections": predictions,
        }
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)

# ─────────────────────────────────────────────
# MAIN: DETECT POTHOLES FROM IMAGE (full pipeline)
# ─────────────────────────────────────────────
@app.post("/detect")
async def detect_pothole(
    file: UploadFile = File(...),
    latitude: float  = Form(0.0),
    longitude: float = Form(0.0),
    confidence: float = Form(0.20),
    reported_by: str = Form("citizen"),
):
    try:
        # Run geocoding in parallel with detection (not blocking)
        jurisdiction_task = asyncio.get_event_loop().run_in_executor(None, get_jurisdiction, latitude, longitude)
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
                    best_image = frame.copy()
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
            
            if best_predictions:
                image = draw_detections_on_image(image, best_predictions)
                
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

            if predictions:
                image = draw_detections_on_image(image, predictions)

        # Await geocoding result
        jurisdiction = await jurisdiction_task

        report_id = str(uuid.uuid4())[:8]
        image_path = f"images/uploads/{report_id}.jpg"
        cv2.imwrite(image_path, image)
        image_url = f"/images/uploads/{report_id}.jpg"

        # Save to Firebase + Local
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
            "image_url":    image_url,
            "reported_by":  reported_by,
        }

        if predictions:
            try:
                db.collection("potholes_v2").document(report_id).set(report)
            except Exception as e:
                print("Firebase Write Warning (Quota):", e)
            print(f"  ✅ Saved report {report_id} — {overall} — {len(predictions)} pothole(s)")
            
            # Save to local JSON backup
            add_local_report(report)
            
            # Push into memory cache
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
# SAVE LIVE DETECTION — Called when live webcam finds a pothole
# ─────────────────────────────────────────────
@app.post("/save-live-report")
async def save_live_report(
    file: UploadFile = File(...),
    latitude: float = Form(0.0),
    longitude: float = Form(0.0),
    severity: str = Form("MEDIUM"),
    total: int = Form(1),
    reported_by: str = Form("citizen"),
):
    """Save a pothole detected during live webcam — runs geocoding + Firebase in background"""
    try:
        contents = await file.read()
        np_arr = np.frombuffer(contents, np.uint8)
        image = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
        if image is None:
            return JSONResponse({"error": "Invalid image"}, status_code=400)

        jurisdiction = await asyncio.to_thread(get_jurisdiction, latitude, longitude)

        report_id = str(uuid.uuid4())[:8]
        image_path = f"images/uploads/{report_id}.jpg"
        cv2.imwrite(image_path, image)
        image_url = f"/images/uploads/{report_id}.jpg"

        report = {
            "id": report_id,
            "timestamp": datetime.now().isoformat(),
            "latitude": latitude,
            "longitude": longitude,
            "total": total,
            "severity": severity,
            "detections": [],
            "status": "Pending",
            "jurisdiction": jurisdiction,
            "image_url": image_url,
            "reported_by": reported_by,
        }

        try:
            db.collection("potholes_v2").document(report_id).set(report)
        except Exception as e:
            print("Firebase Write Warning:", e)

        add_local_report(report)
        LOCAL_REPORTS_CACHE.insert(0, report)

        print(f"  ✅ Live report saved {report_id} — {severity}")
        return {"success": True, "report_id": report_id, "image_url": image_url, "jurisdiction": jurisdiction}

    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


# ─────────────────────────────────────────────
# GET ALL REPORTS (for dashboard)
# ─────────────────────────────────────────────
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
        
        # Merge with local reports (local may have reports Firebase missed due to quota)
        local_reports = load_local_reports()
        existing_ids = {r.get("id") for r in reports}
        for lr in local_reports:
            if lr.get("id") not in existing_ids:
                reports.append(lr)
        reports.sort(key=lambda x: x.get("timestamp", ""), reverse=True)
        
        LOCAL_REPORTS_CACHE = reports
        LAST_CACHE_TIME = now
        
        # Also save merged data to local file
        save_local_reports(reports)
        
        return {"success": True, "count": len(reports), "reports": reports}
    except Exception as e:
        print("Firebase Quota/Network Warning:", e)
        # Fall back to local JSON
        if not LOCAL_REPORTS_CACHE:
            LOCAL_REPORTS_CACHE = load_local_reports()
        if not LOCAL_REPORTS_CACHE:
            LOCAL_REPORTS_CACHE = [
                {"id": "demo001", "timestamp": datetime.now().isoformat(), "latitude": 9.45, "longitude": 76.33, "total": 3, "severity": "HIGH", "jurisdiction": "PWD", "status": "Pending", "image_url": "", "reported_by": "citizen"},
                {"id": "demo002", "timestamp": datetime.now().isoformat(), "latitude": 9.46, "longitude": 76.35, "total": 1, "severity": "LOW", "jurisdiction": "NHAI", "status": "Work in Progress", "image_url": "", "reported_by": "citizen"}
            ]
        return {"success": True, "count": len(LOCAL_REPORTS_CACHE), "reports": LOCAL_REPORTS_CACHE, "cached": True, "quota_warning": True}

# ─────────────────────────────────────────────
# GET MY REPORTS (for citizen — filtered by user)
# ─────────────────────────────────────────────
@app.get("/reports/mine")
def get_my_reports(user: str = Query("citizen")):
    """Get reports filtered by reported_by field"""
    try:
        all_reps = LOCAL_REPORTS_CACHE if LOCAL_REPORTS_CACHE else load_local_reports()
        my_reps = [r for r in all_reps if r.get("reported_by", "citizen") == user]
        return {"success": True, "count": len(my_reps), "reports": my_reps}
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)

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
        
        # Update local JSON too
        save_local_reports(LOCAL_REPORTS_CACHE)
                
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
        
    LOCAL_REPORTS_CACHE = [r for r in LOCAL_REPORTS_CACHE if r.get("id") != report_id]
    save_local_reports(LOCAL_REPORTS_CACHE)
    return {"success": True, "deleted_id": report_id}

# ─────────────────────────────────────────────
# COMPLAINTS & RATINGS (Firebase-backed)
# ─────────────────────────────────────────────
@app.post("/complaints")
async def submit_complaint(
    type: str = Form(...),
    report_id: str = Form(""),
    message: str = Form(...),
    submitted_by: str = Form("citizen"),
):
    try:
        complaint = {
            "id": str(uuid.uuid4())[:8],
            "type": type,
            "reportId": report_id,
            "msg": message,
            "submitted_by": submitted_by,
            "timestamp": datetime.now().isoformat(),
        }
        try:
            db.collection("complaints").document(complaint["id"]).set(complaint)
        except Exception as e:
            print("Firebase Complaint Warning:", e)
        return {"success": True, "complaint": complaint}
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)

@app.get("/complaints")
def get_complaints():
    try:
        docs = db.collection("complaints").stream()
        complaints = [doc.to_dict() for doc in docs]
        complaints.sort(key=lambda x: x.get("timestamp", ""), reverse=True)
        return {"success": True, "complaints": complaints}
    except Exception as e:
        return {"success": True, "complaints": []}

@app.post("/ratings")
async def submit_rating(
    stars: int = Form(...),
    comment: str = Form(""),
    submitted_by: str = Form("citizen"),
):
    try:
        rating = {
            "id": str(uuid.uuid4())[:8],
            "stars": stars,
            "comment": comment,
            "submitted_by": submitted_by,
            "timestamp": datetime.now().isoformat(),
        }
        try:
            db.collection("ratings").document(rating["id"]).set(rating)
        except Exception as e:
            print("Firebase Rating Warning:", e)
        return {"success": True, "rating": rating}
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)

@app.get("/ratings")
def get_ratings():
    try:
        docs = db.collection("ratings").stream()
        ratings = [doc.to_dict() for doc in docs]
        ratings.sort(key=lambda x: x.get("timestamp", ""), reverse=True)
        return {"success": True, "ratings": ratings}
    except Exception as e:
        return {"success": True, "ratings": []}


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

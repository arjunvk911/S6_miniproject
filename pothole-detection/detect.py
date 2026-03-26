"""
================================================
 POTHOLE DETECTION SYSTEM - GROUP 4
 College of Engineering and Management Punnapra
 Members: Adithyan, Arjun, Anandhu, Chirag

 3 Modes:
   1 - Image detection
   2 - Video detection
   3 - Live webcam (AUTO CAPTURE + GPS + SEND TO AUTHORITY!)

 Run: python detect.py
================================================
"""

from ultralytics import YOLO
import cv2
import os
import sys
import threading
import time
import requests
import numpy as np

# ─────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────
MODEL_PATH    = "runs/detect/pothole_model/weights/best.pt"
OUTPUT_FOLDER = "results"
API_URL       = "http://localhost:8000/detect"

os.makedirs(OUTPUT_FOLDER, exist_ok=True)
os.makedirs(os.path.join(OUTPUT_FOLDER, "auto_captures"), exist_ok=True)

if not os.path.exists(MODEL_PATH):
    print("\n  Model not found! Please run train.py first.")
    sys.exit(1)

model = YOLO(MODEL_PATH)

# ─────────────────────────────────────────────
# GET GPS LOCATION
# ─────────────────────────────────────────────
def get_gps():
    try:
        res  = requests.get("http://ip-api.com/json/", timeout=3)
        data = res.json()
        if data.get("status") == "success":
            return data["lat"], data["lon"]
    except:
        pass
    return 9.4981, 76.3388

# ─────────────────────────────────────────────
# AUDIO ALERT
# ─────────────────────────────────────────────
def play_alert(severity):
    try:
        import winsound
        patterns = {
            "HIGH":   [(1000, 200)] * 3,
            "MEDIUM": [(800,  300)] * 2,
            "LOW":    [(600,  400)] * 1,
        }
        for freq, dur in patterns.get(severity, []):
            winsound.Beep(freq, dur)
            time.sleep(0.1)
    except:
        pass
    try:
        import subprocess
        msg = {
            "HIGH":   "Warning! High severity pothole detected! Auto reporting to authority!",
            "MEDIUM": "Caution! Medium severity pothole detected! Sending report!",
            "LOW":    "Low severity pothole detected.",
        }.get(severity, "Pothole detected!")
        subprocess.Popen(
            ['powershell', '-Command',
             f'Add-Type -AssemblyName System.Speech; '
             f'$s = New-Object System.Speech.Synthesis.SpeechSynthesizer; '
             f'$s.Rate = 1; $s.Speak("{msg}")'],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
    except:
        pass

# ─────────────────────────────────────────────
# AUTO CAPTURE + SEND
# ─────────────────────────────────────────────
def auto_capture_and_send(frame, severity):
    try:
        timestamp = time.strftime("%Y%m%d_%H%M%S")
        filename  = f"auto_{severity}_{timestamp}.jpg"
        save_path = os.path.join(OUTPUT_FOLDER, "auto_captures", filename)
        cv2.imwrite(save_path, frame)
        print(f"  📸 Auto-captured: {filename}")

        lat, lng = get_gps()
        print(f"  📍 GPS: {lat}, {lng}")

        with open(save_path, "rb") as f:
            files = {"file": (filename, f, "image/jpeg")}
            data  = {"latitude": str(lat), "longitude": str(lng)}
            res   = requests.post(API_URL, files=files, data=data, timeout=10)

        if res.status_code == 200:
            result = res.json()
            print(f"  ✅ Sent! Report ID: #{result.get('report_id','—')}")
            print(f"  🗺️  Visible on dashboard map!")
        else:
            print(f"  ⚠️  Backend error: {res.status_code}")
    except requests.exceptions.ConnectionError:
        print("  ⚠️  Backend offline — saved locally only")
    except Exception as e:
        print(f"  ⚠️  Error: {e}")

# ─────────────────────────────────────────────
# SEVERITY
# ─────────────────────────────────────────────
def get_severity(box_area, image_area):
    ratio = box_area / image_area
    if ratio > 0.05:   return "HIGH",   (0, 0, 220)
    elif ratio > 0.01: return "MEDIUM", (0, 140, 255)
    else:              return "LOW",    (30, 180, 30)

# ─────────────────────────────────────────────
# DRAW LABEL (clean, no overlap)
# ─────────────────────────────────────────────
def draw_label(frame, text, x1, y1, x2, y2, color):
    """Draw label INSIDE the box at top-left corner"""
    font       = cv2.FONT_HERSHEY_SIMPLEX
    font_scale = 0.52
    thickness  = 1
    pad        = 5

    (tw, th), baseline = cv2.getTextSize(text, font, font_scale, thickness)

    # Label position — inside box top-left
    lx1 = x1
    ly1 = y1
    lx2 = x1 + tw + pad * 2
    ly2 = y1 + th + pad * 2

    # Keep label inside frame
    lx2 = min(lx2, frame.shape[1])
    ly2 = min(ly2, frame.shape[0])

    # Draw filled label background
    cv2.rectangle(frame, (lx1, ly1), (lx2, ly2), color, -1)

    # Draw text
    cv2.putText(frame, text,
                (lx1 + pad, ly1 + th + pad - 1),
                font, font_scale, (255, 255, 255), thickness, cv2.LINE_AA)

# ─────────────────────────────────────────────
# DRAW DETECTIONS
# ─────────────────────────────────────────────
def draw_detections(frame, results, min_conf=0.20):
    h, w       = frame.shape[:2]
    image_area = h * w
    counts     = {"HIGH": 0, "MEDIUM": 0, "LOW": 0}
    detections = []

    # Collect all detections first
    for result in results:
        if result.boxes is None: continue
        for box in result.boxes:
            conf = float(box.conf[0])
            if conf < min_conf: continue
            x1, y1, x2, y2 = map(int, box.xyxy[0])
            w_pad = int((x2 - x1) * 0.20)
            h_pad = int((y2 - y1) * 0.20)
            x1 = max(0, x1 - w_pad)
            y1 = max(0, y1 - h_pad)
            x2 = min(w, x2 + w_pad)
            y2 = min(h, y2 + h_pad)
            severity, color = get_severity((x2-x1)*(y2-y1), image_area)
            counts[severity] += 1
            detections.append((x1, y1, x2, y2, severity, color, conf))

    # Draw boxes first (all of them)
    for (x1, y1, x2, y2, severity, color, conf) in detections:
        # Draw box border
        cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)

        # Draw corner accents for style
        corner_len = min(12, (x2-x1)//4, (y2-y1)//4)
        cv2.line(frame, (x1, y1), (x1+corner_len, y1), color, 3)
        cv2.line(frame, (x1, y1), (x1, y1+corner_len), color, 3)
        cv2.line(frame, (x2, y1), (x2-corner_len, y1), color, 3)
        cv2.line(frame, (x2, y1), (x2, y1+corner_len), color, 3)
        cv2.line(frame, (x1, y2), (x1+corner_len, y2), color, 3)
        cv2.line(frame, (x1, y2), (x1, y2-corner_len), color, 3)
        cv2.line(frame, (x2, y2), (x2-corner_len, y2), color, 3)
        cv2.line(frame, (x2, y2), (x2, y2-corner_len), color, 3)

    # Draw labels on top (after all boxes)
    for (x1, y1, x2, y2, severity, color, conf) in detections:
        label = f"{severity}  {conf*100:.0f}%"
        draw_label(frame, label, x1, y1, x2, y2, color)

    # ── TOP SUMMARY BAR ──
    total = sum(counts.values())
    bar_h = 36
    overlay = frame.copy()
    cv2.rectangle(overlay, (0, 0), (w, bar_h), (15, 15, 15), -1)
    cv2.addWeighted(overlay, 0.85, frame, 0.15, 0, frame)

    # Summary text
    summary = f"Potholes: {total}"
    cv2.putText(frame, summary, (12, 24),
                cv2.FONT_HERSHEY_SIMPLEX, 0.65, (255, 255, 255), 1, cv2.LINE_AA)

    # Colored counts on right
    x_off = 160
    if counts["HIGH"] > 0:
        cv2.putText(frame, f"HIGH:{counts['HIGH']}", (x_off, 24),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (80, 80, 255), 1, cv2.LINE_AA)
        x_off += 90
    if counts["MEDIUM"] > 0:
        cv2.putText(frame, f"MED:{counts['MEDIUM']}", (x_off, 24),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (80, 180, 255), 1, cv2.LINE_AA)
        x_off += 90
    if counts["LOW"] > 0:
        cv2.putText(frame, f"LOW:{counts['LOW']}", (x_off, 24),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (80, 200, 80), 1, cv2.LINE_AA)

    return frame, total, counts

# ─────────────────────────────────────────────
# MODE 1: IMAGE
# ─────────────────────────────────────────────
def detect_image():
    path = input("\n  Enter image path (or drag & drop): ").strip().strip('"')
    if not os.path.exists(path):
        print(f"  ERROR: File not found: {path}"); return

    print("  Detecting...")
    frame   = cv2.imread(path)
    results = model(frame, verbose=False)
    frame, total, counts = draw_detections(frame, results)

    out_path = os.path.join(OUTPUT_FOLDER, "result_" + os.path.basename(path))
    cv2.imwrite(out_path, frame)

    print(f"\n  Found {total} pothole(s)")
    print(f"  HIGH:{counts['HIGH']}  MEDIUM:{counts['MEDIUM']}  LOW:{counts['LOW']}")
    print(f"  Saved to: {out_path}")
    print("  Press any key to close...")

    try:
        print("\n  💡 TIP: Make sure to click on the actual pop-up image window before pressing a key to close it!")
        cv2.imshow("Pothole Detection - Group 4", frame)
        cv2.waitKey(0)
    except Exception:
        pass
    finally:
        cv2.destroyAllWindows()
        cv2.waitKey(1)

# ─────────────────────────────────────────────
# MODE 2: VIDEO
# ─────────────────────────────────────────────
def detect_video():
    path = input("\n  Enter video path (or drag & drop): ").strip().strip('"')
    if not os.path.exists(path):
        print(f"  ERROR: File not found: {path}"); return

    cap      = cv2.VideoCapture(path)
    w        = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    h        = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps      = cap.get(cv2.CAP_PROP_FPS)
    out_path = os.path.join(OUTPUT_FOLDER, "result_" + os.path.basename(path))
    writer   = cv2.VideoWriter(out_path, cv2.VideoWriter_fourcc(*"mp4v"), fps, (w, h))

    print("  Processing video... (press Q to stop)")
    last_alert = 0

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret: break

        results = model(frame, verbose=False)
        frame, total, counts = draw_detections(frame, results)
        writer.write(frame)

        now = time.time()
        if total > 0 and (now - last_alert) > 3:
            sev = "HIGH" if counts["HIGH"] > 0 else "MEDIUM" if counts["MEDIUM"] > 0 else "LOW"
            threading.Thread(target=play_alert, args=(sev,), daemon=True).start()
            last_alert = now

        try:
            cv2.imshow("Pothole Detection - Group 4 (Q to stop)", frame)
            if cv2.waitKey(1) & 0xFF == ord('q'): break
        except:
            break

    cap.release()
    writer.release()
    cv2.destroyAllWindows()
    print(f"\n  Done! Saved to: {out_path}")

# ─────────────────────────────────────────────
# MODE 3: LIVE WEBCAM + AUTO REPORT
# ─────────────────────────────────────────────
def detect_webcam():
    print("\n  ╔══════════════════════════════════════╗")
    print("  ║   LIVE DETECTION + AUTO REPORT       ║")
    print("  ║   HIGH & MEDIUM → auto sent to PWD   ║")
    print("  ║   Press Q to quit                    ║")
    print("  ╚══════════════════════════════════════╝\n")

    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("  ERROR: Webcam not found!"); return

    last_alert_time   = 0
    last_capture_time = 0
    alert_cooldown    = 4
    capture_cooldown  = 10
    total_sent        = 0

    while True:
        ret, frame = cap.read()
        if not ret: break

        results = model(frame, verbose=False)
        frame, total, counts = draw_detections(frame, results, min_conf=0.75)

        now = time.time()

        if total > 0:
            sev = "HIGH" if counts["HIGH"] > 0 else "MEDIUM" if counts["MEDIUM"] > 0 else "LOW"

            # Audio alert
            if (now - last_alert_time) > alert_cooldown:
                threading.Thread(target=play_alert, args=(sev,), daemon=True).start()
                last_alert_time = now

            # Auto capture + send
            if sev in ("HIGH", "MEDIUM") and (now - last_capture_time) > capture_cooldown:
                total_sent += 1
                print(f"\n  🚨 {sev} — Auto capturing & sending...")
                capture_frame = frame.copy()
                threading.Thread(
                    target=auto_capture_and_send,
                    args=(capture_frame, sev),
                    daemon=True
                ).start()
                last_capture_time = now

            # Alert bar at bottom
            colors = {"HIGH":(0,0,200), "MEDIUM":(0,130,255), "LOW":(30,180,30)}
            texts  = {
                "HIGH":   "⚠ WARNING! HIGH SEVERITY — REPORT SENT!",
                "MEDIUM": "⚠ CAUTION! MEDIUM SEVERITY — REPORT SENT!",
                "LOW":    "ℹ LOW SEVERITY POTHOLE AHEAD"
            }
            h_frame = frame.shape[0]
            color   = colors[sev]
            if int(now * 2) % 2 == 0:
                overlay = frame.copy()
                cv2.rectangle(overlay, (0, h_frame-48), (frame.shape[1], h_frame), color, -1)
                cv2.addWeighted(overlay, 0.8, frame, 0.2, 0, frame)
                cv2.putText(frame, texts[sev], (12, h_frame-16),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.62, (255, 255, 255), 1, cv2.LINE_AA)
        else:
            h_frame = frame.shape[0]
            cv2.putText(frame, "✓ Road Clear", (10, h_frame-14),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.55, (60, 200, 60), 1, cv2.LINE_AA)

        # Reports sent counter (top right)
        label = f"Reports sent: {total_sent}"
        (lw, _), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.48, 1)
        cv2.putText(frame, label, (frame.shape[1]-lw-10, 24),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.48, (200, 200, 200), 1, cv2.LINE_AA)

        try:
            cv2.imshow("LIVE Detection + Auto Report - Group 4  |  Q = Quit", frame)
            if cv2.waitKey(1) & 0xFF == ord('q'): break
        except:
            break

    cap.release()
    try:
        cv2.destroyAllWindows()
    except:
        pass
    print(f"\n  Session ended. Total reports sent: {total_sent}")

# ─────────────────────────────────────────────
# MAIN MENU
# ─────────────────────────────────────────────
def main():
    print("\n====================================")
    print("  POTHOLE DETECTION SYSTEM - GROUP 4")
    print("  College of Engineering, Punnapra")
    print("====================================")
    print("  1 -> Detect in Image")
    print("  2 -> Detect in Video")
    print("  3 -> Live Webcam + Auto Report 🔊📍")
    print("====================================")

    choice = input("  Enter choice (1/2/3): ").strip()
    if   choice == "1": detect_image()
    elif choice == "2": detect_video()
    elif choice == "3": detect_webcam()
    else: print("  Invalid choice! Enter 1, 2 or 3.")

if __name__ == "__main__":
    main()

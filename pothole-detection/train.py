"""
================================================
 STEP 2: TRAIN THE MODEL
 Run after merge.py: python train.py
 This will take 20-60 minutes depending on your PC
================================================
"""

from ultralytics import YOLO
import os

BASE      = os.path.dirname(os.path.abspath(__file__))
DATA_YAML = os.path.join(BASE, "dataset_merged", "data.yaml")

print("\n----------------------------------")
print("  TRAINING POTHOLE MODEL - GROUP 4")
print("----------------------------------")
print(f"  Dataset : {DATA_YAML}")
print("  Model   : YOLOv8n (nano - fast)")
print("  Epochs  : 30")
print("\n  This will take 20-60 mins...")
print("  DO NOT close VS Code!")
print("----------------------------------\n")

# Load base YOLOv8 model
model = YOLO("yolov8n.pt")

# Train
results = model.train(
    data    = DATA_YAML,
    epochs  = 30,        # increase to 50 for better accuracy
    imgsz   = 640,
    batch   = 8,         # reduce to 4 if you get memory errors
    name    = "pothole_model",
    exist_ok= True,      # forces overwriting the weights expected by main.py
    patience= 10,
    device  = "cpu",     # uses CPU (safe for all laptops)
)

print("\n----------------------------------")
print("  TRAINING COMPLETE!")
print("  Your model is saved at:")
print("  runs/detect/pothole_model/weights/best.pt")
print("\n  Now run: python detect.py")
print("----------------------------------\n")

"""
================================================
 STEP 1: MERGE DATASETS
 Run this first: python merge.py
================================================
"""

import os
import shutil

BASE   = os.path.dirname(os.path.abspath(__file__))
DS1    = os.path.join(BASE, "dataset1")
DS2    = os.path.join(BASE, "dataset2")
MERGED = os.path.join(BASE, "dataset_merged")

if os.path.exists(MERGED):
    shutil.rmtree(MERGED)
SPLITS = ["train", "valid", "test"]

def copy_files(src_folder, dst_folder, prefix):
    os.makedirs(dst_folder, exist_ok=True)
    if not os.path.exists(src_folder):
        return 0
    count = 0
    for f in os.listdir(src_folder):
        src = os.path.join(src_folder, f)
        name, ext = os.path.splitext(f)
        dst = os.path.join(dst_folder, f"{prefix}_{name}{ext}")
        shutil.copy2(src, dst)
        count += 1
    return count

print("\n----------------------------------")
print("  MERGING DATASETS - GROUP 4")
print("----------------------------------\n")

total = 0
for split in SPLITS:
    for sub in ["images", "labels"]:
        src1 = os.path.join(DS1, split, sub)
        src2 = os.path.join(DS2, split, sub)
        dst  = os.path.join(MERGED, split, sub)
        n1 = copy_files(src1, dst, "ds1")
        n2 = copy_files(src2, dst, "ds2")
        total += n1 + n2
        print(f"  {split}/{sub}: {n1} + {n2} = {n1+n2} files")

# Write data.yaml with forward slashes (works on Windows too)
merged_path = MERGED.replace("\\", "/")
yaml_content = f"""train: {merged_path}/train/images
val:   {merged_path}/valid/images
test:  {merged_path}/test/images

nc: 1
names: ['pothole']
"""

yaml_path = os.path.join(MERGED, "data.yaml")
with open(yaml_path, "w") as f:
    f.write(yaml_content)

print(f"\n  Total files : {total}")
print(f"  data.yaml   : {yaml_path}")
print("\n  DONE! Now run: python train.py")
print("----------------------------------\n")

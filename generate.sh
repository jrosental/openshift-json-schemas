#!/bin/bash
set -euo pipefail

# --- CONFIGURATION ---
VERSION_LONG="4.21.5"
VERSION_SHORT="4.21"
SPEC_FILE="openapi/openshift-openapi-spec-v4.21.json"

echo "🚀 Starting..."
# Initial cleaning
rm -rf "v${VERSION_LONG}-"* "v${VERSION_SHORT}-"*

# 1. MINIMAL PATCHING (Just to ensure that JSON is valid)
python3 - <<EOF
import json
with open('$SPEC_FILE', 'r') as f:
    data = json.load(f)
for k, v in data.get('definitions', {}).items():
    if not isinstance(v, dict): continue
    if 'properties' not in v: v['properties'] = {}
with open('$SPEC_FILE.patched', 'w') as f:
    json.dump(data, f)
EOF

# 2. GENERATION FUNCTION
generate_variant() {
    local suffix=$1
    local flags=$2
    local out_dir="v${VERSION_LONG}-${suffix}"
    
    echo "📦 Generating files for: $suffix..."
    openapi2jsonschema "$SPEC_FILE.patched" -o "$out_dir" $flags

    echo "📂 Rename and organize files..."
    python3 - <<EOF
import os, json, shutil
d = "$out_dir"
if not os.path.exists(d): exit(0)
tmp_d = d + "_tmp"
os.makedirs(tmp_d, exist_ok=True)

for f in os.listdir(d):
    if not f.endswith('.json') or f == '_definitions.json': continue
    path = os.path.join(d, f)
    try:
        with open(path, 'r') as file:
            data = json.load(file)
        
        # We read the Kind and Group directly from inside the JSON
        gvk_list = data.get('x-kubernetes-group-version-kind', [])
        if gvk_list:
            gvk = gvk_list[0]
            kind = gvk.get('kind', '').lower()
            group = gvk.get('group', '').lower()
        else:
            # If it isn't a K8S object, we use the original clean name
            kind = f.replace('.json', '').split('.')[-1].lower()
            group = ""

        if not kind: continue

        # Name compatible with Kubeconform: kind-group.json o kind.json
        new_name = f"{kind}-{group}.json" if group else f"{kind}.json"
        
        # Avoid duplicates if the group is the same
        dest = os.path.join(tmp_d, new_name)
        if not os.path.exists(dest):
            shutil.move(path, dest)
    except:
        continue

shutil.rmtree(d)
os.rename(tmp_d, d)
EOF
}

# 3. RUNNING ALL VARIANTS
# Note: We drop --expanded so that it's more stable and fast. 
# --stand-alone is what's really needed by Kubeconform.
generate_variant "standalone" "--stand-alone"
generate_variant "standalone-strict" "--stand-alone --strict"
generate_variant "local" ""

# 4. CREATE BASE DIRECTORIES.
echo "📂 Creating version base directories..."

# v4.21.5 (Base)
mkdir -p "v${VERSION_LONG}"
cp -r "v${VERSION_LONG}-standalone"/. "v${VERSION_LONG}/"

mkdir -p "v${VERSION_SHORT}"
cp -r "v${VERSION_LONG}/." "v${VERSION_SHORT}/"

mkdir -p "v${VERSION_SHORT}-standalone"
cp -r "v${VERSION_LONG}-standalone/." "v${VERSION_SHORT}-standalone/"

mkdir -p "v${VERSION_SHORT}-standalone-strict"
cp -r "v${VERSION_LONG}-standalone-strict/." "v${VERSION_SHORT}-standalone-strict/"

mkdir -p "v${VERSION_SHORT}-local"
cp -r "v${VERSION_LONG}-local/." "v${VERSION_SHORT}-local/"

rm "$SPEC_FILE.patched"
echo "✅ DONE! Skeleton generated successfully."

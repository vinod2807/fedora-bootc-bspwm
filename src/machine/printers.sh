#!/usr/bin/env bash
# Recreate CUPS print queues. Run as root, after cupsd (and for Konica,
# legacy-printer-app/PAPPL) are available.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Epson L3260 (network IPP) ----------------------------------------------
lpadmin -p epson-l3260 -E \
  -v "ipp://192.168.1.19:631/ipp/print" \
  -P "$DIR/ppd/epson-l3260.ppd" \
  -D "Epson L3260"
echo "epson-l3260 created"

# --- Konica 206i (via PAPPL on localhost:8000) -------------------------------
systemctl try-restart legacy-printer-app.service 2>/dev/null || true
sleep 3
for q in konica206uri konica206uri-ppd; do
  lpadmin -p "$q" -E \
    -v "ipp://localhost:8000/ipp/print/konica206uri" \
    -P "$DIR/ppd/$q.ppd" && echo "$q created" || echo "WARN: $q failed (is legacy-printer-app running?)"
done

# --- default queue ------------------------------------------------------------
if [ -s "$DIR/default.txt" ]; then
  lpadmin -d "$(cat "$DIR/default.txt")" && echo "default: $(cat "$DIR/default.txt")"
fi

# --- resume queues ------------------------------------------------------------
for p in $(lpstat -e); do cupsenable "$p" 2>/dev/null || true; cupsaccept "$p" 2>/dev/null || true; done

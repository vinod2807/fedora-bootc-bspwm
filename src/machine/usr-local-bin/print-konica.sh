#!/bin/bash
# print-konica.sh — rofi PDF print launcher for the Konica Minolta 206i.
# Lists PDFs in ~/Downloads (latest first), then prompts for duplex,
# orientation, and page range before printing via pdftops -> lp.
set -u

PRINTER="konica206uri"
DIR="${1:-$HOME/Downloads}"

pick() {
  local prompt="$1"
  shift
  rofi -dmenu -p "$prompt" "$@"
}

die() {
  notify-send -u critical "Konica print" "$1" 2>/dev/null
  exit 1
}

# --- 1. pick file (latest first) ------------------------------------------
declare -A name_map
display_names=()
while IFS= read -r f; do
  [ -z "$f" ] && continue
  base=$(basename "$f")
  name_map["$base"]="$f"
  display_names+=("$base")
done < <(find "$DIR" -maxdepth 1 -type f -iname '*.pdf' -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)
if [ "${#display_names[@]}" -eq 0 ]; then
  die "No PDF files found in $DIR"
fi

sel=$(printf '%s\n' "${display_names[@]}" | pick "Select PDF to print" -i)
[ -n "$sel" ] || exit 0

file="${name_map[$sel]:-}"
[ -n "$file" ] || die "Could not resolve selected file"

# --- 2. page count ----------------------------------------------------------
total=$(pdfinfo "$file" 2>/dev/null | awk '/^Pages:/ {print $2}')
if [ -z "$total" ] || [ "$total" -lt 1 ] 2>/dev/null; then
  die "Could not read page count for $(basename "$file")"
fi

# --- 3. duplex --------------------------------------------------------------
duplex=$(printf '%s\n' "Simplex" "Duplex Long Edge" "Duplex Short Edge" | pick "Duplex (Total: $total pages)")
[ -n "$duplex" ] || exit 0
case "$duplex" in
  "Simplex")            sides="one-sided" ;;
  "Duplex Long Edge")   sides="two-sided-long-edge" ;;
  "Duplex Short Edge")  sides="two-sided-short-edge" ;;
  *) die "Invalid duplex option" ;;
esac

# --- 4. orientation ----------------------------------------------------------
orient=$(printf '%s\n' "Auto" "Portrait" "Landscape" | pick "Orientation")
[ -n "$orient" ] || exit 0
case "$orient" in
  "Auto")      orient_opt="" ;;
  "Portrait")  orient_opt="-o orientation-requested=3" ;;
  "Landscape") orient_opt="-o orientation-requested=4" ;;
  *) die "Invalid orientation option" ;;
esac

# --- 5. page size --------------------------------------------------------------
detected_size=$(pdfinfo "$file" 2>/dev/null | awk '/^Page size:/ {for (i=3;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/[[:space:]]*$//')
page_size=$(printf '%s\n' "A4" "A3" | pick "Page size (detected: ${detected_size:-unknown})")
[ -n "$page_size" ] || exit 0
case "$page_size" in
  "A4") media="iso_a4_210x297mm" ;;
  "A3") media="iso_a3_297x420mm" ;;
  *) die "Invalid page size" ;;
esac

# --- 6. page range -----------------------------------------------------------
range_pick=$(printf '%s\n' "All pages" "Custom range" | pick "Pages (Total: $total)")
[ -n "$range_pick" ] || exit 0

pages=()
if [ "$range_pick" = "Custom range" ]; then
  from=$(pick "From page (1-$total)")
  [ -n "$from" ] || exit 0
  if ! [[ "$from" =~ ^[0-9]+$ ]] || [ "$from" -lt 1 ] || [ "$from" -gt "$total" ]; then
    die "Invalid From page: $from (must be 1-$total)"
  fi
  to=$(pick "To page ($from-$total)")
  [ -n "$to" ] || exit 0
  if ! [[ "$to" =~ ^[0-9]+$ ]] || [ "$to" -lt "$from" ] || [ "$to" -gt "$total" ]; then
    die "Invalid To page: $to (must be $from-$total)"
  fi
  pages=(-f "$from" -l "$to")
  range="$from-$to"
else
  range="All"
fi

# --- 7. confirm ---------------------------------------------------------------
echo "=== PRINT SUMMARY ==="
echo "File    : $file"
echo "Pages   : $range (total $total)"
echo "Duplex  : $duplex"
echo "Orient  : $orient"
echo "PageSize: $page_size"
if ! printf 'Yes\nNo\n' | pick "Confirm print? $range / $duplex / $orient / $page_size" | grep -qx Yes; then
  exit 0
fi

# --- 8. print ----------------------------------------------------------------
notify-send "Konica print" "Sending $(basename "$file") ($range, $duplex, $orient, $page_size)..." 2>/dev/null

if pdftops "${pages[@]}" "$file" - 2>/dev/null | lp -d "$PRINTER" -o sides="$sides" -o media="$media" $orient_opt; then
  notify-send "Konica print" "Job sent: $(basename "$file")" 2>/dev/null
else
  die "Print failed for $(basename "$file")"
fi
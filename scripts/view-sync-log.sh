#!/data/data/com.termux/files/usr/bin/bash

LOGDIR="$HOME/sync-logs"

if [ ! -d "$LOGDIR" ] || [ -z "$(ls -A "$LOGDIR" 2>/dev/null)" ]; then
  echo "No logs found — run the sync at least once."
  echo ""
  echo "Press Enter to close…"
  read -r
  exit 0
fi

mapfile -t LOGS < <(ls -1t "$LOGDIR"/sync-*.log)

echo "Available sync logs:"
echo ""
for i in "${!LOGS[@]}"; do
  printf "  %2d) %s\n" "$((i+1))" "$(basename "${LOGS[$i]}")"
done

echo ""
read -rp "Pick a number (Enter = most recent): " choice

if [ -z "$choice" ]; then
  choice=1
fi

INDEX=$((choice-1))

if [ -z "${LOGS[$INDEX]}" ]; then
  echo "Invalid choice."
else
  echo ""
  echo "────────────────────────────────"
  cat "${LOGS[$INDEX]}"
fi

echo ""
echo "────────────────────────────────"
echo "Press Enter to close…"
read -r

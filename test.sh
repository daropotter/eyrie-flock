#!/usr/bin/env bash
set -euo pipefail

if ! command -v dialog >/dev/null 2>&1; then
  echo "Brakuje programu: dialog"
  echo "Debian/Ubuntu: sudo apt install dialog"
  exit 1
fi

selected=$(
  dialog \
    --clear \
    --title "Konfiguracja" \
    --separate-output \
    --checklist "Wybierz komponenty do instalacji:" \
    18 70 8 \
    docker   "Docker"          off \
    nginx    "Nginx"           on \
    postgres "PostgreSQL"      off \
    redis    "Redis"           off \
    node     "Node.js"         on \
    3>&1 1>&2 2>&3
)

clear

mapfile -t choices <<< "$selected"

echo "Wybrano:"
for choice in "${choices[@]}"; do
  echo "- $choice"
done

for choice in "${choices[@]}"; do
  case "$choice" in
    docker)
      echo "Instaluję Docker..."
      ;;
    nginx)
      echo "Instaluję Nginx..."
      ;;
    postgres)
      echo "Instaluję PostgreSQL..."
      ;;
    redis)
      echo "Instaluję Redis..."
      ;;
    node)
      echo "Instaluję Node.js..."
      ;;
  esac
done

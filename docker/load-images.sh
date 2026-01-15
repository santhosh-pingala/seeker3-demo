#!/usr/bin/env bash
set -e

cd "$(dirname "$0")"

if [ ! -d images ]; then
  echo "❌ images directory not found"
  exit 1
fi

for zipfile in images/*.zip; do
  if [ ! -f "$zipfile" ]; then
    echo "❌ No zip files found in images/"
    exit 1
  fi

  echo "➡ Extracting: $zipfile"
  unzip -o "$zipfile" -d images/

  # Get the tar filename from the zip
  tarfile="${zipfile%.zip}.tar"

  echo "➡ Loading: $tarfile"
  docker load -i "$tarfile"

  # Clean up tar file after loading
  rm "$tarfile"
  echo ""
done

echo "✅ All images loaded successfully"

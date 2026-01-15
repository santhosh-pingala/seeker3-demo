#!/usr/bin/env bash
set -e

cd "$(dirname "$0")"

if [ ! -d images ]; then
  unzip images.zip -d images
fi

for img in images/*.tar; do
  echo "Loading Docker image: $img"
  docker load -i "$img"
done

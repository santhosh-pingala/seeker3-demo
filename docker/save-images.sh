#!/usr/bin/env bash
set -e

cd "$(dirname "$0")/.."

echo "==============================="
echo " Docker Image Export Script"
echo "==============================="

# Extract image names from docker-compose.yml
IMAGES=$(grep -E '^\s+image:' docker-compose.yml | awk '{print $2}')

if [ -z "$IMAGES" ]; then
  echo "❌ No images found in docker-compose.yml"
  exit 1
fi

echo "Found images:"
echo "$IMAGES"
echo ""

# Create directory for zip files
IMAGES_DIR="docker/images"
rm -rf "$IMAGES_DIR"
mkdir -p "$IMAGES_DIR"

# Pull, save, and zip each image separately
for IMAGE in $IMAGES; do
  echo "➡ Pulling: $IMAGE"
  docker pull "$IMAGE"

  # Create safe filename from image name
  FILENAME=$(echo "$IMAGE" | tr '/:' '_')
  TAR_PATH="$IMAGES_DIR/${FILENAME}.tar"
  ZIP_PATH="$IMAGES_DIR/${FILENAME}.zip"

  echo "➡ Saving: $IMAGE -> $TAR_PATH"
  docker save -o "$TAR_PATH" "$IMAGE"

  echo "➡ Zipping: $TAR_PATH -> $ZIP_PATH"
  zip -j "$ZIP_PATH" "$TAR_PATH"
  rm "$TAR_PATH"

  echo ""
done

echo "✅ Done! Images saved to $IMAGES_DIR/"
echo ""
echo "Created zip files:"
ls -lh "$IMAGES_DIR"


#!/usr/bin/env bash
set -e

echo "==============================="
echo " Demo Setup & Launch Script"
echo "==============================="

BASE_DIR="./"
REPO_URL="https://github.com/santhosh-pingala/seeker3-demo.git"
REPO_DIR="$BASE_DIR/demo-repo"

# mkdir -p "$BASE_DIR"
# cd "$BASE_DIR"

echo "➡ Verifying environment..."
./check-or-install.sh

echo "➡ Cloning or updating repository..."
if [ ! -d "$REPO_DIR/.git" ]; then
    git clone "$REPO_URL"
else
    cd "$REPO_DIR"
    git pull 
fi

cd "$REPO_DIR"

echo "➡ Loading Docker images..."
./docker/load-images.sh

echo "➡ Starting application..."
./app/start.sh

echo "✅ Demo application is ready!"

#!/usr/bin/env bash
set -e

echo "Checking Docker installation..."

if ! command -v docker >/dev/null 2>&1; then
  echo "❌ Docker is not installed. Please contact administrator."
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "❌ Docker Compose plugin is missing."
  echo "Please install docker-compose-plugin."
  exit 1
fi

echo "✅ Docker and Docker Compose plugin are available"

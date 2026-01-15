# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Docker-based demo setup for the Seeker3 gate security system. The repository contains shell scripts to set up and run a multi-service application using Docker Compose.

## Commands

### Check Prerequisites
```bash
./check-or-install.sh
```
Verifies Docker and Docker Compose plugin are installed.

### Run the Demo
```bash
./run-demo.sh
```
Full setup: verifies environment, clones/updates repo, loads Docker images, and starts the application.

### Save Docker Images for Offline Use
```bash
./docker/save-images.sh
```
Pulls all images from docker-compose.yml and packages them into `docker/images.zip`. Run this when docker-compose.yml is updated.

### Load Docker Images
```bash
./docker/load-images.sh
```
Extracts and loads Docker images from `docker/images.zip`.

### Start Services with Docker Compose
```bash
docker compose up -d
```

### Stop Services
```bash
docker compose down
```

## Architecture

The system consists of four services orchestrated via Docker Compose:

- **gateway-service** (port 8081): Main business logic service with optional face recognition and fingerprint ML service integrations
- **auth-service** (port 8080 HTTP, port 50051 gRPC): Authentication and authorization using JWT
- **postgres** (port 5432): PostgreSQL 16 with pgvector extension for the `gate_security` database
- **redis** (port 6380 on host): Cache and message broker

All services depend on healthy postgres/redis before starting and include health checks.

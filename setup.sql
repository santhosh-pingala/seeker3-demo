-- Complete Database Setup for Gateway Service and Auth Service
-- Run this file once to set up the complete database schema for both services
-- Usage: docker exec -i postgres-gateway psql -U postgres -d gate_security < setup.sql

-- ============================================================================
-- STEP 1: Enable Extensions
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS vector;  -- pgvector for embeddings (extension name is 'vector')
CREATE EXTENSION IF NOT EXISTS "pg_trgm";  -- For fuzzy text search
CREATE EXTENSION IF NOT EXISTS "pgcrypto";  -- For encryption

-- ============================================================================
-- STEP 2: Core Tables
-- ============================================================================

-- Persons table (core)
CREATE TABLE IF NOT EXISTS persons (
    id VARCHAR(255) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    phone VARCHAR(50) NOT NULL,
    id_type VARCHAR(50),
    id_number VARCHAR(100),
    person_type VARCHAR(50) NOT NULL CHECK (person_type IN ('resident', 'visitor')),
    thumbnail_url TEXT,
    version BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    -- Extended registration fields
    first_name VARCHAR(255),
    last_name VARCHAR(255),
    alias VARCHAR(255),
    gender VARCHAR(20) CHECK (gender IN ('MALE', 'FEMALE', 'OTHER')),
    contact_number VARCHAR(50),
    age INT,
    date_of_birth DATE,
    religion VARCHAR(100),
    id_proof_type VARCHAR(50) CHECK (id_proof_type IN ('AADHAR', 'PAN', 'DL', 'VOTER_ID', 'PASSPORT')),
    id_proof_number VARCHAR(100),
    person_category VARCHAR(50) CHECK (person_category IN ('RESIDENT', 'VISITOR', 'STAFF', 'GUEST')),
    village_id VARCHAR(255),
    address TEXT,
    email VARCHAR(255),
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'deactivated')),
    last_verified_at TIMESTAMP
);

-- Villages table
CREATE TABLE IF NOT EXISTS villages (
    id VARCHAR(255) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Nodes table (intermediate level: Village → Node → Device)
CREATE TABLE IF NOT EXISTS nodes (
    id VARCHAR(255) PRIMARY KEY,
    village_id VARCHAR(255) NOT NULL REFERENCES villages(id),
    node_name VARCHAR(255) NOT NULL,
    node_type VARCHAR(50),  -- e.g., "gate", "checkpoint", "entrance", etc.
    location_description TEXT,  -- Optional: physical location description
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Devices table (for gate access tracking and device authentication)
-- Hierarchy: Village → Node → Device (for gateway service)
-- Can also be used for auth service device authentication (node_id can be NULL)
CREATE TABLE IF NOT EXISTS devices (
    id VARCHAR(255) PRIMARY KEY,
    node_id VARCHAR(255) REFERENCES nodes(id),  -- Device belongs to a node (optional - NULL for auth service devices)
    device_name VARCHAR(255) NOT NULL,
    device_type VARCHAR(50) NOT NULL CHECK (device_type IN ('mobile', 'tablet', 'admin', 'gate')),
    cert_fingerprint VARCHAR(255),  -- Certificate fingerprint for mTLS (unique for auth service)
    is_active BOOLEAN NOT NULL DEFAULT true,
    operator_name VARCHAR(255),  -- Name of operator/guard using the device
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMP,  -- Last time device was active
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Make node_id nullable if table already exists with NOT NULL constraint
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'devices' 
        AND column_name = 'node_id' 
        AND is_nullable = 'NO'
    ) THEN
        ALTER TABLE devices ALTER COLUMN node_id DROP NOT NULL;
    END IF;
END $$;

-- Indexes for nodes table
CREATE INDEX IF NOT EXISTS idx_nodes_village_id ON nodes(village_id);
CREATE INDEX IF NOT EXISTS idx_nodes_is_active ON nodes(is_active) WHERE is_active = true;

-- Indexes for devices table
CREATE INDEX IF NOT EXISTS idx_devices_node_id ON devices(node_id) WHERE node_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_devices_is_active ON devices(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_devices_device_type ON devices(device_type);
CREATE INDEX IF NOT EXISTS idx_devices_last_seen_at ON devices(last_seen_at DESC);
CREATE INDEX IF NOT EXISTS idx_devices_cert_fingerprint ON devices(cert_fingerprint) WHERE cert_fingerprint IS NOT NULL;
-- Unique constraint for cert_fingerprint (for auth service)
CREATE UNIQUE INDEX IF NOT EXISTS idx_devices_cert_fingerprint_unique ON devices(cert_fingerprint) WHERE cert_fingerprint IS NOT NULL;

-- Face embeddings table (with pgvector)
CREATE TABLE IF NOT EXISTS person_face_embeddings (
    id VARCHAR(255) PRIMARY KEY,
    person_id VARCHAR(255) REFERENCES persons(id) ON DELETE CASCADE,
    embedding vector(512) NOT NULL,
    photo_id VARCHAR(255),
    quality_score FLOAT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    is_deleted BOOLEAN NOT NULL DEFAULT false
);

-- Fingerprint templates table
CREATE TABLE IF NOT EXISTS person_fingerprint_templates (
    id VARCHAR(255) PRIMARY KEY,
    person_id VARCHAR(255) REFERENCES persons(id) ON DELETE CASCADE,
    template BYTEA NOT NULL,
    finger_position VARCHAR(50),
    quality_score FLOAT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    is_deleted BOOLEAN NOT NULL DEFAULT false
);

-- Person photos table
CREATE TABLE IF NOT EXISTS person_photos (
    id VARCHAR(255) PRIMARY KEY,
    person_id VARCHAR(255) REFERENCES persons(id) ON DELETE CASCADE,
    photo_url TEXT NOT NULL,
    photo_type VARCHAR(50) NOT NULL CHECK (photo_type IN ('front', 'side', 'back', 'other')),
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Entry logs table
CREATE TABLE IF NOT EXISTS entry_logs (
    id VARCHAR(255) PRIMARY KEY,
    request_id VARCHAR(255) UNIQUE,  -- For idempotency (unique constraint)
    person_id VARCHAR(255) NOT NULL REFERENCES persons(id),
    person_name VARCHAR(255),  -- Denormalized for performance
    device_id VARCHAR(255) NOT NULL,
    biometric_method VARCHAR(50) NOT NULL CHECK (biometric_method IN ('face', 'fingerprint', 'manual')),
    match_type VARCHAR(50) NOT NULL CHECK (match_type IN ('mobile_auto', 'server_confirm', 'manual')),
    direction VARCHAR(10) NOT NULL CHECK (direction IN ('in', 'out')),
    confidence_score FLOAT DEFAULT 0.0,
    timestamp TIMESTAMP NOT NULL,
    image_url TEXT,  -- Optional: captured image URL
    remarks TEXT,  -- Optional: general remarks/notes
    -- Vehicle details (optional)
    vehicle_type VARCHAR(50),  -- e.g., "CAR", "BIKE", "TRUCK", "AUTO", etc.
    vehicle_number VARCHAR(50),  -- Vehicle registration number
    vehicle_make_model VARCHAR(255),  -- Vehicle make and model
    vehicle_remarks TEXT,  -- Optional: vehicle-specific remarks
    is_synced BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Indexes for entry_logs table
CREATE INDEX IF NOT EXISTS idx_entry_logs_person_id ON entry_logs(person_id);
CREATE INDEX IF NOT EXISTS idx_entry_logs_device_id ON entry_logs(device_id);
CREATE INDEX IF NOT EXISTS idx_entry_logs_timestamp ON entry_logs(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_entry_logs_request_id ON entry_logs(request_id) WHERE request_id IS NOT NULL;
-- Composite indexes for query performance
CREATE INDEX IF NOT EXISTS idx_entry_logs_timestamp_id ON entry_logs(timestamp DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_entry_logs_biometric_method ON entry_logs(biometric_method);
CREATE INDEX IF NOT EXISTS idx_entry_logs_direction ON entry_logs(direction);
-- Composite index for common filter combinations
CREATE INDEX IF NOT EXISTS idx_entry_logs_person_timestamp ON entry_logs(person_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_entry_logs_device_timestamp ON entry_logs(device_id, timestamp DESC);

-- Person audit table
CREATE TABLE IF NOT EXISTS person_audit (
    id VARCHAR(255) PRIMARY KEY,
    person_id VARCHAR(255) NOT NULL REFERENCES persons(id) ON DELETE CASCADE,
    action VARCHAR(50) NOT NULL CHECK (action IN ('created', 'updated', 'deleted')),
    changed_fields JSONB,
    changed_by VARCHAR(255),
    old_version BIGINT NOT NULL,
    new_version BIGINT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Extended registration tables
CREATE TABLE IF NOT EXISTS person_social_media (
    id VARCHAR(255) PRIMARY KEY,
    person_id VARCHAR(255) NOT NULL REFERENCES persons(id) ON DELETE CASCADE,
    platform VARCHAR(100) NOT NULL,
    account_id VARCHAR(255) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE(person_id, platform, account_id)
);

CREATE TABLE IF NOT EXISTS person_education (
    id VARCHAR(255) PRIMARY KEY,
    person_id VARCHAR(255) NOT NULL REFERENCES persons(id) ON DELETE CASCADE,
    qualification VARCHAR(255),
    institution VARCHAR(255),
    education_info TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS person_professional (
    id VARCHAR(255) PRIMARY KEY,
    person_id VARCHAR(255) NOT NULL REFERENCES persons(id) ON DELETE CASCADE,
    profession VARCHAR(255),
    profession_description TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS person_relationships (
    id VARCHAR(255) PRIMARY KEY,
    person_id VARCHAR(255) NOT NULL REFERENCES persons(id) ON DELETE CASCADE,
    related_person_id VARCHAR(255) REFERENCES persons(id) ON DELETE SET NULL,
    related_person_name VARCHAR(255),
    relationship_type VARCHAR(50) NOT NULL CHECK (relationship_type IN ('FATHER', 'MOTHER', 'SON', 'DAUGHTER', 'BROTHER', 'SISTER', 'SPOUSE', 'FRIEND', 'OTHER')),
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS person_vehicles (
    id VARCHAR(255) PRIMARY KEY,
    person_id VARCHAR(255) NOT NULL REFERENCES persons(id) ON DELETE CASCADE,
    vehicle_type VARCHAR(50) NOT NULL CHECK (vehicle_type IN ('CAR', 'BIKE', 'SCOOTER', 'TRUCK', 'OTHER')),
    vehicle_number VARCHAR(100) NOT NULL,
    make_model VARCHAR(255),
    remarks TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS person_remarks (
    id VARCHAR(255) PRIMARY KEY,
    person_id VARCHAR(255) NOT NULL REFERENCES persons(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS person_registration_movement (
    id VARCHAR(255) PRIMARY KEY,
    person_id VARCHAR(255) NOT NULL REFERENCES persons(id) ON DELETE CASCADE,
    movement_type VARCHAR(20) NOT NULL CHECK (movement_type IN ('ENTRY', 'EXIT')),
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- Auth Service Tables (User Authentication & Management)
-- ============================================================================

-- Users table (for user authentication and management)
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_number VARCHAR(15) UNIQUE NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    employee_id VARCHAR(50) UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(50) NOT NULL CHECK (role IN ('GUARD', 'ADMIN', 'SUPER_ADMIN', 'VIEWER', 'GUARD_MANAGER')),
    is_active BOOLEAN DEFAULT true NOT NULL,
    password_changed_at TIMESTAMP DEFAULT NOW() NOT NULL,
    password_expires_at TIMESTAMP DEFAULT (NOW() + INTERVAL '90 days') NOT NULL,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP DEFAULT NOW() NOT NULL
);

-- Indexes for users
CREATE INDEX IF NOT EXISTS idx_users_phone_number ON users(phone_number);
CREATE INDEX IF NOT EXISTS idx_users_employee_id ON users(employee_id) WHERE employee_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
CREATE INDEX IF NOT EXISTS idx_users_is_active ON users(is_active);
CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at DESC);

-- User sessions table (for session management)
CREATE TABLE IF NOT EXISTS user_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id VARCHAR(255),
    device_type VARCHAR(50) CHECK (device_type IN ('MOBILE', 'WEB')),
    token_hash VARCHAR(255) UNIQUE NOT NULL,
    refresh_token_hash VARCHAR(255) UNIQUE,
    last_sync_at TIMESTAMP DEFAULT NOW() NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    is_active BOOLEAN DEFAULT true NOT NULL,
    created_at TIMESTAMP DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP DEFAULT NOW() NOT NULL
);

-- Indexes for user_sessions
CREATE INDEX IF NOT EXISTS idx_user_sessions_user_id ON user_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_sessions_token_hash ON user_sessions(token_hash);
CREATE INDEX IF NOT EXISTS idx_user_sessions_refresh_token_hash ON user_sessions(refresh_token_hash) WHERE refresh_token_hash IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_user_sessions_is_active ON user_sessions(is_active);
CREATE INDEX IF NOT EXISTS idx_user_sessions_expires_at ON user_sessions(expires_at);
CREATE INDEX IF NOT EXISTS idx_user_sessions_last_sync_at ON user_sessions(last_sync_at);
CREATE INDEX IF NOT EXISTS idx_user_sessions_device_type ON user_sessions(device_type);
CREATE INDEX IF NOT EXISTS idx_user_sessions_user_active ON user_sessions(user_id, is_active, expires_at);

-- User audit logs table (for audit trail)
CREATE TABLE IF NOT EXISTS user_audit_logs (
    id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    performed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    metadata JSONB,
    ip_address VARCHAR(45),
    device_info TEXT,
    created_at TIMESTAMP DEFAULT NOW() NOT NULL
);

-- Indexes for user_audit_logs
CREATE INDEX IF NOT EXISTS idx_user_audit_logs_user_id ON user_audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_user_audit_logs_performed_by ON user_audit_logs(performed_by);
CREATE INDEX IF NOT EXISTS idx_user_audit_logs_action ON user_audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_user_audit_logs_created_at ON user_audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_audit_logs_user_action ON user_audit_logs(user_id, action, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_audit_logs_metadata ON user_audit_logs USING GIN (metadata);

-- Device audit logs table (for device authentication audit)
CREATE TABLE IF NOT EXISTS auth_audit_logs (
    id SERIAL PRIMARY KEY,
    device_id VARCHAR(255) REFERENCES devices(id),
    action VARCHAR(100) NOT NULL,
    success BOOLEAN NOT NULL,
    error_message TEXT,
    ip_address VARCHAR(45),
    user_agent TEXT,
    timestamp TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Indexes for auth_audit_logs
CREATE INDEX IF NOT EXISTS idx_auth_audit_logs_device_id ON auth_audit_logs(device_id);
CREATE INDEX IF NOT EXISTS idx_auth_audit_logs_timestamp ON auth_audit_logs(timestamp DESC);

-- ============================================================================
-- STEP 3: Indexes for Performance
-- ============================================================================

-- Basic indexes
CREATE INDEX IF NOT EXISTS idx_persons_phone ON persons(phone);
CREATE INDEX IF NOT EXISTS idx_persons_person_type ON persons(person_type);
CREATE INDEX IF NOT EXISTS idx_persons_village_id ON persons(village_id);
CREATE INDEX IF NOT EXISTS idx_persons_status ON persons(status);
CREATE INDEX IF NOT EXISTS idx_persons_created_at ON persons(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_persons_last_verified_at ON persons(last_verified_at DESC);

-- GIN indexes for fuzzy search (pg_trgm)
CREATE INDEX IF NOT EXISTS idx_persons_name_trgm ON persons USING gin (name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_persons_first_name_trgm ON persons USING gin (first_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_persons_last_name_trgm ON persons USING gin (last_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_persons_alias_trgm ON persons USING gin (alias gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_persons_phone_trgm ON persons USING gin (phone gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_persons_contact_number_trgm ON persons USING gin (contact_number gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_persons_id_number_trgm ON persons USING gin (id_number gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_persons_id_proof_number_trgm ON persons USING gin (id_proof_number gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_persons_address_trgm ON persons USING gin (address gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_villages_name_trgm ON villages USING gin (name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_villages_name ON villages(name);

-- Full-text search (tsvector) - using search_vector column name for consistency
ALTER TABLE persons ADD COLUMN IF NOT EXISTS search_vector tsvector;

-- Function to update search_vector on person changes
CREATE OR REPLACE FUNCTION persons_search_vector_update() RETURNS TRIGGER AS $$
BEGIN
    NEW.search_vector :=
        setweight(to_tsvector('english', COALESCE(NEW.first_name, '') || ' ' || COALESCE(NEW.last_name, '') || ' ' || COALESCE(NEW.name, '')), 'A') ||
        setweight(to_tsvector('english', COALESCE(NEW.alias, '')), 'B') ||
        setweight(to_tsvector('english', COALESCE(NEW.contact_number, '') || ' ' || COALESCE(NEW.phone, '')), 'B') ||
        setweight(to_tsvector('english', COALESCE(NEW.id_proof_number, '') || ' ' || COALESCE(NEW.id_number, '')), 'C') ||
        setweight(to_tsvector('english', COALESCE(NEW.address, '')), 'C');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS persons_search_vector_trigger ON persons;
CREATE TRIGGER persons_search_vector_trigger
    BEFORE INSERT OR UPDATE ON persons
    FOR EACH ROW
    EXECUTE FUNCTION persons_search_vector_update();

-- Update existing rows
UPDATE persons SET search_vector =
    setweight(to_tsvector('english', COALESCE(first_name, '') || ' ' || COALESCE(last_name, '') || ' ' || COALESCE(name, '')), 'A') ||
    setweight(to_tsvector('english', COALESCE(alias, '')), 'B') ||
    setweight(to_tsvector('english', COALESCE(contact_number, '') || ' ' || COALESCE(phone, '')), 'B') ||
    setweight(to_tsvector('english', COALESCE(id_proof_number, '') || ' ' || COALESCE(id_number, '')), 'C') ||
    setweight(to_tsvector('english', COALESCE(address, '')), 'C');

CREATE INDEX IF NOT EXISTS idx_persons_search_vector ON persons USING gin (search_vector);

-- Other indexes
CREATE INDEX IF NOT EXISTS idx_person_face_embeddings_person_id ON person_face_embeddings(person_id);
CREATE INDEX IF NOT EXISTS idx_person_fingerprint_templates_person_id ON person_fingerprint_templates(person_id);
CREATE INDEX IF NOT EXISTS idx_person_photos_person_id ON person_photos(person_id);
CREATE INDEX IF NOT EXISTS idx_entry_logs_person_id ON entry_logs(person_id);
CREATE INDEX IF NOT EXISTS idx_entry_logs_timestamp ON entry_logs(timestamp);
CREATE INDEX IF NOT EXISTS idx_entry_logs_is_synced ON entry_logs(is_synced);
CREATE INDEX IF NOT EXISTS idx_person_audit_person_id ON person_audit(person_id);
CREATE INDEX IF NOT EXISTS idx_person_audit_created_at ON person_audit(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_person_social_media_person_id ON person_social_media(person_id);
CREATE INDEX IF NOT EXISTS idx_person_education_person_id ON person_education(person_id);
CREATE INDEX IF NOT EXISTS idx_person_professional_person_id ON person_professional(person_id);
CREATE INDEX IF NOT EXISTS idx_person_relationships_person_id ON person_relationships(person_id);
CREATE INDEX IF NOT EXISTS idx_person_vehicles_person_id ON person_vehicles(person_id);
CREATE INDEX IF NOT EXISTS idx_person_remarks_person_id ON person_remarks(person_id);

-- ============================================================================
-- STEP 4: Triggers and Functions
-- ============================================================================

-- Function to increment version on update
CREATE OR REPLACE FUNCTION increment_person_version()
RETURNS TRIGGER AS $$
BEGIN
    NEW.version = OLD.version + 1;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Trigger to auto-increment version on person update
DROP TRIGGER IF EXISTS increment_persons_version ON persons;
CREATE TRIGGER increment_persons_version BEFORE UPDATE ON persons
    FOR EACH ROW EXECUTE FUNCTION increment_person_version();

-- Function to update updated_at timestamp (for devices and villages)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Trigger for devices table
DROP TRIGGER IF EXISTS update_devices_updated_at ON devices;
CREATE TRIGGER update_devices_updated_at BEFORE UPDATE ON devices
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Trigger for villages table
DROP TRIGGER IF EXISTS update_villages_updated_at ON villages;
CREATE TRIGGER update_villages_updated_at BEFORE UPDATE ON villages
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function to update users.updated_at
CREATE OR REPLACE FUNCTION update_users_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for users.updated_at
DROP TRIGGER IF EXISTS trigger_update_users_updated_at ON users;
CREATE TRIGGER trigger_update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_users_updated_at();

-- Function to update user_sessions.updated_at
CREATE OR REPLACE FUNCTION update_user_sessions_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for user_sessions.updated_at
DROP TRIGGER IF EXISTS trigger_update_user_sessions_updated_at ON user_sessions;
CREATE TRIGGER trigger_update_user_sessions_updated_at
    BEFORE UPDATE ON user_sessions
    FOR EACH ROW
    EXECUTE FUNCTION update_user_sessions_updated_at();

-- ============================================================================
-- STEP 5: Sample Data (Optional - for testing)
-- ============================================================================

-- Insert dummy villages
INSERT INTO villages (id, name, created_at, updated_at) VALUES
('village-1', 'Poonch', NOW(), NOW()),
('village-2', 'Rajouri', NOW(), NOW()),
('village-3', 'Doda', NOW(), NOW()),
('village-4', 'Udhampur', NOW(), NOW()),
('village-5', 'Baramulla', NOW(), NOW())
ON CONFLICT (id) DO NOTHING;

-- Insert test nodes (for entry log testing)
-- Each village can have multiple nodes
-- Creating nodes for all existing villages to ensure data sync
INSERT INTO nodes (id, village_id, node_name, node_type, location_description, is_active, created_at, updated_at) VALUES
-- Nodes for village-1 (Poonch)
('node-1', 'village-1', 'Main Gate', 'gate', 'Primary entrance to Poonch', true, NOW(), NOW()),
('node-2', 'village-1', 'Back Gate', 'gate', 'Secondary entrance at the rear', true, NOW(), NOW()),
('node-3', 'village-1', 'Checkpoint 1', 'checkpoint', 'Internal checkpoint near residential area', true, NOW(), NOW()),
-- Nodes for village-2 (Rajouri)
('node-4', 'village-2', 'Main Entrance', 'gate', 'Main entrance to Rajouri', true, NOW(), NOW()),
('node-5', 'village-2', 'Side Gate', 'gate', 'Side entrance for vehicles', true, NOW(), NOW()),
('node-6', 'village-2', 'Checkpoint 2', 'checkpoint', 'Internal security checkpoint', true, NOW(), NOW()),
-- Nodes for village-3 (Doda)
('node-7', 'village-3', 'Main Gate', 'gate', 'Primary entrance to Doda', true, NOW(), NOW()),
('node-8', 'village-3', 'North Gate', 'gate', 'Northern entrance point', true, NOW(), NOW()),
-- Nodes for village-4 (Udhampur)
('node-9', 'village-4', 'Main Gate', 'gate', 'Main entrance to Udhampur', true, NOW(), NOW()),
-- Nodes for village-5 (Baramulla)
('node-10', 'village-5', 'Main Gate', 'gate', 'Main entrance to Baramulla', true, NOW(), NOW()),
('node-11', 'village-5', 'East Gate', 'gate', 'Eastern entrance point', true, NOW(), NOW())
ON CONFLICT (id) DO NOTHING;

-- Insert test devices (for entry log testing)
-- Each device belongs to a node, ensuring sync with villages through nodes
INSERT INTO devices (id, node_id, device_name, device_type, is_active, operator_name, created_at, last_seen_at, updated_at) VALUES
-- Devices for node-1 (village-1 Main Gate)
('device-1', 'node-1', 'Main Gate Device', 'gate', true, 'Security Guard 1', NOW(), NOW(), NOW()),
('device-3', 'node-1', 'Mobile Device - Guard 1', 'mobile', true, 'John Smith', NOW(), NOW(), NOW()),
-- Devices for node-2 (village-1 Back Gate)
('device-2', 'node-2', 'Back Gate Device', 'gate', true, 'Security Guard 2', NOW(), NOW(), NOW()),
('device-4', 'node-2', 'Mobile Device - Guard 2', 'mobile', true, 'Jane Doe', NOW(), NOW(), NOW()),
('device-6', 'node-2', 'Inactive Device', 'mobile', false, 'Inactive Guard', NOW(), NOW() - INTERVAL '30 days', NOW()),
-- Devices for node-3 (village-1 Checkpoint 1)
('device-5', 'node-3', 'Admin Tablet', 'tablet', true, 'Admin User', NOW(), NOW(), NOW()),
-- Devices for node-4 (village-2 Main Entrance)
('device-7', 'node-4', 'Main Entrance Device', 'gate', true, 'Security Guard 3', NOW(), NOW(), NOW()),
-- Devices for node-5 (village-2 Side Gate)
('device-8', 'node-5', 'Side Gate Device', 'gate', true, 'Security Guard 4', NOW(), NOW(), NOW()),
-- Devices for node-6 (village-2 Checkpoint 2)
('device-10', 'node-6', 'Checkpoint Device', 'gate', true, 'Security Guard 6', NOW(), NOW(), NOW()),
-- Devices for node-7 (village-3 Main Gate)
('device-9', 'node-7', 'Doda Main Gate', 'gate', true, 'Security Guard 5', NOW(), NOW(), NOW()),
-- Devices for node-8 (village-3 North Gate)
('device-11', 'node-8', 'North Gate Device', 'gate', true, 'Security Guard 7', NOW(), NOW(), NOW()),
-- Devices for node-9 (village-4 Main Gate - Udhampur)
('device-12', 'node-9', 'Udhampur Main Gate', 'gate', true, 'Security Guard 8', NOW(), NOW(), NOW()),
('device-13', 'node-9', 'Mobile Device - Udhampur', 'mobile', true, 'Guard Udhampur', NOW(), NOW(), NOW()),
-- Devices for node-10 (village-5 Main Gate - Baramulla)
('device-14', 'node-10', 'Baramulla Main Gate', 'gate', true, 'Security Guard 9', NOW(), NOW(), NOW()),
('device-15', 'node-10', 'Mobile Device - Baramulla', 'mobile', true, 'Guard Baramulla', NOW(), NOW(), NOW()),
-- Devices for node-11 (village-5 East Gate - Baramulla)
('device-16', 'node-11', 'East Gate Device', 'gate', true, 'Security Guard 10', NOW(), NOW(), NOW())
ON CONFLICT (id) DO UPDATE 
SET node_id = EXCLUDED.node_id,
    device_name = EXCLUDED.device_name,
    device_type = EXCLUDED.device_type,
    is_active = EXCLUDED.is_active,
    operator_name = EXCLUDED.operator_name,
    updated_at = NOW();

-- ============================================================================
-- STEP 5.5: Insert Sample Muslim Persons
-- ============================================================================

-- Insert sample Muslim persons for testing
INSERT INTO persons (
    id,
    name,
    phone,
    first_name,
    last_name,
    person_type,
    gender,
    age,
    religion,
    village_id,
    id_proof_type,
    id_proof_number,
    person_category,
    address,
    status,
    version,
    created_at,
    updated_at
) VALUES
-- Person 1: Ahmed Khan from Poonch
('person-1', 'Ahmed Khan', '+919876543210', 'Ahmed', 'Khan', 'resident', 'MALE', 35, 'ISLAM', 'village-1', 'AADHAR', '1234-5678-9012', 'RESIDENT', 'House No. 45, Main Street, Poonch', 'active', 0, NOW(), NOW()),

-- Person 2: Fatima Sheikh from Rajouri
('person-2', 'Fatima Sheikh', '+919876543211', 'Fatima', 'Sheikh', 'resident', 'FEMALE', 28, 'ISLAM', 'village-2', 'AADHAR', '1234-5678-9013', 'RESIDENT', 'House No. 12, Market Road, Rajouri', 'active', 0, NOW(), NOW()),

-- Person 3: Mohammad Ali from Doda
('person-3', 'Mohammad Ali', '+919876543212', 'Mohammad', 'Ali', 'resident', 'MALE', 42, 'ISLAM', 'village-3', 'AADHAR', '1234-5678-9014', 'RESIDENT', 'House No. 78, Residential Area, Doda', 'active', 0, NOW(), NOW()),

-- Person 4: Ayesha Begum from Udhampur
('person-4', 'Ayesha Begum', '+919876543213', 'Ayesha', 'Begum', 'resident', 'FEMALE', 31, 'ISLAM', 'village-4', 'AADHAR', '1234-5678-9015', 'RESIDENT', 'House No. 23, Colony Street, Udhampur', 'active', 0, NOW(), NOW()),

-- Person 5: Hassan Raza from Baramulla
('person-5', 'Hassan Raza', '+919876543214', 'Hassan', 'Raza', 'resident', 'MALE', 39, 'ISLAM', 'village-5', 'AADHAR', '1234-5678-9016', 'RESIDENT', 'House No. 56, Main Bazaar, Baramulla', 'active', 0, NOW(), NOW()),

-- Person 6: Zainab Hussain from Poonch
('person-6', 'Zainab Hussain', '+919876543215', 'Zainab', 'Hussain', 'resident', 'FEMALE', 26, 'ISLAM', 'village-1', 'AADHAR', '1234-5678-9017', 'RESIDENT', 'House No. 34, New Colony, Poonch', 'active', 0, NOW(), NOW()),

-- Person 7: Ibrahim Malik from Rajouri
('person-7', 'Ibrahim Malik', '+919876543216', 'Ibrahim', 'Malik', 'resident', 'MALE', 45, 'ISLAM', 'village-2', 'AADHAR', '1234-5678-9018', 'RESIDENT', 'House No. 67, Old Town, Rajouri', 'active', 0, NOW(), NOW()),

-- Person 8: Khadija Ansari from Doda
('person-8', 'Khadija Ansari', '+919876543217', 'Khadija', 'Ansari', 'resident', 'FEMALE', 33, 'ISLAM', 'village-3', 'AADHAR', '1234-5678-9019', 'RESIDENT', 'House No. 89, Hill View, Doda', 'active', 0, NOW(), NOW()),

-- Person 9: Yusuf Qureshi from Udhampur
('person-9', 'Yusuf Qureshi', '+919876543218', 'Yusuf', 'Qureshi', 'resident', 'MALE', 37, 'ISLAM', 'village-4', 'AADHAR', '1234-5678-9020', 'RESIDENT', 'House No. 11, Park Street, Udhampur', 'active', 0, NOW(), NOW()),

-- Person 10: Mariam Dar from Baramulla
('person-10', 'Mariam Dar', '+919876543219', 'Mariam', 'Dar', 'resident', 'FEMALE', 29, 'ISLAM', 'village-5', 'AADHAR', '1234-5678-9021', 'RESIDENT', 'House No. 90, River Side, Baramulla', 'active', 0, NOW(), NOW())
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- STEP 5.6: Insert Sample Entry Logs
-- ============================================================================

-- Insert sample entry logs for testing
INSERT INTO entry_logs (
    id,
    request_id,
    person_id,
    person_name,
    device_id,
    biometric_method,
    match_type,
    direction,
    confidence_score,
    timestamp,
    image_url,
    remarks,
    vehicle_type,
    vehicle_number,
    vehicle_make_model,
    is_synced,
    created_at
) VALUES
-- Entry logs for Ahmed Khan (person-1) - Poonch (January 10, 2026)
('entry-1', 'req-001', 'person-1', 'Ahmed Khan', 'device-1', 'face', 'mobile_auto', 'in', 0.95, '2026-01-10 08:30:00.000', 'https://example.com/images/entry-1.jpg', 'Regular entry through main gate', NULL, NULL, NULL, true, '2026-01-10 08:30:00.000'),
('entry-2', 'req-002', 'person-1', 'Ahmed Khan', 'device-1', 'face', 'mobile_auto', 'out', 0.92, '2026-01-10 14:45:00.000', 'https://example.com/images/entry-2.jpg', 'Exit through main gate', 'CAR', 'JK01AB1234', 'Maruti Swift', true, '2026-01-10 14:45:00.000'),

-- Entry logs for Fatima Sheikh (person-2) - Rajouri (village-2) (January 10, 2026)
('entry-3', 'req-003', 'person-2', 'Fatima Sheikh', 'device-7', 'fingerprint', 'server_confirm', 'in', 0.88, '2026-01-10 09:15:00.000', 'https://example.com/images/entry-3.jpg', 'Entry with fingerprint verification at Rajouri main entrance', NULL, NULL, NULL, true, '2026-01-10 09:15:00.000'),
('entry-4', 'req-004', 'person-2', 'Fatima Sheikh', 'device-7', 'fingerprint', 'server_confirm', 'out', 0.90, '2026-01-10 16:20:00.000', 'https://example.com/images/entry-4.jpg', 'Exit verified from Rajouri', NULL, NULL, NULL, true, '2026-01-10 16:20:00.000'),

-- Entry logs for Mohammad Ali (person-3) - Doda (village-3) (January 10, 2026)
('entry-5', 'req-005', 'person-3', 'Mohammad Ali', 'device-9', 'face', 'mobile_auto', 'in', 0.96, '2026-01-10 10:00:00.000', 'https://example.com/images/entry-5.jpg', 'Entry with vehicle at Doda main gate', 'BIKE', 'JK02CD5678', 'Honda Activa', true, '2026-01-10 10:00:00.000'),
('entry-6', 'req-006', 'person-3', 'Mohammad Ali', 'device-9', 'face', 'mobile_auto', 'out', 0.94, '2026-01-10 17:30:00.000', 'https://example.com/images/entry-6.jpg', 'Exit with same vehicle from Doda', 'BIKE', 'JK02CD5678', 'Honda Activa', true, '2026-01-10 17:30:00.000'),

-- Entry logs for Ayesha Begum (person-4) - Udhampur (village-4) (January 11, 2026)
('entry-7', 'req-007', 'person-4', 'Ayesha Begum', 'device-12', 'manual', 'manual', 'in', 0.85, '2026-01-11 07:45:00.000', NULL, 'Manual entry by security guard at Udhampur', NULL, NULL, NULL, true, '2026-01-11 07:45:00.000'),
('entry-8', 'req-008', 'person-4', 'Ayesha Begum', 'device-12', 'face', 'mobile_auto', 'out', 0.91, '2026-01-11 15:10:00.000', 'https://example.com/images/entry-8.jpg', 'Face recognition exit from Udhampur', NULL, NULL, NULL, true, '2026-01-11 15:10:00.000'),

-- Entry logs for Hassan Raza (person-5) - Baramulla (village-5) (January 11, 2026)
('entry-9', 'req-009', 'person-5', 'Hassan Raza', 'device-14', 'face', 'server_confirm', 'in', 0.93, '2026-01-11 08:20:00.000', 'https://example.com/images/entry-9.jpg', 'Server confirmed entry at Baramulla main gate', 'TRUCK', 'JK03EF9012', 'Tata Ace', true, '2026-01-11 08:20:00.000'),
('entry-10', 'req-010', 'person-5', 'Hassan Raza', 'device-14', 'face', 'server_confirm', 'out', 0.89, '2026-01-11 18:00:00.000', 'https://example.com/images/entry-10.jpg', 'Exit with vehicle from Baramulla', 'TRUCK', 'JK03EF9012', 'Tata Ace', true, '2026-01-11 18:00:00.000'),

-- Entry logs for Zainab Hussain (person-6) - Poonch (village-1) (January 11, 2026)
('entry-11', 'req-011', 'person-6', 'Zainab Hussain', 'device-2', 'fingerprint', 'mobile_auto', 'in', 0.87, '2026-01-11 09:30:00.000', 'https://example.com/images/entry-11.jpg', 'Morning entry through Poonch back gate', NULL, NULL, NULL, true, '2026-01-11 09:30:00.000'),
('entry-12', 'req-012', 'person-6', 'Zainab Hussain', 'device-2', 'fingerprint', 'mobile_auto', 'out', 0.90, '2026-01-11 19:15:00.000', 'https://example.com/images/entry-12.jpg', 'Evening exit from Poonch', NULL, NULL, NULL, true, '2026-01-11 19:15:00.000'),

-- Entry logs for Ibrahim Malik (person-7) - Rajouri (village-2) (January 12, 2026)
('entry-13', 'req-013', 'person-7', 'Ibrahim Malik', 'device-10', 'face', 'mobile_auto', 'in', 0.92, '2026-01-12 06:00:00.000', 'https://example.com/images/entry-13.jpg', 'Early morning entry at Rajouri checkpoint', 'AUTO', 'JK04GH3456', 'Bajaj Auto', true, '2026-01-12 06:00:00.000'),
('entry-14', 'req-014', 'person-7', 'Ibrahim Malik', 'device-10', 'face', 'mobile_auto', 'out', 0.88, '2026-01-12 20:30:00.000', 'https://example.com/images/entry-14.jpg', 'Late evening exit from Rajouri', 'AUTO', 'JK04GH3456', 'Bajaj Auto', true, '2026-01-12 20:30:00.000'),

-- Entry logs for Khadija Ansari (person-8) - Doda (village-3) (January 12, 2026)
('entry-15', 'req-015', 'person-8', 'Khadija Ansari', 'device-11', 'manual', 'manual', 'in', 0.80, '2026-01-12 10:30:00.000', NULL, 'Manual entry - visitor at Doda north gate', NULL, NULL, NULL, true, '2026-01-12 10:30:00.000'),
('entry-16', 'req-016', 'person-8', 'Khadija Ansari', 'device-11', 'face', 'server_confirm', 'out', 0.94, '2026-01-12 16:45:00.000', 'https://example.com/images/entry-16.jpg', 'Face recognition verified exit from Doda', NULL, NULL, NULL, true, '2026-01-12 16:45:00.000'),

-- Entry logs for Yusuf Qureshi (person-9) - Udhampur (village-4) (January 12, 2026)
('entry-17', 'req-017', 'person-9', 'Yusuf Qureshi', 'device-13', 'fingerprint', 'server_confirm', 'in', 0.91, '2026-01-12 11:00:00.000', 'https://example.com/images/entry-17.jpg', 'Fingerprint verified entry at Udhampur', 'CAR', 'JK05IJ7890', 'Hyundai i20', true, '2026-01-12 11:00:00.000'),
('entry-18', 'req-018', 'person-9', 'Yusuf Qureshi', 'device-13', 'fingerprint', 'server_confirm', 'out', 0.93, '2026-01-12 17:20:00.000', 'https://example.com/images/entry-18.jpg', 'Verified exit from Udhampur', 'CAR', 'JK05IJ7890', 'Hyundai i20', true, '2026-01-12 17:20:00.000'),

-- Entry logs for Mariam Dar (person-10) - Baramulla (village-5) (January 12, 2026)
('entry-19', 'req-019', 'person-10', 'Mariam Dar', 'device-15', 'face', 'mobile_auto', 'in', 0.95, '2026-01-12 12:15:00.000', 'https://example.com/images/entry-19.jpg', 'Entry with high confidence at Baramulla', NULL, NULL, NULL, true, '2026-01-12 12:15:00.000'),
('entry-20', 'req-020', 'person-10', 'Mariam Dar', 'device-15', 'face', 'mobile_auto', 'out', 0.97, '2026-01-12 18:00:00.000', 'https://example.com/images/entry-20.jpg', 'Recent exit - high confidence match from Baramulla', NULL, NULL, NULL, true, '2026-01-12 18:00:00.000')
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- STEP 6: Auth Service Seed Data
-- ============================================================================

-- Seed initial SUPER_ADMIN user
-- Password: Admin123 (bcrypt hash with cost factor 12)
INSERT INTO users (
    phone_number,
    full_name,
    employee_id,
    password_hash,
    role,
    is_active,
    password_changed_at,
    password_expires_at,
    created_by,
    updated_by,
    created_at,
    updated_at
) VALUES (
    'admin',
    'System Administrator',
    'ADMIN001',
    '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYIr3mXuNWe',
    'SUPER_ADMIN',
    true,
    NOW(),
    NOW() + INTERVAL '90 days',
    NULL,
    NULL,
    NOW(),
    NOW()
)
ON CONFLICT (phone_number) DO NOTHING;

-- Add audit log entry for initial admin creation
INSERT INTO user_audit_logs (
    user_id,
    action,
    performed_by,
    metadata,
    ip_address,
    device_info,
    created_at
) SELECT
    u.id,
    'USER_CREATED',
    NULL,
    '{"source": "database_seed", "role": "SUPER_ADMIN"}'::jsonb,
    '127.0.0.1',
    'Database Setup Script',
    NOW()
FROM users u
WHERE u.phone_number = 'admin'
ON CONFLICT DO NOTHING;

-- ============================================================================
-- Setup Complete!
-- ============================================================================

SELECT 'Database setup completed successfully!' AS status;


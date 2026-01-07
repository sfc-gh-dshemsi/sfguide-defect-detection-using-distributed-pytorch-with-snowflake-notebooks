-- ============================================================================
-- PCB Defect Detection - Teardown Script
-- ============================================================================
-- Run this script to clean up all objects created by the setup script.
-- WARNING: This will permanently delete all data and objects!
-- ============================================================================

USE ROLE ACCOUNTADMIN;

-- ============================================================================
-- 1. Drop Services (must be dropped before compute pools and models)
-- ============================================================================
-- IMPORTANT: Run this first to see all services
SHOW SERVICES IN SCHEMA PCB_CV.PUBLIC;

-- Drop the main inference service
DROP SERVICE IF EXISTS PCB_CV.PUBLIC.DEFECTDETECTSERVICE;

-- Drop any MODEL_BUILD services (auto-created during model deployment)
-- These services are created automatically when logging models to registry.
-- Run SHOW SERVICES above, find any MODEL_BUILD_% services, and drop them:
-- SHOW SERVICES IN SCHEMA PCB_CV.PUBLIC;
--
-- Common pattern: MODEL_BUILD_XXXXXXXX (8 character hex ID)
-- Example: DROP SERVICE IF EXISTS PCB_CV.PUBLIC.MODEL_BUILD_5837C509;
--
-- >>> PASTE YOUR MODEL_BUILD SERVICE DROP COMMAND HERE <<<
-- DROP SERVICE IF EXISTS PCB_CV.PUBLIC.MODEL_BUILD_XXXXXXXX;

-- ============================================================================
-- 2. Drop Model (after all services are dropped)
-- ============================================================================
-- NOTE: If you get "Model is being used by inference services", 
-- go back to step 1 and ensure ALL MODEL_BUILD_% services are dropped first.
DROP MODEL IF EXISTS PCB_CV.PUBLIC.DEFECTDETECTIONMODEL;

-- ============================================================================
-- 3. Drop Streamlit App
-- ============================================================================
DROP STREAMLIT IF EXISTS PCB_CV.PUBLIC.PCB_DEFECT_DETECTION_APP;

-- ============================================================================
-- 4. Drop Notebooks
-- ============================================================================
DROP NOTEBOOK IF EXISTS PCB_CV.PUBLIC.TRAIN_PCB_DEFECT_MODEL;
DROP NOTEBOOK IF EXISTS PCB_CV.PUBLIC.TRAIN_PCB_DEFECT_DETECTION_YOLO;

-- ============================================================================
-- 5. Drop Git Repository
-- ============================================================================
DROP GIT REPOSITORY IF EXISTS PCB_CV.PUBLIC.PCB_CV_REPO;

-- ============================================================================
-- 6. Drop Secret
-- ============================================================================
DROP SECRET IF EXISTS PCB_CV.PUBLIC.GITHUB_SECRET;

-- ============================================================================
-- 7. Drop Compute Pools
-- ============================================================================
DROP COMPUTE POOL IF EXISTS PCB_CV_COMPUTEPOOL;
DROP COMPUTE POOL IF EXISTS PCB_CV_SERVICE_COMPUTEPOOL;

-- ============================================================================
-- 8. Drop Database (includes all schemas, tables, stages, network rules, etc.)
-- ============================================================================
DROP DATABASE IF EXISTS PCB_CV;

-- ============================================================================
-- 9. Drop Warehouse
-- ============================================================================
DROP WAREHOUSE IF EXISTS PCB_CV_WH;

-- ============================================================================
-- 10. Drop Integrations
-- ============================================================================
DROP INTEGRATION IF EXISTS GITHUB_INTEGRATION_PCB_CV;
DROP INTEGRATION IF EXISTS allow_all_integration;

-- ============================================================================
-- 11. Drop Role
-- ============================================================================
DROP ROLE IF EXISTS PCB_CV_ROLE;

-- ============================================================================
-- Teardown Complete
-- ============================================================================
SELECT 'Teardown complete! All PCB CV objects have been removed.' AS STATUS;

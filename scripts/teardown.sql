-- ============================================================================
-- PCB Defect Detection - Teardown Script
-- ============================================================================
-- Run this script to clean up all objects created by the setup script.
-- WARNING: This will permanently delete all data and objects!
-- ============================================================================

USE ROLE ACCOUNTADMIN;

-- ============================================================================
-- 1. Drop Services (must be dropped before compute pools)
-- ============================================================================
DROP SERVICE IF EXISTS PCB_CV.PUBLIC.DEFECTDETECTSERVICE;

-- Drop any model build services
SHOW SERVICES IN SCHEMA PCB_CV.PUBLIC;
-- Note: Manually drop any MODEL_BUILD_% services if they exist

-- ============================================================================
-- 2. Drop Streamlit App
-- ============================================================================
DROP STREAMLIT IF EXISTS PCB_CV.PUBLIC.PCB_DEFECT_DETECTION_APP;

-- ============================================================================
-- 3. Drop Notebook
-- ============================================================================
DROP NOTEBOOK IF EXISTS PCB_CV.PUBLIC.TRAIN_PCB_DEFECT_MODEL;

-- ============================================================================
-- 4. Drop Git Repository
-- ============================================================================
DROP GIT REPOSITORY IF EXISTS PCB_CV.PUBLIC.PCB_CV_REPO;

-- ============================================================================
-- 5. Drop Secret
-- ============================================================================
DROP SECRET IF EXISTS PCB_CV.PUBLIC.GITHUB_SECRET;

-- ============================================================================
-- 6. Drop Compute Pools
-- ============================================================================
DROP COMPUTE POOL IF EXISTS PCB_CV_COMPUTEPOOL;
DROP COMPUTE POOL IF EXISTS PCB_CV_SERVICE_COMPUTEPOOL;

-- ============================================================================
-- 7. Drop Database (includes all schemas, tables, stages, repos)
-- ============================================================================
DROP DATABASE IF EXISTS PCB_CV;

-- ============================================================================
-- 8. Drop Warehouse
-- ============================================================================
DROP WAREHOUSE IF EXISTS PCB_CV_WH;

-- ============================================================================
-- 9. Drop Integrations
-- ============================================================================
DROP INTEGRATION IF EXISTS GITHUB_INTEGRATION_PCB_CV;
DROP INTEGRATION IF EXISTS allow_all_integration;

-- ============================================================================
-- 10. Drop Network Rule
-- ============================================================================
DROP NETWORK RULE IF EXISTS allow_all_rule;

-- ============================================================================
-- 11. Drop Role
-- ============================================================================
DROP ROLE IF EXISTS PCB_CV_ROLE;

-- ============================================================================
-- Teardown Complete
-- ============================================================================
SELECT 'Teardown complete! All PCB CV objects have been removed.' AS STATUS;

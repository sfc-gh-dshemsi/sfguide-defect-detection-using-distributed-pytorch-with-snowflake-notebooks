/*
 * Teardown Script for PCB Defect Detection Quickstart
 * 
 * This script removes all Snowflake objects created by setup.sql.
 * Run this to clean up resources after completing the quickstart.
 * 
 * WARNING: This will permanently delete all data and objects!
 */

USE ROLE PCB_DEFECT_DETECTION_ROLE;

-- Drop Streamlit app
DROP STREAMLIT IF EXISTS PCB_DATASET.PCB_SCHEMA.PCB_DEFECT_DETECTION_APP;

-- Drop notebooks
DROP NOTEBOOK IF EXISTS PCB_DATASET.PCB_SCHEMA.DATA_PREPARATION;
DROP NOTEBOOK IF EXISTS PCB_DATASET.PCB_SCHEMA.DISTRIBUTED_MODEL_TRAINING;

-- Drop Git repository
DROP GIT REPOSITORY IF EXISTS PCB_DATASET.PCB_SCHEMA.PCB_GITHUB_REPO;

-- Drop compute pool
DROP COMPUTE POOL IF EXISTS PCB_GPU_POOL;

-- Drop warehouse
DROP WAREHOUSE IF EXISTS PCB_WH;

-- Drop database (this will also drop all contained objects)
DROP DATABASE IF EXISTS PCB_DATASET;

-- Clean up integrations and role (requires ACCOUNTADMIN)
USE ROLE ACCOUNTADMIN;

DROP INTEGRATION IF EXISTS allow_all_integration;
DROP NETWORK RULE IF EXISTS allow_all_rule;
DROP API INTEGRATION IF EXISTS GITHUB_INTEGRATION_PCB;

-- Revoke and drop the role
DROP ROLE IF EXISTS PCB_DEFECT_DETECTION_ROLE;


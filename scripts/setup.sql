--- ============================================================================
-- PCB Defect Detection with Distributed PyTorch - Setup Script
-- ============================================================================
USE ROLE ACCOUNTADMIN;

SET USERNAME = (SELECT CURRENT_USER());
SELECT $USERNAME;

-- Set query tag for tracking
ALTER SESSION SET query_tag = '{"origin":"sf_sit-is","name":"pcb_defect_detection","version":{"major":1,"minor":0},"attributes":{"is_quickstart":1,"source":"sql"}}';

-- ============================================================================
-- 1. Create Role and Grant Account-Level Permissions
-- ============================================================================
CREATE OR REPLACE ROLE PCB_CV_ROLE;
GRANT ROLE PCB_CV_ROLE to USER identifier($USERNAME);

GRANT CREATE DATABASE ON ACCOUNT TO ROLE PCB_CV_ROLE;
GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE PCB_CV_ROLE;
GRANT CREATE COMPUTE POOL ON ACCOUNT TO ROLE PCB_CV_ROLE;
GRANT BIND SERVICE ENDPOINT ON ACCOUNT TO ROLE PCB_CV_ROLE;
GRANT CREATE INTEGRATION ON ACCOUNT TO ROLE PCB_CV_ROLE;

-- ============================================================================
-- 2. Create Database, Warehouse, and Schema
-- ============================================================================
CREATE OR REPLACE WAREHOUSE PCB_CV_WH
    WAREHOUSE_SIZE = MEDIUM
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

CREATE OR REPLACE DATABASE PCB_CV;
CREATE OR REPLACE SCHEMA PCB_CV.PUBLIC;

-- ============================================================================
-- 3. Create Network Rule & Secret (DO THIS BEFORE TRANSFERRING OWNERSHIP)
-- ============================================================================
-- This must be done while ACCOUNTADMIN still owns the PUBLIC schema
-- Network rule: 0.0.0.0 wildcards allow all outbound traffic on ports 443/80
CREATE OR REPLACE NETWORK RULE PCB_CV.PUBLIC.allow_all_rule
    TYPE = 'HOST_PORT'
    MODE = 'EGRESS'
    VALUE_LIST = ('0.0.0.0:443', '0.0.0.0:80')
    COMMENT = 'Allow all outbound HTTPS/HTTP traffic for external package installs';

-- Create Secret (Replace with your valid GitHub PAT)
CREATE OR REPLACE SECRET PCB_CV.PUBLIC.GITHUB_SECRET
    TYPE = PASSWORD
    USERNAME = 'your_github_username' 
    PASSWORD = 'your_github_pat' 
    COMMENT = 'GitHub PAT for accessing PCB CV repository';

-- ============================================================================
-- 4. Grant Privileges and Transfer Ownership
-- ============================================================================
-- Warehouse grants and ownership
GRANT USAGE ON WAREHOUSE PCB_CV_WH TO ROLE PCB_CV_ROLE;
GRANT OWNERSHIP ON WAREHOUSE PCB_CV_WH TO ROLE PCB_CV_ROLE COPY CURRENT GRANTS;

-- Database grants (but NOT ownership yet - need to grant on schema first)
GRANT USAGE ON DATABASE PCB_CV TO ROLE PCB_CV_ROLE;
GRANT ALL PRIVILEGES ON DATABASE PCB_CV TO ROLE PCB_CV_ROLE;

-- Schema grants (BEFORE any ownership transfer)
GRANT USAGE ON SCHEMA PCB_CV.PUBLIC TO ROLE PCB_CV_ROLE;
GRANT ALL PRIVILEGES ON SCHEMA PCB_CV.PUBLIC TO ROLE PCB_CV_ROLE;
GRANT CREATE MODEL ON SCHEMA PCB_CV.PUBLIC TO ROLE PCB_CV_ROLE;
GRANT CREATE STAGE ON SCHEMA PCB_CV.PUBLIC TO ROLE PCB_CV_ROLE;
GRANT CREATE SERVICE ON SCHEMA PCB_CV.PUBLIC TO ROLE PCB_CV_ROLE;
GRANT CREATE TABLE ON SCHEMA PCB_CV.PUBLIC TO ROLE PCB_CV_ROLE;
GRANT CREATE VIEW ON SCHEMA PCB_CV.PUBLIC TO ROLE PCB_CV_ROLE;
GRANT CREATE FUNCTION ON SCHEMA PCB_CV.PUBLIC TO ROLE PCB_CV_ROLE;
GRANT CREATE PROCEDURE ON SCHEMA PCB_CV.PUBLIC TO ROLE PCB_CV_ROLE;

-- Grant on existing objects in schema
GRANT USAGE, READ ON SECRET PCB_CV.PUBLIC.GITHUB_SECRET TO ROLE PCB_CV_ROLE;

-- ============================================================================
-- 5. Create Integrations 
-- ============================================================================
-- External Access Integration 
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION allow_all_integration
    ALLOWED_NETWORK_RULES = (PCB_CV.PUBLIC.allow_all_rule)
    ENABLED = true;

GRANT USAGE ON INTEGRATION allow_all_integration TO ROLE PCB_CV_ROLE;

-- Git API Integration 
CREATE OR REPLACE API INTEGRATION GITHUB_INTEGRATION_PCB_CV
    API_PROVIDER = git_https_api
    API_ALLOWED_PREFIXES = ('https://github.com/')
    ALLOWED_AUTHENTICATION_SECRETS = (PCB_CV.PUBLIC.GITHUB_SECRET)
    ENABLED = TRUE;

GRANT USAGE ON INTEGRATION GITHUB_INTEGRATION_PCB_CV TO ROLE PCB_CV_ROLE;

-- ============================================================================
-- 6. Transfer Ownership 
-- ============================================================================
GRANT OWNERSHIP ON SCHEMA PCB_CV.PUBLIC TO ROLE PCB_CV_ROLE COPY CURRENT GRANTS;
GRANT OWNERSHIP ON DATABASE PCB_CV TO ROLE PCB_CV_ROLE COPY CURRENT GRANTS;

-- ============================================================================
-- 7. Switch to PCB_CV_ROLE and Create Remaining Objects
-- ============================================================================
USE ROLE PCB_CV_ROLE;
USE WAREHOUSE PCB_CV_WH;
USE DATABASE PCB_CV;
USE SCHEMA PUBLIC;

-- Create Git Repository
CREATE OR REPLACE GIT REPOSITORY PCB_CV_REPO
    API_INTEGRATION = GITHUB_INTEGRATION_PCB_CV
    GIT_CREDENTIALS = PCB_CV.PUBLIC.GITHUB_SECRET
    ORIGIN = 'https://github.com/sfc-gh-dshemsi/sfguide-defect-detection-using-distributed-pytorch-with-snowflake-notebooks.git';

ALTER GIT REPOSITORY PCB_CV_REPO FETCH;

-- Create Stages & Image Repo
CREATE OR REPLACE STAGE PCB_CV_DEEP_PCB_DATASET_STAGE
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Stage for Deep PCB dataset (R-CNN approach)';

-- Stage for YOLOv12 model and raw images (stage-based approach)
CREATE OR REPLACE STAGE MODEL_STAGE
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Stage for YOLOv12 models, weights, and raw PCB images';

-- Stage for notebook files
CREATE OR REPLACE STAGE NOTEBOOKS
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Stage for Jupyter notebook files';

CREATE OR REPLACE IMAGE REPOSITORY IMAGE_REPO;


-- ============================================================================
-- 8. Create Compute Pools
-- ============================================================================
-- GPU compute pool for distributed PyTorch training (1 GPU)
CREATE COMPUTE POOL IF NOT EXISTS PCB_CV_COMPUTEPOOL
    MIN_NODES = 3
    MAX_NODES = 3
    INSTANCE_FAMILY = GPU_NV_M
    AUTO_SUSPEND_SECS = 600
    COMMENT = 'GPU compute pool for distributed PyTorch training';

-- GPU compute pool for model inference service
CREATE COMPUTE POOL IF NOT EXISTS PCB_CV_SERVICE_COMPUTEPOOL
    MIN_NODES = 3
    MAX_NODES = 3
    INSTANCE_FAMILY = GPU_NV_S
    AUTO_SUSPEND_SECS = 600
    COMMENT = 'GPU compute pool for model inference service';

USE ROLE ACCOUNTADMIN;
GRANT OWNERSHIP ON COMPUTE POOL PCB_CV_COMPUTEPOOL TO ROLE PCB_CV_ROLE COPY CURRENT GRANTS;
GRANT OWNERSHIP ON COMPUTE POOL PCB_CV_SERVICE_COMPUTEPOOL TO ROLE PCB_CV_ROLE COPY CURRENT GRANTS;
USE ROLE PCB_CV_ROLE;

-- ============================================================================
-- 9. Create Tables
-- ============================================================================
CREATE OR REPLACE TABLE TRAINING_DATA (
    FILENAME VARCHAR(255),
    IMAGE_DATA VARCHAR(16777216),
    CLASS INT,
    XMIN FLOAT,
    YMIN FLOAT,
    XMAX FLOAT,
    YMAX FLOAT
) COMMENT = 'Training dataset with base64 encoded images and labels';

CREATE OR REPLACE TABLE TEST_DATA (
    FILENAME VARCHAR(255),
    IMAGE_DATA VARCHAR(16777216),
    CLASS INT,
    XMIN FLOAT,
    YMIN FLOAT,
    XMAX FLOAT,
    YMAX FLOAT
) COMMENT = 'Test dataset for model evaluation';

CREATE OR REPLACE TABLE DETECTION_OUTPUTS (
    IMAGE_DATA VARCHAR(16777216),
    OUTPUT VARCHAR(16777216),
    LABEL NUMBER(38,0),
    BOX VARIANT,
    SCORE FLOAT
) COMMENT = 'Model inference detection outputs (R-CNN)';

-- PCB Metadata: Tracks individual PCB boards (for YOLOv12 dashboard)
CREATE OR REPLACE TABLE PCB_METADATA (
    BOARD_ID VARCHAR(50) NOT NULL,
    MANUFACTURING_DATE TIMESTAMP_NTZ,
    FACTORY_LINE_ID VARCHAR(50),
    PRODUCT_TYPE VARCHAR(100),
    IMAGE_PATH VARCHAR(500),
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_PCB_METADATA PRIMARY KEY (BOARD_ID)
) COMMENT = 'Metadata for PCB boards processed through defect detection';

-- Defect Logs: Stores inference results from YOLOv12
CREATE OR REPLACE TABLE DEFECT_LOGS (
    INFERENCE_ID VARCHAR(36) NOT NULL,
    BOARD_ID VARCHAR(50),
    INFERENCE_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    DETECTED_CLASS VARCHAR(50) NOT NULL,
    CONFIDENCE_SCORE FLOAT,
    BBOX_X_CENTER FLOAT,
    BBOX_Y_CENTER FLOAT,
    BBOX_WIDTH FLOAT,
    BBOX_HEIGHT FLOAT,
    IMAGE_PATH VARCHAR(500),
    MODEL_VERSION VARCHAR(50),
    CONSTRAINT PK_DEFECT_LOGS PRIMARY KEY (INFERENCE_ID)
) COMMENT = 'Inference results from YOLOv12 defect detection model';

-- Create index-like clustering for common query patterns
ALTER TABLE DEFECT_LOGS CLUSTER BY (DETECTED_CLASS, INFERENCE_TIMESTAMP);

-- ============================================================================
-- 9b. Create Analytics Views (for YOLOv12 Dashboard)
-- ============================================================================

-- Defect Summary by Class
CREATE OR REPLACE VIEW DEFECT_SUMMARY AS
SELECT 
    DETECTED_CLASS,
    COUNT(*) AS DEFECT_COUNT,
    AVG(CONFIDENCE_SCORE) AS AVG_CONFIDENCE,
    MIN(INFERENCE_TIMESTAMP) AS FIRST_DETECTED,
    MAX(INFERENCE_TIMESTAMP) AS LAST_DETECTED
FROM DEFECT_LOGS
GROUP BY DETECTED_CLASS;

-- Daily Defect Trends
CREATE OR REPLACE VIEW DAILY_DEFECT_TRENDS AS
SELECT 
    DATE_TRUNC('DAY', INFERENCE_TIMESTAMP) AS DETECTION_DATE,
    DETECTED_CLASS,
    COUNT(*) AS DEFECT_COUNT,
    AVG(CONFIDENCE_SCORE) AS AVG_CONFIDENCE
FROM DEFECT_LOGS
GROUP BY DATE_TRUNC('DAY', INFERENCE_TIMESTAMP), DETECTED_CLASS
ORDER BY DETECTION_DATE DESC, DEFECT_COUNT DESC;

-- Factory Line Performance
CREATE OR REPLACE VIEW FACTORY_LINE_DEFECTS AS
SELECT 
    COALESCE(m.FACTORY_LINE_ID, 'UNKNOWN') AS FACTORY_LINE_ID,
    d.DETECTED_CLASS,
    COUNT(*) AS DEFECT_COUNT,
    AVG(d.CONFIDENCE_SCORE) AS AVG_CONFIDENCE
FROM DEFECT_LOGS d
LEFT JOIN PCB_METADATA m ON d.BOARD_ID = m.BOARD_ID
GROUP BY COALESCE(m.FACTORY_LINE_ID, 'UNKNOWN'), d.DETECTED_CLASS;

-- ============================================================================
-- 9c. Insert Sample PCB Metadata (for demo dashboard)
-- ============================================================================
INSERT INTO PCB_METADATA (BOARD_ID, MANUFACTURING_DATE, FACTORY_LINE_ID, PRODUCT_TYPE)
SELECT 
    'PCB_' || SEQ4() AS BOARD_ID,
    DATEADD('HOUR', -UNIFORM(0, 720, RANDOM()), CURRENT_TIMESTAMP()) AS MANUFACTURING_DATE,
    CASE UNIFORM(1, 4, RANDOM())
        WHEN 1 THEN 'SHANGHAI_L1'
        WHEN 2 THEN 'SHANGHAI_L2'
        WHEN 3 THEN 'SHENZHEN_L1'
        ELSE 'AUSTIN_L1'
    END AS FACTORY_LINE_ID,
    CASE UNIFORM(1, 3, RANDOM())
        WHEN 1 THEN 'CONSUMER_ELECTRONICS'
        WHEN 2 THEN 'AUTOMOTIVE'
        ELSE 'INDUSTRIAL'
    END AS PRODUCT_TYPE
FROM TABLE(GENERATOR(ROWCOUNT => 100));

-- ============================================================================
-- 10. Create Notebook from Git Repository
-- ============================================================================
CREATE OR REPLACE NOTEBOOK TRAIN_PCB_DEFECT_MODEL
    FROM '@PCB_CV_REPO/branches/main'
    MAIN_FILE = 'notebooks/0_train_pcb_defect_detection_model.ipynb'
    QUERY_WAREHOUSE = PCB_CV_WH
    COMPUTE_POOL = PCB_CV_COMPUTEPOOL
    RUNTIME_NAME = 'SYSTEM$GPU_RUNTIME'
    IDLE_AUTO_SHUTDOWN_TIME_SECONDS = 3600
    COMMENT = '{"origin":"sf_sit-is", "name":"pcb_defect_detection", "version":{"major":1, "minor":0}, "attributes":{"is_quickstart":1, "source":"notebook"}}';

ALTER NOTEBOOK TRAIN_PCB_DEFECT_MODEL ADD LIVE VERSION FROM LAST;
ALTER NOTEBOOK TRAIN_PCB_DEFECT_MODEL SET EXTERNAL_ACCESS_INTEGRATIONS = ('allow_all_integration');

-- Create YOLO Notebook (alternative model - faster training, single GPU)
CREATE OR REPLACE NOTEBOOK TRAIN_PCB_DEFECT_MODEL_YOLO
    FROM '@PCB_CV_REPO/branches/main'
    MAIN_FILE = 'notebooks/1_train_pcb_defect_detection_yolo.ipynb'
    QUERY_WAREHOUSE = PCB_CV_WH
    COMPUTE_POOL = PCB_CV_COMPUTEPOOL
    RUNTIME_NAME = 'SYSTEM$GPU_RUNTIME'
    IDLE_AUTO_SHUTDOWN_TIME_SECONDS = 3600
    COMMENT = '{"origin":"sf_sit-is", "name":"pcb_defect_detection_yolo", "version":{"major":1, "minor":0}, "attributes":{"is_quickstart":1, "source":"notebook"}}';

ALTER NOTEBOOK TRAIN_PCB_DEFECT_MODEL_YOLO ADD LIVE VERSION FROM LAST;
ALTER NOTEBOOK TRAIN_PCB_DEFECT_MODEL_YOLO SET EXTERNAL_ACCESS_INTEGRATIONS = ('allow_all_integration');

-- ============================================================================
-- 11. Create Streamlit App from Git Repository
-- ============================================================================
-- Using Native SiS (not Container Runtime) for snowflake-ml-python compatibility
CREATE OR REPLACE STREAMLIT PCB_DEFECT_DETECTION_APP
    FROM '@PCB_CV_REPO/branches/main/streamlit'
    MAIN_FILE = 'app.py'
    QUERY_WAREHOUSE = PCB_CV_WH
    TITLE = 'PCB Defect Detection'
    COMMENT = '{"origin":"sf_sit-is", "name":"pcb_defect_detection", "version":{"major":1, "minor":0}, "attributes":{"is_quickstart":1, "source":"streamlit"}}';

ALTER STREAMLIT PCB_DEFECT_DETECTION_APP ADD LIVE VERSION FROM LAST;
ALTER STREAMLIT PCB_DEFECT_DETECTION_APP SET EXTERNAL_ACCESS_INTEGRATIONS = ('allow_all_integration');

-- Grant usage on the Streamlit app
GRANT USAGE ON STREAMLIT PCB_DEFECT_DETECTION_APP TO ROLE PCB_CV_ROLE;

-- ============================================================================
-- 12. Create Data Loading Procedure
-- ============================================================================
CREATE OR REPLACE PROCEDURE LOAD_DEEPPCB_DATA()
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'requests', 'pillow')
HANDLER = 'load_data'
EXTERNAL_ACCESS_INTEGRATIONS = (allow_all_integration)
AS
$$
import requests
import zipfile
import io
import os
import base64
from PIL import Image
import random
import re

def load_data(session):
    """
    Download DeepPCB dataset and load into Snowflake tables.
    Dataset: https://github.com/tangsanli5201/DeepPCB
    
    Structure: PCBData/group{N}/{N}/*_test.jpg (images)
               PCBData/group{N}/{N}_not/*.txt (labels)
    """
    
    # Download entire DeepPCB repository as zip
    REPO_URL = "https://github.com/tangsanli5201/DeepPCB/archive/refs/heads/master.zip"
    
    print("Downloading DeepPCB repository...")
    response = requests.get(REPO_URL, timeout=600, allow_redirects=True)
    
    if response.status_code != 200:
        return f"Failed to download dataset: HTTP {response.status_code}"
    
    print("Extracting dataset...")
    zip_file = zipfile.ZipFile(io.BytesIO(response.content))
    
    # Build index of all files in zip
    all_files = zip_file.namelist()
    
    # Find all test images and their corresponding labels
    # Structure: DeepPCB-master/PCBData/group{N}/{N}/*_test.jpg
    #            DeepPCB-master/PCBData/group{N}/{N}_not/*.txt
    
    data_records = []
    processed_images = 0
    
    for name in all_files:
        # Find test images
        if '_test.jpg' in name and '/PCBData/' in name:
            # Extract the base filename (e.g., "00041000")
            filename_base = os.path.basename(name).replace('_test.jpg', '')
            
            # Get the directory containing the image
            img_dir = os.path.dirname(name)
            
            # Construct the _not directory path for labels
            # e.g., group00001/00001 -> group00001/00001_not
            parent_dir = os.path.dirname(img_dir)
            folder_name = os.path.basename(img_dir)
            not_dir = os.path.join(parent_dir, folder_name + '_not')
            
            # Find the label file
            label_file = os.path.join(not_dir, filename_base + '.txt')
            
            # Normalize path separators
            label_file = label_file.replace('\\', '/')
            
            try:
                # Read and encode image
                with zip_file.open(name) as img_file:
                    img_bytes = img_file.read()
                    image_b64 = base64.b64encode(img_bytes).decode('utf-8')
                
                # Try to find and read the label file
                label_found = False
                for f in all_files:
                    if f.endswith(filename_base + '.txt') and '_not/' in f:
                        with zip_file.open(f) as lbl_file:
                            for line in lbl_file.read().decode('utf-8').strip().split('\\n'):
                                if line.strip():
                                    parts = line.strip().split()
                                    if len(parts) >= 5:
                                        xmin, ymin, xmax, ymax = map(float, parts[:4])
                                        defect_class = int(parts[4])
                                        
                                        data_records.append({
                                            'FILENAME': filename_base,
                                            'IMAGE_DATA': image_b64,
                                            'CLASS': defect_class,
                                            'XMIN': xmin,
                                            'YMIN': ymin,
                                            'XMAX': xmax,
                                            'YMAX': ymax
                                        })
                                        label_found = True
                        break
                
                processed_images += 1
                if processed_images % 50 == 0:
                    print(f"Processed {processed_images} images...")
                    
            except Exception as e:
                print(f"Error processing {name}: {e}")
                continue
    
    if not data_records:
        return f"No valid records found. Processed {processed_images} images but found no matching labels."
    
    print(f"Found {len(data_records)} defect annotations from {processed_images} images")
    
    # Shuffle and split 90/10
    random.seed(42)
    random.shuffle(data_records)
    split_idx = int(len(data_records) * 0.9)
    
    train_records = data_records[:split_idx]
    test_records = data_records[split_idx:]
    
    print(f"Training set: {len(train_records)} records")
    print(f"Test set: {len(test_records)} records")
    
    # Clear existing data
    session.sql("TRUNCATE TABLE TRAINING_DATA").collect()
    session.sql("TRUNCATE TABLE TEST_DATA").collect()
    
    # Insert training data in batches
    batch_size = 100
    for i in range(0, len(train_records), batch_size):
        batch = train_records[i:i+batch_size]
        df = session.create_dataframe(batch)
        df.write.mode("append").save_as_table("TRAINING_DATA")
        print(f"Loaded training batch {i//batch_size + 1}/{(len(train_records)-1)//batch_size + 1}")
    
    # Insert test data
    for i in range(0, len(test_records), batch_size):
        batch = test_records[i:i+batch_size]
        df = session.create_dataframe(batch)
        df.write.mode("append").save_as_table("TEST_DATA")
        print(f"Loaded test batch {i//batch_size + 1}/{(len(test_records)-1)//batch_size + 1}")
    
    return f"Success! Loaded {len(train_records)} training and {len(test_records)} test records."
$$;

-- ============================================================================
-- 13. Execute Data Load
-- ============================================================================
CALL LOAD_DEEPPCB_DATA();

SELECT 'Setup Complete' AS STATUS;
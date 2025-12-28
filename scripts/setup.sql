--- ============================================================================
-- PCB Defect Detection with Distributed PyTorch - Setup Script
-- ============================================================================
USE ROLE ACCOUNTADMIN;

SET USERNAME = (SELECT CURRENT_USER());
SELECT $USERNAME;

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
    WAREHOUSE_SIZE = SMALL
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

CREATE OR REPLACE DATABASE PCB_CV;
CREATE OR REPLACE SCHEMA PCB_CV.PUBLIC;

-- ============================================================================
-- 3. Create Network Rule & Secret (DO THIS BEFORE TRANSFERRING OWNERSHIP)
-- ============================================================================
-- This must be done while ACCOUNTADMIN still owns the PUBLIC schema
CREATE OR REPLACE NETWORK RULE PCB_CV.PUBLIC.allow_all_rule
    TYPE = 'HOST_PORT'
    MODE = 'EGRESS'
    VALUE_LIST = ('0.0.0.0:443', '0.0.0.0:80');

-- Create Secret (Replace with your valid GitHub PAT)
CREATE OR REPLACE SECRET PCB_CV.PUBLIC.GITHUB_SECRET
    TYPE = PASSWORD
    USERNAME = 'your_github_username' 
    PASSWORD = 'your_github_pat' 
    COMMENT = 'GitHub PAT for accessing PCB CV repository';

-- ============================================================================
-- 4. Transfer Ownership and Grant Usages
-- ============================================================================
GRANT USAGE ON WAREHOUSE PCB_CV_WH TO ROLE PCB_CV_ROLE;
GRANT OWNERSHIP ON WAREHOUSE PCB_CV_WH TO ROLE PCB_CV_ROLE COPY CURRENT GRANTS;

GRANT USAGE ON DATABASE PCB_CV TO ROLE PCB_CV_ROLE;
GRANT OWNERSHIP ON DATABASE PCB_CV TO ROLE PCB_CV_ROLE COPY CURRENT GRANTS;

GRANT USAGE ON SCHEMA PCB_CV.PUBLIC TO ROLE PCB_CV_ROLE;
GRANT OWNERSHIP ON SCHEMA PCB_CV.PUBLIC TO ROLE PCB_CV_ROLE COPY CURRENT GRANTS;

-- Grant permissions for existing objects in the schema to the new role
GRANT USAGE, READ ON SECRET PCB_CV.PUBLIC.GITHUB_SECRET TO ROLE PCB_CV_ROLE;

-- ============================================================================
-- 5. Create Integrations (Requires ACCOUNTADMIN)
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
-- 6. Switch to PCB_CV_ROLE and Create Remaining Objects
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
CREATE OR REPLACE STAGE PCB_CV_DEEP_PCB_DATASET_STAGE;
CREATE OR REPLACE IMAGE REPOSITORY IMAGE_REPO;


-- ============================================================================
-- 7. Create Compute Pools
-- ============================================================================
-- GPU compute pool for distributed PyTorch training (1 GPU)
CREATE COMPUTE POOL IF NOT EXISTS PCB_CV_COMPUTEPOOL
    MIN_NODES = 3
    MAX_NODES = 3
    INSTANCE_FAMILY = GPU_NV_M
    AUTO_SUSPEND_SECS = 600
    COMMENT = 'GPU compute pool for distributed PyTorch training (Large)';

-- GPU compute pool for model inference service (1 GPU)
CREATE COMPUTE POOL IF NOT EXISTS PCB_CV_SERVICE_COMPUTEPOOL
    MIN_NODES = 3
    MAX_NODES = 3
    INSTANCE_FAMILY = GPU_NV_S
    AUTO_SUSPEND_SECS = 600
    COMMENT = 'GPU compute pool for model inference service (Medium)';

-- ============================================================================
-- 8. Create Tables
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
) COMMENT = 'Model inference detection outputs';

-- ============================================================================
-- 9. Create Notebook from Git Repository
-- ============================================================================
CREATE OR REPLACE NOTEBOOK TRAIN_PCB_DEFECT_MODEL
    FROM '@PCB_CV_REPO/branches/main'
    MAIN_FILE = 'notebooks/0_train_pcb_defect_detection_model.ipynb'
    QUERY_WAREHOUSE = PCB_CV_WH
    COMPUTE_POOL = PCB_CV_COMPUTEPOOL
    RUNTIME_NAME = 'SYSTEM$GPU_RUNTIME'
    IDLE_AUTO_SHUTDOWN_TIME_SECONDS = 3600;

ALTER NOTEBOOK TRAIN_PCB_DEFECT_MODEL ADD LIVE VERSION FROM LAST;
ALTER NOTEBOOK TRAIN_PCB_DEFECT_MODEL SET EXTERNAL_ACCESS_INTEGRATIONS = ('allow_all_integration');

-- ============================================================================
-- 10. Create Streamlit App from Git Repository
-- ============================================================================
CREATE OR REPLACE STREAMLIT PCB_DEFECT_DETECTION_APP
    FROM '@PCB_CV_REPO/branches/main/streamlit'
    MAIN_FILE = 'app.py'
    QUERY_WAREHOUSE = PCB_CV_WH
    COMPUTE_POOL = PCB_CV_SERVICE_COMPUTEPOOL
    RUNTIME_NAME = 'SYSTEM$ST_CONTAINER_RUNTIME_PY3_11'
    TITLE = 'PCB Defect Detection'
    COMMENT = '{"origin":"sf_sit-is", "name":"pcb_defect_detection", "version":{"major":1, "minor":0}, "attributes":{"is_quickstart":1, "source":"streamlit"}}';

ALTER STREAMLIT PCB_DEFECT_DETECTION_APP ADD LIVE VERSION FROM LAST;
ALTER STREAMLIT PCB_DEFECT_DETECTION_APP SET EXTERNAL_ACCESS_INTEGRATIONS = ('allow_all_integration');

-- ============================================================================
-- 11. Create Data Loading Procedure
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
-- 12. Execute Data Load
-- ============================================================================
CALL LOAD_DEEPPCB_DATA();

SELECT 'Setup Complete' AS STATUS;
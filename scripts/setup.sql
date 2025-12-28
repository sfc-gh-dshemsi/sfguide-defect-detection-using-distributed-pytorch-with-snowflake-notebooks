-- ============================================================================
-- PCB Defect Detection with Distributed PyTorch - Setup Script
-- ============================================================================
-- Run this script in Snowsight to set up all required objects for the
-- PCB defect detection demo with distributed GPU training.
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
-- 2. Create Database and Warehouse (as ACCOUNTADMIN for shared access)
-- ============================================================================
CREATE OR REPLACE WAREHOUSE PCB_CV_WH
    WAREHOUSE_SIZE = SMALL
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

CREATE OR REPLACE DATABASE PCB_CV;
CREATE OR REPLACE SCHEMA PCB_CV.PUBLIC;

-- Grant full privileges to PCB_CV_ROLE
GRANT ALL ON WAREHOUSE PCB_CV_WH TO ROLE PCB_CV_ROLE;
GRANT ALL ON DATABASE PCB_CV TO ROLE PCB_CV_ROLE;
GRANT ALL ON SCHEMA PCB_CV.PUBLIC TO ROLE PCB_CV_ROLE;

USE DATABASE PCB_CV;
USE SCHEMA PUBLIC;
USE WAREHOUSE PCB_CV_WH;

-- ============================================================================
-- 3. Create External Access Integration (for pip installs & data download)
-- ============================================================================
CREATE OR REPLACE NETWORK RULE PCB_CV.PUBLIC.allow_all_rule
    TYPE = 'HOST_PORT'
    MODE = 'EGRESS'
    VALUE_LIST = ('0.0.0.0:443', '0.0.0.0:80');

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION allow_all_integration
    ALLOWED_NETWORK_RULES = (PCB_CV.PUBLIC.allow_all_rule)
    ENABLED = true;

GRANT USAGE ON INTEGRATION allow_all_integration TO ROLE PCB_CV_ROLE;

-- ============================================================================
-- 4. Git Integration (with authentication)
-- ============================================================================
CREATE OR REPLACE SECRET PCB_CV.PUBLIC.GITHUB_SECRET
    TYPE = PASSWORD
    USERNAME = 'user_name'
    PASSWORD = 'password'
    COMMENT = 'GitHub PAT for accessing PCB CV repository';

-- Grant secret usage to role
GRANT USAGE ON SECRET PCB_CV.PUBLIC.GITHUB_SECRET TO ROLE PCB_CV_ROLE;
GRANT READ ON SECRET PCB_CV.PUBLIC.GITHUB_SECRET TO ROLE PCB_CV_ROLE;

-- Create API integration for Git (must reference the secret)
CREATE OR REPLACE API INTEGRATION GITHUB_INTEGRATION_PCB_CV
    API_PROVIDER = git_https_api
    API_ALLOWED_PREFIXES = ('https://github.com/')
    ALLOWED_AUTHENTICATION_SECRETS = (PCB_CV.PUBLIC.GITHUB_SECRET)
    ENABLED = TRUE
    COMMENT = 'Git integration with GitHub for PCB CV repository';

-- Grant integration usage to role
GRANT USAGE ON INTEGRATION GITHUB_INTEGRATION_PCB_CV TO ROLE PCB_CV_ROLE;

-- ============================================================================
-- 5. Switch to PCB_CV_ROLE and Create Remaining Objects
-- ============================================================================
USE ROLE PCB_CV_ROLE;
USE DATABASE PCB_CV;
USE SCHEMA PUBLIC;
USE WAREHOUSE PCB_CV_WH;

-- ============================================================================
-- 6. Create Git Repository (with authentication)
-- ============================================================================

CREATE OR REPLACE GIT REPOSITORY PCB_CV_REPO
    API_INTEGRATION = GITHUB_INTEGRATION_PCB_CV
    GIT_CREDENTIALS = PCB_CV.PUBLIC.GITHUB_SECRET
    ORIGIN = 'https://github.com/Snowflake-Labs/sfguide-defect-detection-using-distributed-pytorch-with-snowflake-notebooks.git'
    COMMENT = 'Git repository for PCB Defect Detection demo';

-- Fetch latest code from Git
ALTER GIT REPOSITORY PCB_CV_REPO FETCH;

-- ============================================================================
-- 7. Create Stages
-- ============================================================================
CREATE OR REPLACE STAGE PCB_CV_DEEP_PCB_DATASET_STAGE
    COMMENT = 'Stage for storing PCB images and labels from DeepPCB dataset';

-- ============================================================================
-- 8. Create Image Repository (for SPCS model deployment)
-- ============================================================================
CREATE OR REPLACE IMAGE REPOSITORY IMAGE_REPO
    COMMENT = 'Image repository for model container images';

-- ============================================================================
-- 9. Create Compute Pools
-- ============================================================================
-- GPU compute pool for distributed PyTorch training (1 GPU)
CREATE COMPUTE POOL IF NOT EXISTS PCB_CV_COMPUTEPOOL
    MIN_NODES = 1
    MAX_NODES = 1
    INSTANCE_FAMILY = GPU_NV_L
    AUTO_SUSPEND_SECS = 600
    COMMENT = 'GPU compute pool for distributed PyTorch training (Large)';

-- GPU compute pool for model inference service (1 GPU)
CREATE COMPUTE POOL IF NOT EXISTS PCB_CV_SERVICE_COMPUTEPOOL
    MIN_NODES = 1
    MAX_NODES = 1
    INSTANCE_FAMILY = GPU_NV_M
    AUTO_SUSPEND_SECS = 600
    COMMENT = 'GPU compute pool for model inference service (Medium)';

-- ============================================================================
-- 10. Create Tables
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
-- 11. Create Notebook from Git Repository
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

-- Grant usage on the notebook (for other users if needed)
GRANT USAGE ON NOTEBOOK TRAIN_PCB_DEFECT_MODEL TO ROLE PCB_CV_ROLE;

-- ============================================================================
-- 12. Create Streamlit App from Git Repository
-- ============================================================================
CREATE OR REPLACE STREAMLIT PCB_DEFECT_DETECTION_APP
    FROM '@PCB_CV_REPO/branches/main/streamlit'
    MAIN_FILE = 'app.py'
    QUERY_WAREHOUSE = PCB_CV_WH
    TITLE = 'PCB Defect Detection'
    COMMENT = '{"origin":"sf_sit-is", "name":"pcb_defect_detection", "version":{"major":1, "minor":0}, "attributes":{"is_quickstart":1, "source":"streamlit"}}';

ALTER STREAMLIT PCB_DEFECT_DETECTION_APP ADD LIVE VERSION FROM LAST;
ALTER STREAMLIT PCB_DEFECT_DETECTION_APP SET EXTERNAL_ACCESS_INTEGRATIONS = ('allow_all_integration');

-- Grant usage on the Streamlit app (for other users if needed)
GRANT USAGE ON STREAMLIT PCB_DEFECT_DETECTION_APP TO ROLE PCB_CV_ROLE;

-- ============================================================================
-- 13. Create Data Loading Procedure
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

def load_data(session):
    """
    Download DeepPCB dataset and load into Snowflake tables.
    Dataset: https://github.com/tangsanli5201/DeepPCB
    """
    
    # DeepPCB dataset URL (hosted on GitHub)
    DATASET_URL = "https://github.com/tangsanli5201/DeepPCB/raw/master/PCBData.zip"
    
    print("Downloading DeepPCB dataset...")
    response = requests.get(DATASET_URL, timeout=300)
    
    if response.status_code != 200:
        return f"Failed to download dataset: HTTP {response.status_code}"
    
    print("Extracting dataset...")
    zip_file = zipfile.ZipFile(io.BytesIO(response.content))
    
    # Parse dataset structure
    # PCBData/
    #   group00001/
    #     00041000_temp.jpg (template)
    #     00041000_test.jpg (test image with defects)
    #     00041000.txt (labels)
    
    data_records = []
    
    for name in zip_file.namelist():
        # Process test images (ones with defects)
        if name.endswith('_test.jpg'):
            # Get corresponding label file
            base_name = name.replace('_test.jpg', '')
            label_file = base_name + '.txt'
            
            # Extract filename without path
            filename = os.path.basename(name).replace('_test.jpg', '')
            
            try:
                # Read and encode image
                with zip_file.open(name) as img_file:
                    img_bytes = img_file.read()
                    image_b64 = base64.b64encode(img_bytes).decode('utf-8')
                
                # Read labels
                if label_file in zip_file.namelist():
                    with zip_file.open(label_file) as lbl_file:
                        for line in lbl_file.read().decode('utf-8').strip().split('\n'):
                            if line.strip():
                                parts = line.strip().split()
                                if len(parts) >= 5:
                                    xmin, ymin, xmax, ymax = map(float, parts[:4])
                                    defect_class = int(parts[4])
                                    
                                    data_records.append({
                                        'FILENAME': filename,
                                        'IMAGE_DATA': image_b64,
                                        'CLASS': defect_class,
                                        'XMIN': xmin,
                                        'YMIN': ymin,
                                        'XMAX': xmax,
                                        'YMAX': ymax
                                    })
            except Exception as e:
                print(f"Error processing {name}: {e}")
                continue
    
    if not data_records:
        return "No valid records found in dataset"
    
    print(f"Found {len(data_records)} defect annotations")
    
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
-- 14. Setup Complete - Display Summary
-- ============================================================================
SELECT 'PCB CV Setup Complete!' AS STATUS;

SELECT 'OBJECT TYPE' AS TYPE, 'NAME' AS NAME, 'NOTES' AS NOTES
UNION ALL SELECT '───────────────', '─────────────────────────────────', '─────────────────────────'
UNION ALL SELECT 'Role', 'PCB_CV_ROLE', 'Granted to current user'
UNION ALL SELECT 'Database', 'PCB_CV', ''
UNION ALL SELECT 'Warehouse', 'PCB_CV_WH', 'SMALL, auto-suspend 5 min'
UNION ALL SELECT 'Git Repo', 'PCB_CV_REPO', 'GitHub integration'
UNION ALL SELECT 'Stage', 'PCB_CV_DEEP_PCB_DATASET_STAGE', 'For images & labels'
UNION ALL SELECT 'Image Repo', 'IMAGE_REPO', 'For SPCS containers'
UNION ALL SELECT 'Compute Pool', 'PCB_CV_COMPUTEPOOL', 'GPU_NV_L (1 node) - Training'
UNION ALL SELECT 'Compute Pool', 'PCB_CV_SERVICE_COMPUTEPOOL', 'GPU_NV_M (1 node) - Inference'
UNION ALL SELECT 'Table', 'TRAINING_DATA', ''
UNION ALL SELECT 'Table', 'TEST_DATA', ''
UNION ALL SELECT 'Table', 'DETECTION_OUTPUTS', ''
UNION ALL SELECT 'Notebook', 'TRAIN_PCB_DEFECT_MODEL', 'Loaded from Git'
UNION ALL SELECT 'Streamlit', 'PCB_DEFECT_DETECTION_APP', 'Loaded from Git'
UNION ALL SELECT 'Procedure', 'LOAD_DEEPPCB_DATA()', 'Downloads & loads dataset';

-- ============================================================================
-- 15. Load Training Data
-- ============================================================================
CALL LOAD_DEEPPCB_DATA();

-- ============================================================================
-- NEXT STEPS:
-- 1. Open the notebook: TRAIN_PCB_DEFECT_MODEL
-- 2. Run all cells to train the model
-- ============================================================================
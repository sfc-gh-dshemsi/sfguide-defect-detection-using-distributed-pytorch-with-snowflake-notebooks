"""
Data Loader for PCB Defect Detection Dashboard

Provides parallel query execution and caching utilities.
"""

from typing import Dict, List
from concurrent.futures import ThreadPoolExecutor, as_completed
import pandas as pd
import streamlit as st

from utils.query_registry import execute_query


def run_queries_parallel(
    session,
    queries: Dict[str, str],
    max_workers: int = 4
) -> Dict[str, pd.DataFrame]:
    """
    Execute multiple queries in parallel.
    
    Args:
        session: Snowflake Snowpark session
        queries: Dict mapping result keys to SQL strings
        max_workers: Maximum parallel threads
    
    Returns:
        Dict mapping keys to result DataFrames
    
    Raises:
        RuntimeError: If any query fails
    """
    results = {}
    errors = []
    
    def run_single_query(key: str, sql: str):
        try:
            return key, execute_query(session, sql, key)
        except Exception as e:
            return key, e
    
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {
            executor.submit(run_single_query, key, sql): key
            for key, sql in queries.items()
        }
        
        for future in as_completed(futures):
            key, result = future.result()
            if isinstance(result, Exception):
                errors.append(f"{key}: {result}")
            else:
                results[key] = result
    
    if errors:
        raise RuntimeError(f"Query errors: {'; '.join(errors)}")
    
    return results


@st.cache_data(ttl=60)
def load_defect_summary(_session) -> pd.DataFrame:
    """Load defect summary with caching."""
    from utils.query_registry import DEFECT_SUMMARY_SQL
    return execute_query(_session, DEFECT_SUMMARY_SQL, "defect_summary")


@st.cache_data(ttl=60)
def load_daily_trends(_session) -> pd.DataFrame:
    """Load daily trends with caching."""
    from utils.query_registry import DAILY_TRENDS_SQL
    return execute_query(_session, DAILY_TRENDS_SQL, "daily_trends")


@st.cache_data(ttl=60)
def load_factory_line_data(_session) -> pd.DataFrame:
    """Load factory line data with caching."""
    from utils.query_registry import FACTORY_LINE_SQL
    return execute_query(_session, FACTORY_LINE_SQL, "factory_line_defects")


@st.cache_data(ttl=60)
def load_recent_defects(_session) -> pd.DataFrame:
    """Load recent defects with caching."""
    from utils.query_registry import RECENT_DEFECTS_SQL
    return execute_query(_session, RECENT_DEFECTS_SQL, "recent_defects")


@st.cache_data(ttl=300)
def list_stage_images(_session, limit: int = 100) -> List[str]:
    """
    List PCB images available in the MODEL_STAGE.
    
    Args:
        _session: Snowflake Snowpark session
        limit: Maximum number of images to return
    
    Returns:
        List of stage file paths
    """
    try:
        # LIST command returns file metadata
        result = _session.sql(
            "LIST @MODEL_STAGE/raw/deeppcb/ PATTERN='.*\\.jpg'"
        ).collect()
        
        # Extract file paths from the result
        file_paths = []
        for row in result[:limit]:
            # The 'name' column contains the full stage path
            file_path = row['name'] if 'name' in row.asDict() else str(row[0])
            file_paths.append(file_path)
        
        return file_paths
    except Exception as e:
        # Return empty list if stage doesn't exist or has no images
        return []


def load_stage_image(_session, stage_path: str, local_dir: str = "/tmp/pcb_images") -> str:
    """
    Download an image from Snowflake stage to local filesystem.
    
    Args:
        _session: Snowflake Snowpark session
        stage_path: Full stage path (e.g., 'model_stage/raw/deeppcb/group00041/...')
        local_dir: Local directory to download to
    
    Returns:
        Local file path of downloaded image
    """
    import os
    
    os.makedirs(local_dir, exist_ok=True)
    
    # Extract just the stage reference part
    # stage_path format: "model_stage/raw/deeppcb/group00041/00041/00041001_temp.jpg"
    # We need: "@MODEL_STAGE/raw/deeppcb/group00041/00041/00041001_temp.jpg"
    if stage_path.startswith("model_stage/"):
        stage_ref = "@MODEL_STAGE/" + stage_path[len("model_stage/"):]
    else:
        stage_ref = stage_path
    
    # Download the file
    _session.file.get(stage_ref, local_dir)
    
    # Return the local path
    filename = os.path.basename(stage_path)
    return os.path.join(local_dir, filename)


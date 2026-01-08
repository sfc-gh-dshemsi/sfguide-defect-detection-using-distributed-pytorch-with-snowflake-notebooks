"""
Query Registry for PCB Defect Detection Dashboard

All SQL queries must be registered here for:
1. Independent testability via ./run.sh test
2. Fail-fast error handling
3. Centralized query management
"""

from typing import Dict, Optional
import pandas as pd

# Global registry of all queries
_QUERY_REGISTRY: Dict[str, dict] = {}


def register_query(
    name: str,
    sql: str,
    description: str,
    min_rows: int = 0
) -> str:
    """
    Register a SQL query for testing and execution.
    
    Args:
        name: Unique identifier for the query
        sql: SQL query string
        description: Human-readable description
        min_rows: Minimum expected rows (0 = no minimum)
    
    Returns:
        The SQL query string (for inline use)
    """
    _QUERY_REGISTRY[name] = {
        'sql': sql,
        'description': description,
        'min_rows': min_rows
    }
    return sql


def get_all_queries() -> Dict[str, dict]:
    """Return all registered queries."""
    return _QUERY_REGISTRY.copy()


def execute_query(session, query: str, name: str = "query") -> pd.DataFrame:
    """
    Execute a SQL query with fail-fast error handling.
    
    Args:
        session: Snowflake Snowpark session
        query: SQL query string
        name: Descriptive name for error messages
    
    Returns:
        DataFrame with query results
    
    Raises:
        RuntimeError: If query fails or returns None
    """
    try:
        result = session.sql(query).to_pandas()
        if result is None:
            raise RuntimeError(f"Query '{name}' returned None")
        return result
    except Exception as e:
        raise RuntimeError(f"Query '{name}' failed: {e}") from e


# =============================================================================
# REGISTERED QUERIES - YOLO Model (DEFECT_LOGS table)
# =============================================================================

# Defect Summary by Class (YOLO)
DEFECT_SUMMARY_YOLO_SQL = register_query(
    "defect_summary",
    """
    SELECT 
        DETECTED_CLASS,
        COUNT(*) AS DEFECT_COUNT,
        AVG(CONFIDENCE_SCORE) AS AVG_CONFIDENCE,
        MIN(INFERENCE_TIMESTAMP) AS FIRST_DETECTED,
        MAX(INFERENCE_TIMESTAMP) AS LAST_DETECTED
    FROM DEFECT_LOGS
    GROUP BY DETECTED_CLASS
    ORDER BY DEFECT_COUNT DESC
    """,
    "Defect counts by class",
    min_rows=0
)

# Daily Defect Trends
DAILY_TRENDS_SQL = register_query(
    "daily_trends",
    """
    SELECT 
        DATE_TRUNC('DAY', INFERENCE_TIMESTAMP) AS DETECTION_DATE,
        DETECTED_CLASS,
        COUNT(*) AS DEFECT_COUNT,
        AVG(CONFIDENCE_SCORE) AS AVG_CONFIDENCE
    FROM DEFECT_LOGS
    GROUP BY DATE_TRUNC('DAY', INFERENCE_TIMESTAMP), DETECTED_CLASS
    ORDER BY DETECTION_DATE DESC
    LIMIT 100
    """,
    "Daily defect trends",
    min_rows=0
)

# Factory Line Performance
FACTORY_LINE_SQL = register_query(
    "factory_line_defects",
    """
    SELECT 
        COALESCE(m.FACTORY_LINE_ID, 'UNKNOWN') AS FACTORY_LINE_ID,
        d.DETECTED_CLASS,
        COUNT(*) AS DEFECT_COUNT,
        AVG(d.CONFIDENCE_SCORE) AS AVG_CONFIDENCE
    FROM DEFECT_LOGS d
    LEFT JOIN PCB_METADATA m ON d.BOARD_ID = m.BOARD_ID
    GROUP BY COALESCE(m.FACTORY_LINE_ID, 'UNKNOWN'), d.DETECTED_CLASS
    ORDER BY DEFECT_COUNT DESC
    """,
    "Defects by factory line",
    min_rows=0
)

# Total Defect Count
TOTAL_DEFECTS_SQL = register_query(
    "total_defects",
    """
    SELECT COUNT(*) AS TOTAL_DEFECTS FROM DEFECT_LOGS
    """,
    "Total defect count",
    min_rows=1
)

# Recent Defects
RECENT_DEFECTS_SQL = register_query(
    "recent_defects",
    """
    SELECT 
        INFERENCE_ID,
        BOARD_ID,
        DETECTED_CLASS,
        CONFIDENCE_SCORE,
        IMAGE_PATH,
        INFERENCE_TIMESTAMP
    FROM DEFECT_LOGS
    ORDER BY INFERENCE_TIMESTAMP DESC
    LIMIT 50
    """,
    "Recent defect detections",
    min_rows=0
)

# PCB Metadata Count
PCB_COUNT_SQL = register_query(
    "pcb_count",
    """
    SELECT COUNT(*) AS TOTAL_PCBS FROM PCB_METADATA
    """,
    "Total PCB count",
    min_rows=1
)

# =============================================================================
# REGISTERED QUERIES - R-CNN Model (DETECTION_OUTPUTS table)
# =============================================================================

# Defect Summary by Class (R-CNN)
DEFECT_SUMMARY_RCNN_SQL = register_query(
    "defect_summary_rcnn",
    """
    SELECT 
        LABEL AS DETECTED_CLASS,
        COUNT(*) AS DEFECT_COUNT,
        AVG(SCORE) AS AVG_CONFIDENCE
    FROM DETECTION_OUTPUTS
    WHERE LABEL > 0
    GROUP BY LABEL
    ORDER BY DEFECT_COUNT DESC
    """,
    "Defect counts by class (R-CNN)",
    min_rows=0
)

# Total Defect Count (R-CNN)
TOTAL_DEFECTS_RCNN_SQL = register_query(
    "total_defects_rcnn",
    """
    SELECT COUNT(*) AS TOTAL_DEFECTS FROM DETECTION_OUTPUTS WHERE LABEL > 0
    """,
    "Total defect count (R-CNN)",
    min_rows=1
)

# Recent Defects (R-CNN)
RECENT_DEFECTS_RCNN_SQL = register_query(
    "recent_defects_rcnn",
    """
    SELECT 
        LABEL,
        SCORE AS CONFIDENCE_SCORE,
        BOX,
        IMAGE_DATA
    FROM DETECTION_OUTPUTS
    WHERE LABEL > 0
    ORDER BY SCORE DESC
    LIMIT 50
    """,
    "Recent defect detections (R-CNN)",
    min_rows=0
)

# =============================================================================
# HELPER FUNCTIONS - Dynamic Query Selection
# =============================================================================

# Rename YOLO queries for clarity
DEFECT_SUMMARY_YOLO_SQL = DEFECT_SUMMARY_SQL
TOTAL_DEFECTS_YOLO_SQL = TOTAL_DEFECTS_SQL
RECENT_DEFECTS_YOLO_SQL = RECENT_DEFECTS_SQL

def get_query_for_model(base_query_name: str, model: str) -> str:
    """
    Get the appropriate query based on the selected model.
    
    Args:
        base_query_name: Base query name (e.g., 'defect_summary')
        model: Either 'YOLO' or 'R-CNN'
    
    Returns:
        SQL query string for the specified model
    """
    if model == 'R-CNN':
        query_map = {
            'defect_summary': DEFECT_SUMMARY_RCNN_SQL,
            'total_defects': TOTAL_DEFECTS_RCNN_SQL,
            'recent_defects': RECENT_DEFECTS_RCNN_SQL,
        }
    else:  # YOLO
        query_map = {
            'defect_summary': DEFECT_SUMMARY_YOLO_SQL,
            'total_defects': TOTAL_DEFECTS_YOLO_SQL,
            'recent_defects': RECENT_DEFECTS_YOLO_SQL,
            'daily_trends': DAILY_TRENDS_SQL,
            'factory_line': FACTORY_LINE_SQL,
            'pcb_count': PCB_COUNT_SQL,
        }
    
    return query_map.get(base_query_name, '')

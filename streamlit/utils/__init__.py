"""
PCB Defect Detection Dashboard - Utilities

Provides data loading and query execution helpers for the Streamlit app.
"""

# Re-export commonly used functions for convenience
from utils.data_loader import (
    load_defect_summary,
    load_daily_trends,
    load_factory_line_data,
    load_recent_defects,
    list_stage_images,
    load_stage_image
)

from utils.query_registry import (
    execute_query,
    DEFECT_SUMMARY_SQL,
    DAILY_TRENDS_SQL,
    FACTORY_LINE_SQL,
    TOTAL_DEFECTS_SQL,
    RECENT_DEFECTS_SQL,
    PCB_COUNT_SQL
)

__all__ = [
    'load_defect_summary',
    'load_daily_trends',
    'load_factory_line_data',
    'load_recent_defects',
    'list_stage_images',
    'load_stage_image',
    'execute_query',
    'DEFECT_SUMMARY_SQL',
    'DAILY_TRENDS_SQL',
    'FACTORY_LINE_SQL',
    'TOTAL_DEFECTS_SQL',
    'RECENT_DEFECTS_SQL',
    'PCB_COUNT_SQL'
]
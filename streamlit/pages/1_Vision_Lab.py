"""
PCB Defect Detection - Vision Lab

Interactive inference interface with RAG-powered defect guidance.
Supports both YOLOv12 and Faster R-CNN models.
"""

import streamlit as st
from snowflake.snowpark.context import get_active_session
from PIL import Image
import io

from utils.data_loader import load_recent_defects, list_stage_images, load_stage_image
from utils.query_registry import execute_query

# =============================================================================
# PAGE CONFIGURATION
# =============================================================================

st.set_page_config(
    page_title="Vision Lab | PCB Defect Detection",
    page_icon="🔬",
    layout="wide"
)

# Dark theme styling
st.markdown("""
<style>
    .stApp {
        background-color: #0f172a;
    }
    .detection-card {
        background: linear-gradient(135deg, #1e293b 0%, #0f172a 100%);
        border: 1px solid #334155;
        border-radius: 12px;
        padding: 1rem;
        margin-bottom: 1rem;
    }
    .defect-badge {
        display: inline-block;
        padding: 0.25rem 0.75rem;
        border-radius: 9999px;
        font-size: 0.75rem;
        font-weight: 600;
        margin-right: 0.5rem;
        margin-bottom: 0.5rem;
    }
    .defect-open { background-color: #dc2626; color: white; }
    .defect-short { background-color: #ea580c; color: white; }
    .defect-mousebite { background-color: #ca8a04; color: white; }
    .defect-spur { background-color: #16a34a; color: white; }
    .defect-copper { background-color: #2563eb; color: white; }
    .defect-pin-hole { background-color: #7c3aed; color: white; }
    .chat-message {
        background: rgba(59, 130, 246, 0.08);
        border-left: 3px solid #3b82f6;
        padding: 0.75rem 1rem;
        margin-top: 0.5rem;
        border-radius: 0 8px 8px 0;
    }
</style>
""", unsafe_allow_html=True)

# =============================================================================
# SIDEBAR
# =============================================================================

with st.sidebar:
    st.image("https://www.snowflake.com/wp-content/themes/flavor/flavortheme/assets/images/logo.svg", width=150)
    st.title("PCB Defect Detection")
    st.markdown("---")
    
    # Get selected model from session state (set in main app.py)
    selected_model = st.session_state.get('selected_model', 'YOLOv12')
    
    st.info(f"**Active Model:** {selected_model}")
    st.markdown("*Change model in Executive Overview*")
    
    st.markdown("---")
    st.markdown("### Model Info")
    
    if selected_model == "YOLOv12":
        st.markdown("**Model**: YOLOv12n")
        st.markdown("**Type**: Single-stage detector")
        st.markdown("**Speed**: Real-time (~30 FPS)")
    else:  # Faster R-CNN
        st.markdown("**Model**: Faster R-CNN + ResNet50")
        st.markdown("**Type**: Two-stage detector")
        st.markdown("**Speed**: High accuracy (~5 FPS)")
    
    st.markdown("**Classes**: 6 defect types")
    st.markdown("**Input Size**: 640x640")

# =============================================================================
# HEADER
# =============================================================================

st.title("🔬 Vision Lab")
st.markdown("*Interactive PCB defect detection with AI-powered guidance*")

# =============================================================================
# MAIN CONTENT
# =============================================================================

session = get_active_session()
selected_model = st.session_state.get('selected_model', 'YOLOv12')

# Split layout
col_left, col_right = st.columns([1, 1])

with col_left:
    st.subheader("📸 Image Analysis")
    
    # Model-specific data source info
    if selected_model == "YOLOv12":
        data_source_help = "YOLO: Browse images from @MODEL_STAGE/raw/deeppcb/ or upload new"
        stage_available = True
    else:  # Faster R-CNN
        data_source_help = "R-CNN: Upload new images (stage browsing available after YOLO notebook run)"
        # Check if stage has data (only if YOLO was run)
        try:
            stage_check = session.sql("LIST @MODEL_STAGE/raw/deeppcb/ PATTERN='.*\\.jpg'").collect()
            stage_available = len(stage_check) > 0
        except:
            stage_available = False
    
    # Image source selection
    if stage_available:
        image_source = st.radio(
            "Image Source",
            ["Browse Stage", "Upload New"],
            horizontal=True,
            help=data_source_help
        )
    else:
        image_source = "Upload New"
        st.info(f"📁 Stage browsing available after running YOLO notebook to cache dataset.")
    
    # Variable to hold the loaded image
    image = None
    image_caption = None
    
    if image_source == "Browse Stage" and stage_available:
        # Load images from Snowflake stage
        stage_images = list_stage_images(session, limit=100)
        
        if stage_images:
            # Create display names (just the filename for readability)
            import os
            display_names = [os.path.basename(p) for p in stage_images]
            
            selected_idx = st.selectbox(
                "Select a PCB image from stage",
                range(len(stage_images)),
                format_func=lambda i: display_names[i],
                help=f"Found {len(stage_images)} images in @MODEL_STAGE/raw/deeppcb/"
            )
            
            if st.button("📥 Load Image", type="secondary"):
                with st.spinner("Downloading image from stage..."):
                    try:
                        local_path = load_stage_image(session, stage_images[selected_idx])
                        image = Image.open(local_path)
                        image_caption = f"Stage: {display_names[selected_idx]}"
                        st.session_state['loaded_image'] = image
                        st.session_state['loaded_caption'] = image_caption
                    except Exception as e:
                        st.error(f"Failed to load image: {e}")
            
            # Check if we have a previously loaded image in session state
            if 'loaded_image' in st.session_state:
                image = st.session_state['loaded_image']
                image_caption = st.session_state.get('loaded_caption', 'PCB Image')
        else:
            st.info("No images found in stage. Run the notebook first to download the Deep PCB dataset.")
    
    else:
        # File uploader
        uploaded_file = st.file_uploader(
            f"Upload a PCB image for {selected_model} defect analysis",
            type=['jpg', 'jpeg', 'png'],
            help=f"Upload a PCB image to run {selected_model} inference"
        )
        
        if uploaded_file is not None:
            image = Image.open(uploaded_file)
            image_caption = f"Uploaded: {uploaded_file.name}"
    
    # Display and analyze the image (common for both sources)
    if image is not None:
        st.image(image, caption=image_caption, use_container_width=True)
        
        # Inference button
        if st.button(f"🔍 Detect Defects ({selected_model})", type="primary"):
            with st.spinner(f"Running {selected_model} inference..."):
                # Note: In production, this would call a model inference service
                # For demo, we show a placeholder result
                model_desc = "YOLOv12 (single-stage, real-time)" if selected_model == "YOLOv12" else "Faster R-CNN (two-stage, high accuracy)"
                
                st.markdown(f"""
                <div class="detection-card">
                    <h4 style="color: #e2e8f0; margin-bottom: 0.5rem;">Detection Results ({selected_model})</h4>
                    <p style="color: #94a3b8;">
                        ⚠️ <strong>Demo Mode</strong>: Model inference requires the trained model 
                        to be deployed as an inference service. Run the corresponding notebook 
                        ({selected_model}) to train the model, then deploy via Snowpark Container 
                        Services or ML Registry for real-time inference.
                    </p>
                    <p style="color: #94a3b8; font-size: 0.875rem; margin-top: 0.5rem;">
                        <strong>Model:</strong> {model_desc}
                    </p>
                </div>
                """, unsafe_allow_html=True)
                
                # Simulated detections for demo
                st.markdown("**Simulated Detections:**")
                st.markdown("""
                <span class="defect-badge defect-mousebite">mousebite (0.87)</span>
                <span class="defect-badge defect-short">short (0.72)</span>
                """, unsafe_allow_html=True)
    else:
        # Show sample from recent detections
        st.info("Select an image from the stage above or upload a new image.")
        
        # Show recent detections based on selected model
        try:
            recent_df = load_recent_defects(session, selected_model)
            if not recent_df.empty:
                st.markdown(f"### Recent Detections ({selected_model})")
                
                # Column names differ between models
                if selected_model == "YOLOv12":
                    # DEFECT_LOGS schema
                    for _, row in recent_df.head(5).iterrows():
                        defect_class = row['DETECTED_CLASS'].lower().replace('-', '')
                        confidence = row['CONFIDENCE_SCORE']
                        
                        st.markdown(f"""
                        <div class="detection-card">
                            <span class="defect-badge defect-{defect_class}">{row['DETECTED_CLASS']} ({confidence:.2f})</span>
                            <br/>
                            <small style="color: #94a3b8;">
                                Board: {row.get('BOARD_ID', 'N/A')} | Image: {row.get('IMAGE_PATH', 'N/A')}
                            </small>
                        </div>
                        """, unsafe_allow_html=True)
                else:  # Faster R-CNN
                    # DETECTION_OUTPUTS schema
                    for _, row in recent_df.head(5).iterrows():
                        label = int(row.get('LABEL', 0))
                        confidence = float(row.get('CONFIDENCE_SCORE', 0))
                        
                        # Map label to class name
                        class_names = {1: "open", 2: "short", 3: "mousebite", 4: "spur", 5: "copper", 6: "pin-hole"}
                        defect_class = class_names.get(label, "unknown")
                        
                        st.markdown(f"""
                        <div class="detection-card">
                            <span class="defect-badge defect-{defect_class}">{defect_class} ({confidence:.2f})</span>
                            <br/>
                            <small style="color: #94a3b8;">Class ID: {label}</small>
                        </div>
                        """, unsafe_allow_html=True)
        except Exception as e:
            st.info(f"No recent detections available for {selected_model}. Run the notebook to generate inference data.")

with col_right:
    st.subheader("🤖 Defect Guidance")
    
    # Query mode toggle
    query_mode = st.radio(
        "Query Mode",
        ["Query Manuals (RAG)", "Query Data (Analytics)"],
        horizontal=True
    )
    
    # Chat input
    user_question = st.text_input(
        "Ask about defects or procedures",
        placeholder="e.g., What causes mousebite defects?"
    )
    
    if user_question:
        if query_mode == "Query Manuals (RAG)":
            # RAG response (would use Cortex Search in production)
            st.markdown(f"""
            <div class="chat-message">
                <div style="color: #60a5fa; font-size: 0.75rem; text-transform: uppercase; 
                            letter-spacing: 0.05em; margin-bottom: 0.25rem;">🤖 AI Response (Cortex Search)</div>
                <p style="color: #e2e8f0; line-height: 1.5; margin: 0;">
                    <strong>Mousebite defects</strong> are small irregularities along the PCB edge, 
                    typically caused by improper routing or depanelization. According to IPC-A-610 
                    Class 2 standards, mousebites are acceptable if they don't reduce conductor 
                    spacing below minimum requirements.
                    <br/><br/>
                    <strong>Common causes:</strong>
                    <ul style="margin: 0.5rem 0; padding-left: 1.5rem;">
                        <li>Worn router bits</li>
                        <li>Improper feed rate during depanelization</li>
                        <li>Incorrect tab placement in panel design</li>
                    </ul>
                    <strong>Remediation:</strong> Replace worn tooling and verify feed rates.
                </p>
            </div>
            """, unsafe_allow_html=True)
        else:
            # Analytics query (would use Cortex Analyst in production)
            st.markdown(f"""
            <div class="chat-message">
                <div style="color: #60a5fa; font-size: 0.75rem; text-transform: uppercase; 
                            letter-spacing: 0.05em; margin-bottom: 0.25rem;">📊 Analytics Response (Cortex Analyst)</div>
                <p style="color: #e2e8f0; line-height: 1.5; margin: 0;">
                    Based on the defect logs, here's the relevant data analysis:
                </p>
            </div>
            """, unsafe_allow_html=True)
            
            # Show relevant data
            try:
                # Query based on selected model
                if selected_model == "YOLOv12":
                    defect_query = f"""
                    SELECT DETECTED_CLASS, COUNT(*) as COUNT, AVG(CONFIDENCE_SCORE) as AVG_CONF
                    FROM DEFECT_LOGS
                    WHERE LOWER(DETECTED_CLASS) LIKE '%{user_question.lower().split()[0]}%'
                    GROUP BY DETECTED_CLASS
                    """
                else:  # Faster R-CNN
                    defect_query = f"""
                    SELECT LABEL, COUNT(*) as COUNT, AVG(SCORE) as AVG_CONF
                    FROM DETECTION_OUTPUTS
                    WHERE LABEL > 0
                    GROUP BY LABEL
                    """
                
                result = execute_query(session, defect_query, "user_query")
                if not result.empty:
                    st.dataframe(result, use_container_width=True)
            except:
                st.info("No matching data found for your query.")
    
    # Quick reference
    st.markdown("---")
    st.markdown("### 📚 Defect Reference")
    
    defect_info = {
        "open": ("Critical", "Broken trace causing circuit discontinuity"),
        "short": ("Critical", "Unintended connection between traces"),
        "mousebite": ("Minor", "Irregular edge from depanelization"),
        "spur": ("Major", "Unwanted copper protrusion"),
        "copper": ("Major", "Exposed copper area"),
        "pin-hole": ("Minor", "Small void in copper plating")
    }
    
    for defect, (severity, desc) in defect_info.items():
        severity_color = "#dc2626" if severity == "Critical" else "#ca8a04" if severity == "Major" else "#16a34a"
        st.markdown(f"""
        <div style="display: flex; align-items: center; margin-bottom: 0.5rem;">
            <span class="defect-badge defect-{defect}">{defect}</span>
            <span style="color: {severity_color}; font-size: 0.75rem; margin-right: 0.5rem;">[{severity}]</span>
            <span style="color: #94a3b8; font-size: 0.875rem;">{desc}</span>
        </div>
        """, unsafe_allow_html=True)

# =============================================================================
# FOOTER
# =============================================================================

st.markdown("---")
st.caption(f"Vision Lab • {selected_model} Inference • Cortex RAG Integration")


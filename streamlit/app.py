# ============================================================================
# PCB Defect Detection - Streamlit App
# ============================================================================
# Interactive defect detection on PCB images using SPCS model service
# ============================================================================

import streamlit as st
import pandas as pd
import json
import base64
import io
from PIL import Image, ImageDraw
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.patches as patches

# Page config
st.set_page_config(
    page_title="PCB Defect Detection",
    page_icon="🔍",
    layout="wide"
)

# Get Snowflake session
from snowflake.snowpark.context import get_active_session
session = get_active_session()

# ============================================================================
# Header with Snowflake Logo
# ============================================================================
st.image("assets/snowflake_logo.png", width=120)
st.title("🔍 :blue[PCB Defect Detection]")
st.markdown("**Computer Vision based Defect Detection and Classification**")
st.markdown("Detect manufacturing defects in PCB images using GPU-accelerated SPCS inference")

# Display PCB sample image
st.image("assets/pcb_sample.png", width=400, caption="Sample PCB Board")
st.markdown("---")

# ============================================================================
# Constants
# ============================================================================
CLASS_NAMES = {
    0: "background",
    1: "open",
    2: "short",
    3: "mousebite",
    4: "spur",
    5: "copper",
    6: "pin-hole"
}

CLASS_COLORS = {
    1: "#FF6B6B",  # open - red
    2: "#4ECDC4",  # short - teal
    3: "#45B7D1",  # mousebite - blue
    4: "#96CEB4",  # spur - green
    5: "#FFEAA7",  # copper - yellow
    6: "#DDA0DD",  # pin-hole - plum
}

# Model and service configuration
MODEL_NAME = "DEFECTDETECTIONMODEL"
MODEL_VERSION = "v1"
SERVICE_NAME = "DEFECTDETECTSERVICE"

# ============================================================================
# Helper Functions
# ============================================================================
@st.cache_data(ttl=60)
def check_service_status():
    """Check if the SPCS inference service is running."""
    try:
        services = session.sql("SHOW SERVICES").collect()
        for svc in services:
            if svc['name'] == SERVICE_NAME:
                return svc['status'] == 'READY'
    except:
        pass
    return False

def run_inference(image_b64):
    """Run inference on an image using the SPCS model service."""
    try:
        from snowflake.ml.registry import Registry
        
        # Get model from registry
        reg = Registry(session=session)
        model = reg.get_model(MODEL_NAME)
        mv = model.version(MODEL_VERSION)
        
        # Create input DataFrame
        input_df = pd.DataFrame({'IMAGE_DATA': [image_b64]})
        
        # Run inference via SPCS service
        result = mv.run(
            input_df, 
            function_name="predict", 
            service_name=SERVICE_NAME
        )
        
        return result
    except Exception as e:
        st.error(f"Inference error: {str(e)}")
        return None

def draw_detections_pil(image, detections, score_threshold=0.3):
    """Draw bounding boxes on image using PIL."""
    img_copy = image.copy()
    draw = ImageDraw.Draw(img_copy)
    
    boxes = detections.get('boxes', [])
    labels = detections.get('labels', [])
    scores = detections.get('scores', [])
    
    for box, label, score in zip(boxes, labels, scores):
        if score < score_threshold or label == 0:
            continue
            
        xmin, ymin, xmax, ymax = box
        color = CLASS_COLORS.get(label, "#FFFFFF")
        class_name = CLASS_NAMES.get(label, "unknown")
        
        # Draw box with thicker line
        for i in range(3):
            draw.rectangle(
                [xmin-i, ymin-i, xmax+i, ymax+i], 
                outline=color
            )
        
        # Draw label background
        label_text = f"{class_name}: {score:.0%}"
        text_bbox = draw.textbbox((xmin, ymin - 20), label_text)
        draw.rectangle(text_bbox, fill=color)
        draw.text((xmin, ymin - 20), label_text, fill="black")
    
    return img_copy

def draw_detections_matplotlib(image, detections, score_threshold=0.3, top_k=5):
    """Draw bounding boxes on image using matplotlib (like original app)."""
    boxes = detections.get('boxes', [])
    labels = detections.get('labels', [])
    scores = detections.get('scores', [])
    
    if not scores:
        return None
    
    # Get top k predictions
    data = pd.DataFrame({'box': boxes, 'label': labels, 'score': scores})
    top_data = data.nlargest(top_k, 'score')
    
    top_boxes = top_data['box'].tolist()
    top_labels = top_data['label'].tolist()
    top_scores = top_data['score'].tolist()
    
    # Setup the plot
    fig, ax = plt.subplots(figsize=(6, 6))
    ax.imshow(np.array(image))
    
    # Plot each bounding box
    for label, box, score in zip(top_labels, top_boxes, top_scores):
        if score < score_threshold or label == 0:
            continue
            
        xmin, ymin, xmax, ymax = box
        class_label = CLASS_NAMES.get(label, "unknown")
        
        # Create rectangle patch
        rect = patches.Rectangle(
            (xmin, ymin), xmax - xmin, ymax - ymin,
            linewidth=2, edgecolor='red', facecolor='none'
        )
        ax.text(
            xmin, ymin, f"{class_label}: {score:.2f}",
            verticalalignment='top', color='red',
            fontsize=10, weight='bold',
            bbox=dict(boxstyle='round', facecolor='white', alpha=0.8)
        )
        ax.add_patch(rect)
    
    plt.axis('off')
    return fig

def save_detection_results(image_b64, detections, filename="uploaded"):
    """Save detection results to Snowflake table."""
    try:
        boxes = detections.get('boxes', [])
        labels = detections.get('labels', [])
        scores = detections.get('scores', [])
        
        rows = []
        for i, (box, label, score) in enumerate(zip(boxes[:5], labels[:5], scores[:5])):
            rows.append({
                'IMAGE_DATA': image_b64,
                'OUTPUT': json.dumps(detections),
                'LABEL': int(label),
                'BOX': box,
                'SCORE': float(score)
            })
        
        if rows:
            df = session.create_dataframe(rows)
            df.write.mode("append").save_as_table("DETECTION_OUTPUTS")
            return True
    except Exception as e:
        st.warning(f"Could not save results: {e}")
    return False

# ============================================================================
# Service Status
# ============================================================================
service_ready = check_service_status()
if service_ready:
    st.success(f"✅ Inference Service `{SERVICE_NAME}` is running")
else:
    st.warning(f"⚠️ Service `{SERVICE_NAME}` may not be ready. Run the notebook to deploy the model first.")

# ============================================================================
# Sidebar
# ============================================================================
with st.sidebar:
    st.image("assets/snowflake_logo.png", width=80)
    st.header("⚙️ Settings")
    
    score_threshold = st.slider(
        "Confidence Threshold",
        min_value=0.1,
        max_value=0.9,
        value=0.3,
        step=0.05,
        help="Minimum confidence score for detections"
    )
    
    top_k = st.slider(
        "Max Detections",
        min_value=1,
        max_value=10,
        value=5,
        help="Maximum number of detections to show"
    )
    
    st.markdown("---")
    st.header("📊 Defect Classes")
    st.markdown("""
    The model detects 6 types of PCB defects:
    """)
    for class_id, class_name in CLASS_NAMES.items():
        if class_id > 0:
            color = CLASS_COLORS.get(class_id, "#FFFFFF")
            st.markdown(
                f"<span style='color:{color}; font-size: 20px;'>●</span> **{class_name}**", 
                unsafe_allow_html=True
            )
    
    st.markdown("---")
    st.caption(f"Model: `{MODEL_NAME}` v{MODEL_VERSION}")
    st.caption(f"Service: `{SERVICE_NAME}`")

# ============================================================================
# Main Content - Tabs
# ============================================================================
tab1, tab2, tab3 = st.tabs(["📤 Upload Image", "🗃️ Test Dataset", "📈 Results History"])

# ----------------------------------------------------------------------------
# Tab 1: Upload Image
# ----------------------------------------------------------------------------
with tab1:
    st.subheader("Upload a PCB Image for Defect Detection")
    
    st.markdown("""
    Image Base64 encoding is used to represent image data as text strings that can be easily 
    stored and transmitted. Upload a PCB image below to detect manufacturing defects.
    """)
    
    uploaded_file = st.file_uploader(
        "Choose an image...",
        type=["jpg", "jpeg", "png"],
        help="Upload a PCB image to detect defects"
    )
    
    if uploaded_file is not None:
        col1, col2 = st.columns(2)
        
        with col1:
            st.markdown("**:green[Raw Image]**")
            image = Image.open(uploaded_file).convert("RGB")
            st.image(image, use_container_width=True)
        
        if st.button("🔍 Detect Defects", type="primary", key="upload_detect"):
            with st.spinner("Running inference using custom trained RCNN Object Detection PyTorch Model..."):
                # Convert to base64
                buffer = io.BytesIO()
                image.save(buffer, format="JPEG")
                image_b64 = base64.b64encode(buffer.getvalue()).decode()
                
                # Run inference
                result = run_inference(image_b64)
                
                if result is not None and len(result) > 0:
                    output_str = result.iloc[0]['output']
                    detections = json.loads(output_str)
                    
                    with col2:
                        st.markdown("**:green[Detected Defects]**")
                        # Use matplotlib visualization like original app
                        fig = draw_detections_matplotlib(image, detections, score_threshold, top_k)
                        if fig:
                            st.pyplot(fig)
                            plt.close(fig)
                    
                    # Show detection details
                    st.markdown("---")
                    st.subheader("Detection Details")
                    
                    detection_data = []
                    for i, (box, label, score) in enumerate(zip(
                        detections.get('boxes', [])[:top_k],
                        detections.get('labels', [])[:top_k],
                        detections.get('scores', [])[:top_k]
                    )):
                        if score >= score_threshold and label > 0:
                            detection_data.append({
                                "#": i + 1,
                                "Defect": CLASS_NAMES.get(label, "unknown"),
                                "Confidence": f"{score:.1%}",
                                "Box": f"({box[0]:.0f}, {box[1]:.0f}) → ({box[2]:.0f}, {box[3]:.0f})"
                            })
                    
                    if detection_data:
                        st.dataframe(
                            pd.DataFrame(detection_data), 
                            use_container_width=True,
                            hide_index=True
                        )
                        
                        # Save results
                        if save_detection_results(image_b64, detections, uploaded_file.name):
                            st.success("✓ Results saved to DETECTION_OUTPUTS table")
                    else:
                        st.info("No defects detected above the confidence threshold")

# ----------------------------------------------------------------------------
# Tab 2: Test Dataset
# ----------------------------------------------------------------------------
with tab2:
    st.subheader("Test Dataset Samples")
    
    try:
        test_df = session.sql("SELECT * FROM TEST_DATA LIMIT 20").to_pandas()
        
        if len(test_df) > 0:
            selected_idx = st.selectbox(
                "Select a test image",
                range(len(test_df)),
                format_func=lambda x: f"Image {x+1}: {test_df.iloc[x]['FILENAME']} ({CLASS_NAMES.get(int(test_df.iloc[x]['CLASS']), 'unknown')})"
            )
            
            row = test_df.iloc[selected_idx]
            
            col1, col2 = st.columns(2)
            
            with col1:
                st.markdown("**:green[Test Image]**")
                image_data = base64.b64decode(row['IMAGE_DATA'])
                image = Image.open(io.BytesIO(image_data)).convert("RGB")
                st.image(image, use_container_width=True)
                
                st.markdown(f"""
                **Ground Truth:**
                - **Defect:** `{CLASS_NAMES.get(int(row['CLASS']), 'unknown')}`
                - **Box:** ({row['XMIN']:.0f}, {row['YMIN']:.0f}) → ({row['XMAX']:.0f}, {row['YMAX']:.0f})
                """)
            
            if st.button("🔍 Run Detection", type="primary", key="test_detect"):
                with st.spinner("Running SPCS inference..."):
                    result = run_inference(row['IMAGE_DATA'])
                    
                    if result is not None and len(result) > 0:
                        output_str = result.iloc[0]['output']
                        detections = json.loads(output_str)
                        
                        with col2:
                            st.markdown("**:green[Predicted Defects]**")
                            fig = draw_detections_matplotlib(image, detections, score_threshold, top_k)
                            if fig:
                                st.pyplot(fig)
                                plt.close(fig)
                            
                            # Show prediction summary
                            pred_labels = [l for l, s in zip(
                                detections.get('labels', []),
                                detections.get('scores', [])
                            ) if s >= score_threshold and l > 0]
                            
                            if pred_labels:
                                pred_classes = [CLASS_NAMES.get(l, "unknown") for l in pred_labels[:3]]
                                st.markdown(f"**Predictions:** {', '.join(pred_classes)}")
        else:
            st.warning("No test data found. Run `CALL LOAD_DEEPPCB_DATA()` first.")
    except Exception as e:
        st.error(f"Error loading test data: {str(e)}")

# ----------------------------------------------------------------------------
# Tab 3: Results History
# ----------------------------------------------------------------------------
with tab3:
    st.subheader("Detection Results History")
    
    try:
        results_df = session.sql("""
            SELECT 
                LABEL,
                SCORE,
                BOX
            FROM DETECTION_OUTPUTS 
            ORDER BY SCORE DESC
            LIMIT 50
        """).to_pandas()
        
        if len(results_df) > 0:
            # Add class names
            results_df['Defect'] = results_df['LABEL'].apply(
                lambda x: CLASS_NAMES.get(int(x), "unknown")
            )
            results_df['Confidence'] = results_df['SCORE'].apply(lambda x: f"{x:.1%}")
            
            st.dataframe(
                results_df[['Defect', 'Confidence', 'BOX']],
                use_container_width=True,
                hide_index=True
            )
            
            # Summary stats
            st.markdown("---")
            col1, col2, col3 = st.columns(3)
            with col1:
                st.metric("Total Detections", len(results_df))
            with col2:
                avg_conf = results_df['SCORE'].mean()
                st.metric("Avg Confidence", f"{avg_conf:.1%}")
            with col3:
                unique_defects = results_df['Defect'].nunique()
                st.metric("Defect Types", unique_defects)
        else:
            st.info("No detection results yet. Run inference to populate results.")
    except Exception as e:
        st.info("No detection results available yet.")

# ============================================================================
# Footer
# ============================================================================
st.markdown("---")
st.markdown(
    "<div style='text-align: center; color: #666;'>"
    "Built with Snowflake ML Registry + SPCS | PyTorch Faster R-CNN"
    "</div>",
    unsafe_allow_html=True
)

#!/usr/bin/env python3
"""
Script to download and convert DistilBERT to ONNX format for mobile deployment.
This creates a lightweight model optimized for on-device inference.
"""

import os
import sys
import torch
import numpy as np
from transformers import DistilBertTokenizer, DistilBertModel
import onnx
from onnxruntime.quantization import quantize_dynamic, QuantType
import json

def download_and_convert_model():
    """Download DistilBERT and convert to ONNX format."""
    
    print("📥 Downloading DistilBERT model...")
    model_name = "distilbert-base-uncased"
    tokenizer = DistilBertTokenizer.from_pretrained(model_name)
    model = DistilBertModel.from_pretrained(model_name)
    model.eval()
    
    # Create output directory
    output_dir = "../assets/models"
    os.makedirs(output_dir, exist_ok=True)
    
    # Save tokenizer vocabulary
    print("💾 Saving tokenizer vocabulary...")
    vocab = tokenizer.get_vocab()
    with open(f"{output_dir}/vocab.json", "w") as f:
        json.dump(vocab, f)
    
    # Prepare dummy input for ONNX export
    dummy_input = "find a book club event near me"
    inputs = tokenizer(dummy_input, return_tensors="pt", padding="max_length", 
                       max_length=128, truncation=True)
    
    # Export to ONNX
    print("🔄 Converting to ONNX format...")
    onnx_path = f"{output_dir}/distilbert.onnx"
    
    torch.onnx.export(
        model,
        (inputs["input_ids"], inputs["attention_mask"]),
        onnx_path,
        export_params=True,
        opset_version=11,
        do_constant_folding=True,
        input_names=["input_ids", "attention_mask"],
        output_names=["output"],
        dynamic_axes={
            "input_ids": {0: "batch_size", 1: "sequence"},
            "attention_mask": {0: "batch_size", 1: "sequence"},
            "output": {0: "batch_size", 1: "sequence"}
        }
    )
    
    # Quantize model for mobile (reduce size by ~75%)
    print("📦 Quantizing model for mobile...")
    quantized_path = f"{output_dir}/distilbert_quantized.onnx"
    quantize_dynamic(
        onnx_path,
        quantized_path,
        weight_type=QuantType.QUInt8
    )
    
    # Verify the model
    model_onnx = onnx.load(quantized_path)
    onnx.checker.check_model(model_onnx)
    
    # Get model size
    original_size = os.path.getsize(onnx_path) / (1024 * 1024)
    quantized_size = os.path.getsize(quantized_path) / (1024 * 1024)
    
    print(f"✅ Model conversion complete!")
    print(f"   Original size: {original_size:.2f} MB")
    print(f"   Quantized size: {quantized_size:.2f} MB")
    print(f"   Size reduction: {(1 - quantized_size/original_size)*100:.1f}%")
    
    # Create intent classification head (smaller model for mobile)
    create_intent_classifier()

def create_intent_classifier():
    """Create a lightweight intent classification model."""
    
    print("\n🎯 Creating intent classification layer...")
    
    # Categories for event classification
    categories = [
        "Social & Networking", "Entertainment", "Sports & Fitness",
        "Education & Learning", "Arts & Culture", "Food & Dining", 
        "Technology", "Community & Charity"
    ]
    
    # Location intents
    location_intents = ["near_me", "specific_location", "online", "any"]
    
    # Time intents
    time_intents = ["today", "tomorrow", "this_week", "this_weekend", "next_week", "any"]
    
    # Save classification metadata
    metadata = {
        "categories": categories,
        "location_intents": location_intents,
        "time_intents": time_intents,
        "max_sequence_length": 128
    }
    
    output_dir = "../assets/models"
    with open(f"{output_dir}/intent_metadata.json", "w") as f:
        json.dump(metadata, f, indent=2)
    
    print("✅ Intent classifier metadata saved!")

if __name__ == "__main__":
    try:
        download_and_convert_model()
        print("\n🎉 Setup complete! Models ready for mobile deployment.")
    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)

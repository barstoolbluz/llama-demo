#!/usr/bin/env python3
"""
Download LLaMA 2 7B model from HuggingFace Hub
Uses Python API for reliability and progress tracking
"""
import os
import sys
from huggingface_hub import snapshot_download
from pathlib import Path

def download_model(output_dir: str, token: str):
    """Download LLaMA 2 7B model"""

    print("╔════════════════════════════════════════════════════════════╗")
    print("║   Downloading LLaMA 2 7B from HuggingFace                  ║")
    print("║   Size: ~13GB | Time: 10-30 minutes (depends on network)   ║")
    print("╚════════════════════════════════════════════════════════════╝")
    print()

    if not token:
        print("ERROR: HF_TOKEN not set")
        print()
        print("LLaMA 2 requires HuggingFace authentication:")
        print("  1. Get token: https://huggingface.co/settings/tokens")
        print("  2. Accept license: https://huggingface.co/meta-llama/Llama-2-7b-hf")
        print("  3. Set token: export HF_TOKEN=hf_your_token_here")
        sys.exit(1)

    # Create output directory
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    print(f"Output directory: {output_dir}")
    print("Downloading model files...")
    print()

    try:
        # Download model with progress tracking
        snapshot_download(
            repo_id="meta-llama/Llama-2-7b-hf",
            local_dir=output_dir,
            local_dir_use_symlinks=False,
            token=token,
        )

        print()
        print("✓ Model downloaded successfully")

        # Calculate size
        total_size = sum(
            f.stat().st_size for f in output_path.rglob('*') if f.is_file()
        )
        print(f"  Total size: {total_size / (1024**3):.2f} GB")
        print(f"  Location: {output_dir}")
        print()

    except Exception as e:
        print(f"✗ Download failed: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    output_dir = sys.argv[1] if len(sys.argv) > 1 else "./model"
    token = os.environ.get("HF_TOKEN", "")
    download_model(output_dir, token)

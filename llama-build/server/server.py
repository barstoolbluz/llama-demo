from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from transformers import AutoTokenizer, AutoModelForCausalLM
import torch
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="LLaMA 2 7B Inference API")

# Model configuration from environment
MODEL_PATH = os.environ.get("MODEL_PATH", "/nix/store/.../share/models/llama-2-7b-hf")
MAX_LENGTH = int(os.environ.get("MAX_LENGTH", "512"))
TEMPERATURE = float(os.environ.get("TEMPERATURE", "0.7"))

# Global model and tokenizer (loaded on startup)
model = None
tokenizer = None

class GenerateRequest(BaseModel):
    prompt: str
    max_length: int = MAX_LENGTH
    temperature: float = TEMPERATURE

class GenerateResponse(BaseModel):
    generated_text: str
    prompt: str
    model_path: str

@app.on_event("startup")
async def load_model():
    """Load model on server startup"""
    global model, tokenizer
    logger.info(f"Loading model from {MODEL_PATH}...")

    try:
        tokenizer = AutoTokenizer.from_pretrained(MODEL_PATH)
        model = AutoModelForCausalLM.from_pretrained(
            MODEL_PATH,
            torch_dtype=torch.float32,  # CPU-only
            device_map="cpu",
            low_cpu_mem_usage=True
        )
        logger.info("✓ Model loaded successfully!")
    except Exception as e:
        logger.error(f"✗ Failed to load model: {str(e)}")
        raise

@app.get("/health")
async def health():
    """Health check endpoint"""
    return {
        "status": "healthy" if model is not None else "initializing",
        "model_loaded": model is not None,
        "model_path": MODEL_PATH
    }

@app.post("/generate", response_model=GenerateResponse)
async def generate(request: GenerateRequest):
    """Generate text from prompt"""
    if model is None or tokenizer is None:
        raise HTTPException(status_code=503, detail="Model not loaded yet")

    try:
        logger.info(f"Generating from prompt: {request.prompt[:50]}...")

        inputs = tokenizer(request.prompt, return_tensors="pt")

        with torch.no_grad():
            outputs = model.generate(
                inputs.input_ids,
                max_length=request.max_length,
                temperature=request.temperature,
                do_sample=True,
                pad_token_id=tokenizer.eos_token_id
            )

        generated_text = tokenizer.decode(outputs[0], skip_special_tokens=True)

        logger.info("✓ Generation complete")

        return GenerateResponse(
            generated_text=generated_text,
            prompt=request.prompt,
            model_path=MODEL_PATH
        )
    except Exception as e:
        logger.error(f"✗ Generation failed: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/")
async def root():
    """API information"""
    return {
        "service": "LLaMA 2 7B Inference API",
        "version": "1.0.0",
        "model": "meta-llama/Llama-2-7b-hf",
        "endpoints": {
            "health": "GET /health",
            "generate": "POST /generate",
            "docs": "GET /docs"
        }
    }

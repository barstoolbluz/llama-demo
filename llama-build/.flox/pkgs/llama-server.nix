{ stdenv
, lib
, python311
, curl
, cacert
, makeWrapper
, autoPatchelfHook
, zlib
}:

let
  serverVersion = "1.0.0";
  pythonPkg = python311;

  # Fixed-output derivation to download pip packages (allowed network access)
  pipCache = stdenv.mkDerivation {
    name = "llama-server-${serverVersion}-pip-cache";

    nativeBuildInputs = [ pythonPkg curl cacert ];

    # Placeholder source
    src = builtins.toFile "requirements.txt" ''
      fastapi
      uvicorn
      transformers
      torch
      accelerate
    '';

    unpackPhase = ":";

    buildPhase = ''
      mkdir -p $out

      # Create temporary venv for downloading
      ${pythonPkg}/bin/python -m venv venv
      source venv/bin/activate

      pip install --upgrade pip setuptools wheel

      # Download all packages without installing, preferring binary wheels
      # Use PyPI for most packages, PyTorch repo for torch (CPU version)
      pip download fastapi uvicorn transformers accelerate \
        --dest $out

      pip download torch \
        --extra-index-url https://download.pytorch.org/whl/cpu \
        --dest $out
    '';

    installPhase = "true";

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    # Platform-specific hashes (pip downloads different wheels per platform)
    outputHash =
      if stdenv.isDarwin && stdenv.isAarch64
        then "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="  # macOS Apple Silicon - not computed yet
      else if stdenv.isDarwin
        then "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="  # macOS Intel - not computed yet
      else "sha256-SdZCYN134XOeg8Zdx9gfb9oeCg/UPR4sn71T5cMIiIo="; # Linux x86_64
  };

in
stdenv.mkDerivation {
  pname = "llama-server";
  version = serverVersion;

  # Use server script from repo (go up two levels from pkgs/ to reach server/)
  src = ../../server;

  nativeBuildInputs = [ pythonPkg makeWrapper autoPatchelfHook ];

  buildInputs = [ pythonPkg stdenv.cc.cc.lib zlib ];

  unpackPhase = ":";

  buildPhase = ''
    echo "========================================="
    echo "Building LLaMA 2 Inference Server"
    echo "Version: ${serverVersion}"
    echo "========================================="

    # Create virtualenv in $out
    ${pythonPkg}/bin/python -m venv $out
    source $out/bin/activate

    # Install from pre-downloaded packages (no network needed)
    echo ""
    echo "Installing dependencies from cache..."
    pip install --no-index --find-links ${pipCache} \
      fastapi uvicorn transformers torch accelerate

    echo ""
    echo "Installed packages:"
    pip list | grep -E "(fastapi|uvicorn|transformers|torch|accelerate)"
  '';

  installPhase = ''
    echo ""
    echo "Installing server application..."

    # Copy server script
    mkdir -p $out/lib/llama-server
    cp ${../../server/server.py} $out/lib/llama-server/server.py

    # Create launcher script
    cat > $out/bin/llama-server <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Activate virtualenv
SCRIPT_DIR="$(cd "$(dirname "''${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/activate"

# Check MODEL_PATH
if [ -z "''${MODEL_PATH:-}" ]; then
    echo "ERROR: MODEL_PATH environment variable not set"
    echo "Usage: MODEL_PATH=/path/to/model llama-server [OPTIONS]"
    exit 1
fi

# Run server
cd "$(dirname "$SCRIPT_DIR")/lib/llama-server"
exec uvicorn server:app --host 0.0.0.0 --port 8000 "$@"
EOF

    chmod +x $out/bin/llama-server

    echo ""
    echo "✓ LLaMA Server built successfully!"
    echo ""
    echo "Usage:"
    echo "  MODEL_PATH=/path/to/model llama-server"
  '';

  dontStrip = true;
  dontPatchELF = true;
  dontPatchShebangs = false;

  meta = with lib; {
    description = "LLaMA 2 7B Inference Server (FastAPI)";
    longDescription = ''
      FastAPI-based inference server for LLaMA 2 7B model.

      Features:
      - FastAPI web framework
      - Uvicorn ASGI server
      - HuggingFace transformers
      - PyTorch (CPU-only)

      Usage:
        MODEL_PATH=/nix/store/.../share/models/llama-2-7b-hf llama-server

      Endpoints:
        GET  /health   - Health check
        POST /generate - Generate text from prompt
        GET  /         - API information
        GET  /docs     - Interactive API documentation
    '';
    homepage = "https://github.com/barstoolbluz/llama-demo";
    license = licenses.asl20;
    platforms = platforms.unix;
    mainProgram = "llama-server";
  };
}

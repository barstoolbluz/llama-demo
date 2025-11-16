{ stdenv
, python3
, makeWrapper
, lib
}:

let
  # Create Python environment with all dependencies
  pythonEnv = python3.withPackages (ps: with ps; [
    fastapi
    uvicorn
    transformers
    torch
    pydantic
    accelerate
    sentencepiece
  ]);

in stdenv.mkDerivation rec {
  pname = "llama-server";
  version = "1.0.0";

  # Reference our source files
  src = ../..;

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ pythonEnv ];

  # Don't try to unpack
  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    # Create directory structure
    mkdir -p $out/{bin,share/llama-server}

    # Copy server code
    cp -r $src/server/* $out/share/llama-server/

    # Create launcher script
    cat > $out/bin/llama-serve << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Locate package root
APP_ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"
SERVER_DIR="$APP_ROOT/share/llama-server"

# Configuration (overridable via environment)
export HOST="''${HOST:-0.0.0.0}"
export PORT="''${PORT:-8000}"
export WORKERS="''${WORKERS:-1}"
export LOG_LEVEL="''${LOG_LEVEL:-info}"

# MODEL_PATH must be set by runtime environment
if [ -z "''${MODEL_PATH:-}" ]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "ERROR: MODEL_PATH environment variable not set"
  echo ""
  echo "This should be set by the runtime environment manifest."
  echo "Expected: MODEL_PATH=\$FLOX_ENV/share/models/llama-2-7b-hf"
  echo ""
  echo "Make sure you have llama-model package installed:"
  echo "  flox install barstoolbluz/llama-model"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 1
fi

# Check if model exists
if [ ! -d "$MODEL_PATH" ]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "ERROR: Model not found at $MODEL_PATH"
  echo ""
  echo "Make sure the llama-model package is installed."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 1
fi

echo ""
echo "╔════════════════════════════════════════╗"
echo "║   Starting LLaMA Inference Server      ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo "  Host:    $HOST"
echo "  Port:    $PORT"
echo "  Workers: $WORKERS"
echo "  Model:   $MODEL_PATH"
echo ""
echo "Endpoints:"
echo "  http://$HOST:$PORT/           - API info"
echo "  http://$HOST:$PORT/health     - Health check"
echo "  http://$HOST:$PORT/generate   - Generate text (POST)"
echo "  http://$HOST:$PORT/docs       - Interactive docs"
echo ""

cd "$SERVER_DIR"
exec uvicorn server:app \
  --host "$HOST" \
  --port "$PORT" \
  --workers "$WORKERS" \
  --log-level "$LOG_LEVEL"
EOF

    chmod +x $out/bin/llama-serve

    # Wrap the launcher to ensure Python environment is available
    wrapProgram $out/bin/llama-serve \
      --prefix PATH : ${pythonEnv}/bin

    runHook postInstall
  '';

  meta = with lib; {
    description = "FastAPI inference server for LLaMA models";
    homepage = "https://github.com/barstoolbluz/llama-demo";
    license = licenses.mit;
    platforms = platforms.linux;
    maintainers = [];
  };
}

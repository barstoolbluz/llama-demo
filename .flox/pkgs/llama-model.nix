{ stdenv
, python3
, python3Packages
, lib
}:

stdenv.mkDerivation rec {
  pname = "llama-model";
  version = "2.0.0";

  # Use our download script as source
  src = ../..;

  nativeBuildInputs = [
    python3
    python3Packages.huggingface-hub
  ];

  # Don't unpack anything - we're downloading during build
  dontUnpack = true;

  buildPhase = ''
    runHook preBuild

    # Check for HF_TOKEN
    if [ -z "''${HF_TOKEN:-}" ]; then
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "ERROR: HF_TOKEN environment variable not set"
      echo ""
      echo "LLaMA 2 requires HuggingFace authentication."
      echo ""
      echo "To build this package:"
      echo "  1. Get token: https://huggingface.co/settings/tokens"
      echo "  2. Accept license: https://huggingface.co/meta-llama/Llama-2-7b-hf"
      echo "  3. Export token: export HF_TOKEN=hf_your_token_here"
      echo "  4. Build: flox build llama-model"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      exit 1
    fi

    echo "Building llama-model package..."
    echo "Downloading LLaMA 2 7B from HuggingFace..."
    echo "This will take 10-30 minutes (~13GB download)"
    echo ""

    # Run download script
    python3 $src/download_model.py "$out/share/models/llama-2-7b-hf"

    runHook postBuild
  '';

  # No install phase needed - download script puts files in $out
  dontInstall = true;

  meta = with lib; {
    description = "LLaMA 2 7B HuggingFace model (CPU-optimized)";
    homepage = "https://huggingface.co/meta-llama/Llama-2-7b-hf";
    license = licenses.unfree;  # LLaMA 2 Community License
    platforms = platforms.linux;
    maintainers = [];
  };
}

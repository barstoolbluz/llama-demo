{ stdenv
, lib
, python311
, curl
, cacert
}:

let
  # Model configuration
  modelRepo = "meta-llama/Llama-2-7b-hf";
  modelVersion = "2.0.0";

  # Python package for downloading
  pythonPkg = python311.withPackages (ps: [ ps.huggingface-hub ]);

  # HF_TOKEN from environment (must be set when building)
  hfToken = builtins.getEnv "HF_TOKEN";

  # Fixed-output derivation to download model files (allowed network access)
  modelCache = stdenv.mkDerivation {
    name = "llama-2-7b-hf-model-cache";

    nativeBuildInputs = [ pythonPkg cacert ];

    # Placeholder source
    src = builtins.toFile "download.py" ''
      from huggingface_hub import snapshot_download
      import os

      token = os.environ.get("HF_TOKEN")
      if not token:
          raise ValueError("HF_TOKEN environment variable not set")

      print(f"Downloading model from ${modelRepo}...")
      snapshot_download(
          repo_id="${modelRepo}",
          local_dir=os.environ["out"],
          local_dir_use_symlinks=False,
          token=token,
      )
      print("Download complete!")
    '';

    unpackPhase = ":";

    buildPhase = ''
      export HF_TOKEN="${hfToken}"
      export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt

      echo "========================================="
      echo "Downloading LLaMA 2 7B Model"
      echo "Repository: ${modelRepo}"
      echo "========================================="

      mkdir -p $out
      python $src
    '';

    installPhase = "true";

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    # Platform-specific hashes (model files are the same across platforms)
    outputHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # Placeholder - will be updated after first build
  };

in
stdenv.mkDerivation {
  pname = "llama-2-7b-hf-model";
  version = modelVersion;

  # Use the cached model files
  src = modelCache;

  unpackPhase = ":";

  installPhase = ''
    echo "========================================="
    echo "Packaging LLaMA 2 7B Model"
    echo "Version: ${modelVersion}"
    echo "========================================="

    # Create output directory structure
    mkdir -p $out/share/models/llama-2-7b-hf

    # Copy model files from cache
    cp -r $src/* $out/share/models/llama-2-7b-hf/

    # Verify critical files exist
    if [ -f "$out/share/models/llama-2-7b-hf/config.json" ]; then
      echo "✓ Model packaged successfully"
      echo "  Location: $out/share/models/llama-2-7b-hf"
    else
      echo "✗ Model packaging failed - config.json not found"
      exit 1
    fi
  '';

  dontStrip = true;
  dontPatchELF = true;
  dontPatchShebangs = false;

  meta = with lib; {
    description = "LLaMA 2 7B HuggingFace model";
    longDescription = ''
      Meta's LLaMA 2 7B model from HuggingFace.
      Repository: ${modelRepo}
      Version: ${modelVersion}

      This package downloads the model files once during build
      and packages them for reuse.

      To build, set HF_TOKEN environment variable:
        HF_TOKEN=your_token flox build llama-model

      License: LLaMA 2 Community License Agreement
      https://ai.meta.com/llama/license/
    '';
    homepage = "https://huggingface.co/${modelRepo}";
    license = licenses.unfree;
    platforms = platforms.unix;
  };
}

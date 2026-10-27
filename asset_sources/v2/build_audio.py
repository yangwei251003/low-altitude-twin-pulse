"""Compatibility entry point for the V2 CC0 audio pipeline."""
from pathlib import Path
import runpy

if __name__ == "__main__":
    runpy.run_path(str(Path(__file__).parent / "audio/build_audio_upgrade.py"), run_name="__main__")

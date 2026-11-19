"""Local release helper: operator publishes reviewed documents from repository root."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "server"))
from backend.publish_legal import *  # noqa: F401,F403

if __name__ == "__main__":
    from backend.publish_legal import main
    main()

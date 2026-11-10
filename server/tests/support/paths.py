"""Paths independent of the working directory and test package depth."""
from pathlib import Path

SERVER_ROOT = Path(__file__).resolve().parents[2]
PROJECT_ROOT = SERVER_ROOT.parent

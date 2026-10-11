"""No-network, no-credential extraction process. Input is one clean local file."""
import json
from pathlib import Path
import sys
from processor import extract_clean_file, Rejected, TemporaryFailure

try:
    result = extract_clean_file(Path(sys.argv[1]), sys.argv[2], sys.argv[3])
except Rejected:
    result = {"kind": "failed", "retryable": False}
except TemporaryFailure:
    result = {"kind": "failed", "retryable": True}
sys.stdout.write(json.dumps(result, separators=(",", ":")))

"""Fetch historical screenshots for comparison only, never theme artwork."""
from pathlib import Path
from urllib.request import urlopen
import hashlib
import json

root = Path(__file__).resolve().parents[1] / 'evidence/reference'
references = {
    'apple-1997-appearance.gif': 'https://dev.os9.ca/techpubs/mac/HIGOS8Guide/graphics/HIG_Intro-002.gif',
}
results = []
for filename, url in references.items():
    with urlopen(url, timeout=30) as response:
        data = response.read()
    (root / filename).write_bytes(data)
    results.append({'file': filename, 'url': url, 'sha256': hashlib.sha256(data).hexdigest()})
(root / 'sources.json').write_text(json.dumps(results, indent=2) + '\n')

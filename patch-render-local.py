from pathlib import Path

p = Path('/app/backend.php')
text = p.read_text()
anchor = 'function fd_is_local_request(): bool\n{'
if anchor not in text:
    raise SystemExit('fd_is_local_request() anchor not found')
needle = anchor + "\n    if (getenv('PENCARIMOVIE_RENDER_MODE') === '1') {\n        return true;\n    }"
if needle not in text:
    text = text.replace(anchor, needle, 1)
p.write_text(text)

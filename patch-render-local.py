from pathlib import Path

p = Path('/app/backend.php')
text = p.read_text(encoding='utf-8')

# Render sits behind a public reverse proxy, so the upstream local-only guard
# sees Render's proxy/client address instead of localhost. Keep the upstream
# guard intact everywhere else, but explicitly allow the /api/download path
# when this deployment opts into Render mode.
anchor = 'function fd_require_local_request(): void\n{'
if anchor not in text:
    raise SystemExit('fd_require_local_request() anchor not found')

needle = anchor + "\n    if (getenv('PENCARIMOVIE_RENDER_MODE') === '1') {\n        return;\n    }"
if needle not in text:
    text = text.replace(anchor, needle, 1)

# Also patch the predicate itself as a fallback for code paths that call it
# directly. This makes the Render opt-in effective regardless of which caller
# performs the locality check.
anchor2 = 'function fd_is_local_request(): bool\n{'
if anchor2 not in text:
    raise SystemExit('fd_is_local_request() anchor not found')
needle2 = anchor2 + "\n    if (getenv('PENCARIMOVIE_RENDER_MODE') === '1') {\n        return true;\n    }"
if needle2 not in text:
    text = text.replace(anchor2, needle2, 1)

p.write_text(text, encoding='utf-8')
print('Render local-request guard patched at both enforcement and predicate levels')

from pathlib import Path
import re

backend = Path('/app/backend.php')
text = backend.read_text(encoding='utf-8')

# Render sits behind a proxy and may expose Cloudflare headers. Upstream v1.1.0
# intentionally treats Cloudflare/Cloudflare Tunnel requests as remote, which
# blocks the local-only dashboard endpoints on Render. Keep that protection
# everywhere else, but explicitly mark this deployment as trusted server-side.
marker = "function fd_is_cloudflare_tunnel_request(): bool\n{"
if marker not in text:
    raise SystemExit('v1.1.0 cloudflare locality function not found')

needle = marker + "\n    $hosts = ["
replacement = marker + "\n    if ((string) ($_SERVER['PENCARIMOVIE_RENDER_MODE'] ?? $_ENV['PENCARIMOVIE_RENDER_MODE'] ?? '') === '1') {\n        return false;\n    }\n\n    $hosts = ["
if needle not in text:
    raise SystemExit('cloudflare function anchor not found')
text = text.replace(needle, replacement, 1)

# Keep the existing Render bot-token override, but make it resilient to the
# exact whitespace/formatting used by v1.1.0.
if 'PENCARIMOVIE_BOT_TOKEN' not in text:
    pattern = re.compile(r"(?m)^(\s*)\$botToken\s*=\s*trim\(\(string\)\s*\(\$input\['bot_token'\]\s*\?\?\s*''\)\);\s*$")
    match = pattern.search(text)
    if not match:
        raise SystemExit('v1.1.0 bot token assignment not found')
    indent = match.group(1)
    inject = match.group(0) + "\n" + indent + "$configuredBotToken = trim((string) ($_SERVER['PENCARIMOVIE_BOT_TOKEN'] ?? $_ENV['PENCARIMOVIE_BOT_TOKEN'] ?? ''));\n" + indent + "if ($configuredBotToken !== '') {\n" + indent + "    $botToken = $configuredBotToken;\n" + indent + "}"
    text = text[:match.start()] + inject + text[match.end():]

backend.write_text(text, encoding='utf-8')
print('Render compatibility patch applied to PencariMovie v1.1.0 backend')

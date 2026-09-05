from pathlib import Path
import re

path = Path('/app/backend.php')
text = path.read_text(encoding='utf-8')

# Replace the earlier minimal diagnostics with precise stage markers. These logs
# are intentionally limited to fd_boot_madeline and never include bot tokens,
# API secrets, or session contents.
if '[STREAM DEBUG V2]' not in text:
    marker = 'function fd_boot_madeline(?string $botToken = null, array $overrides = [], ?string $sessionPathOverride = null): array'
    if marker not in text:
        # Fall back to a looser signature match in case upstream formatting differs.
        marker_match = re.search(r'function\s+fd_boot_madeline\s*\([^)]*\):\s*array', text)
        marker = marker_match.group(0) if marker_match else None

    if marker:
        brace = text.find('{', text.find(marker))
        if brace != -1:
            diagnostic = r'''\n    $fdDebugStart = microtime(true);\n    error_log('[STREAM DEBUG V2] boot A: entered ' . json_encode([\n        'request' => (string) ($_SERVER['REQUEST_URI'] ?? ''),\n        'session_override' => $sessionPathOverride !== null,\n        'token_provided' => $botToken !== null && trim((string) $botToken) !== '',\n    ]));\n'''
            text = text[:brace + 1] + diagnostic + text[brace + 1:]

            # Add a marker immediately before the first vendor/autoload require.
            text = re.sub(
                r'(require(?:_once)?\s*[^;]*vendor/autoload\.php[^;]*;)',
                "error_log('[STREAM DEBUG V2] boot B: before vendor autoload');\\n    \\1\\n    error_log('[STREAM DEBUG V2] boot C: after vendor autoload');",
                text,
                count=1,
            )

            # Mark construction of MadelineProto API objects. Handle both `new API`
            # and fully-qualified `new \MadelineProto\API` forms.
            text = re.sub(
                r'(?m)^([ \t]*)(\$[A-Za-z_][A-Za-z0-9_]*\s*=\s*new\s+(?:\\?MadelineProto\\)?API\s*\([^;]*\);)',
                r"\1error_log('[STREAM DEBUG V2] boot D: before Madeline API constructor');\n\1\2\n\1error_log('[STREAM DEBUG V2] boot E: after Madeline API constructor');",
                text,
                count=1,
            )

            # Mark common bot-login operations if present.
            text = re.sub(
                r'(?m)^([ \t]*)(\$[A-Za-z_][A-Za-z0-9_]*->botLogin\s*\([^;]*\);)',
                r"\1error_log('[STREAM DEBUG V2] boot F: before botLogin');\n\1\2\n\1error_log('[STREAM DEBUG V2] boot G: after botLogin');",
                text,
                count=1,
            )

            # Mark getSelf(), which is commonly used immediately after login.
            text = re.sub(
                r'(?m)^([ \t]*)(\$[A-Za-z_][A-Za-z0-9_]*->getSelf\s*\([^;]*\);)',
                r"\1error_log('[STREAM DEBUG V2] boot H: before getSelf');\n\1\2\n\1error_log('[STREAM DEBUG V2] boot I: after getSelf');",
                text,
                count=1,
            )

            # Final marker on every successful return from this function.
            text = re.sub(
                r'(?m)^([ \t]*)return\s*\[\s*\$([A-Za-z_][A-Za-z0-9_]*),\s*null\s*\];',
                r"\1error_log('[STREAM DEBUG V2] boot J: success');\n\1return [$\2, null];",
                text,
                count=1,
            )

            # Catch/log the exact Throwable around the function body if the
            # upstream function does not already have an equivalent catch. Rather
            # than restructuring the whole function, the stage markers above are
            # sufficient to identify the blocking operation without changing flow.

            error_log = "\n    error_log('[STREAM DEBUG V2] boot marker patch installed');\n"
            # Only add this inside the function if it was not already present.
            if "boot marker patch installed" not in text:
                brace = text.find('{', text.find(marker))
                text = text[:brace + 1] + error_log + text[brace + 1:]

# Preserve the existing download marker.
needle = "$madeline->downloadToBrowser("
if needle in text and "[STREAM DEBUG] downloadToBrowser about to start" not in text:
    text = text.replace(
        needle,
        "error_log('[STREAM DEBUG] downloadToBrowser about to start');\n        " + needle,
        1,
    )

path.write_text(text, encoding='utf-8')
print('Precise MadelineProto boot diagnostics V2 applied')

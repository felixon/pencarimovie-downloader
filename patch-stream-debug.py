from pathlib import Path
import re

path = Path('/app/backend.php')
text = path.read_text(encoding='utf-8')

# Precise MadelineProto boot diagnostics. No secrets or session contents are logged.
m = re.search(r'function\s+fd_boot_madeline\s*\([^)]*\):\s*array\s*\{', text)
if m and '[STREAM DEBUG V3]' not in text:
    insert_at = m.end()
    diagnostic = """
    error_log('[STREAM DEBUG V3] A entered fd_boot_madeline');
    error_log('[STREAM DEBUG V3] B session=' . (defined('FD_SESSION_PATH') ? FD_SESSION_PATH : 'undefined'));
    register_shutdown_function(function (): void {
        $e = error_get_last();
        if ($e !== null) {
            error_log('[STREAM DEBUG V3] SHUTDOWN ' . json_encode([
                'type' => $e['type'] ?? null,
                'message' => $e['message'] ?? null,
                'file' => $e['file'] ?? null,
                'line' => $e['line'] ?? null,
            ], JSON_UNESCAPED_SLASHES));
        } else {
            error_log('[STREAM DEBUG V3] SHUTDOWN no-last-error');
        }
    });
"""
    text = text[:insert_at] + diagnostic + text[insert_at:]

# The previous V2 patch did not add markers after the WordPress credential cache.
needle = "fd_log('api credentials cached from wordpress', ['api_id' => $apiId]);"
if needle in text and '[STREAM DEBUG V3] C credentials ready' not in text:
    text = text.replace(
        needle,
        needle + "\n        error_log('[STREAM DEBUG V3] C credentials ready; entering MadelineProto setup');",
        1,
    )

# Instrument the API constructor if the backend constructs it directly.
if '[STREAM DEBUG V3] D before API constructor' not in text:
    text = re.sub(
        r'(?m)^(\s*)(\$[A-Za-z_][A-Za-z0-9_]*\s*=\s*new\s+(?:\\?[A-Za-z_][A-Za-z0-9_]*\\)?API\s*\([^;]*\);)',
        r"\1error_log('[STREAM DEBUG V3] D before API constructor');\n\1\2\n\1error_log('[STREAM DEBUG V3] E after API constructor');",
        text,
        count=1,
    )

# Preserve the existing download marker.
needle = '$madeline->downloadToBrowser('
if needle in text and '[STREAM DEBUG] downloadToBrowser about to start' not in text:
    text = text.replace(
        needle,
        "error_log('[STREAM DEBUG] downloadToBrowser about to start');\n        " + needle,
        1,
    )

path.write_text(text, encoding='utf-8')
print('Precise MadelineProto boot diagnostics V3 applied')

from pathlib import Path
import re

path = Path('/app/backend.php')
text = path.read_text(encoding='utf-8')

# Boot diagnostics.
m = re.search(r'function\s+fd_boot_madeline\s*\([^)]*\):\s*array\s*\{', text)
if m and '[STREAM DEBUG V4]' not in text:
    insert_at = m.end()
    diagnostic = """
    error_log('[STREAM DEBUG V4] A entered fd_boot_madeline');
    error_log('[STREAM DEBUG V4] B session=' . (defined('FD_SESSION_PATH') ? FD_SESSION_PATH : 'undefined'));
    register_shutdown_function(function (): void {
        $e = error_get_last();
        error_log('[STREAM DEBUG V4] SHUTDOWN ' . ($e === null ? 'no-last-error' : json_encode([
            'type' => $e['type'] ?? null,
            'message' => $e['message'] ?? null,
            'file' => $e['file'] ?? null,
            'line' => $e['line'] ?? null,
        ], JSON_UNESCAPED_SLASHES)));
    });
"""
    text = text[:insert_at] + diagnostic + text[insert_at:]

# Mark the exact transition out of WordPress credential handling.
needle = "fd_log('api credentials cached from wordpress', ['api_id' => $apiId]);"
if needle in text and '[STREAM DEBUG V4] C credentials ready' not in text:
    text = text.replace(needle, needle + "\n        error_log('[STREAM DEBUG V4] C credentials ready; entering MadelineProto setup');", 1)

# Trace vendor loading if it is performed after the credential stage.
if '[STREAM DEBUG V4] V before vendor autoload' not in text:
    text = re.sub(
        r'(?m)^(\s*)(require(?:_once)?\s*[^;\n]*vendor/autoload\.php[^;\n]*;)',
        r"\1error_log('[STREAM DEBUG V4] V before vendor autoload');\n\1\2\n\1error_log('[STREAM DEBUG V4] W after vendor autoload');",
        text,
        count=1,
    )

# Trace API construction even when the constructor spans multiple lines.
if '[STREAM DEBUG V4] D before API constructor' not in text:
    text = re.sub(
        r'(\$[A-Za-z_][A-Za-z0-9_]*\s*=\s*)new\s+(?:\\?[A-Za-z_][A-Za-z0-9_]*\\)?API\s*\(',
        r"error_log('[STREAM DEBUG V4] D before API constructor');\n\1new API(",
        text,
        count=1,
    )

# Trace common Settings construction if API construction is not reached.
if '[STREAM DEBUG V4] S before Settings' not in text:
    text = re.sub(
        r'(\$settings\s*=\s*)new\s+([A-Za-z_\\]+Settings)\s*\(',
        r"error_log('[STREAM DEBUG V4] S before Settings');\n\1new \2(",
        text,
        count=1,
    )

# Preserve the stream-start marker.
needle = '$madeline->downloadToBrowser('
if needle in text and '[STREAM DEBUG] downloadToBrowser about to start' not in text:
    text = text.replace(needle, "error_log('[STREAM DEBUG] downloadToBrowser about to start');\n        " + needle, 1)

path.write_text(text, encoding='utf-8')
print('MadelineProto setup boundary diagnostics V4 applied')

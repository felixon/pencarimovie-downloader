from pathlib import Path
import re

path = Path('/app/backend.php')
text = path.read_text(encoding='utf-8')

# Boot diagnostics.
m = re.search(r'function\s+fd_boot_madeline\s*\([^)]*\):\s*array\s*\{', text)
if m and '[STREAM DEBUG V6]' not in text:
    insert_at = m.end()
    diagnostic = """
    error_log('[STREAM DEBUG V6] A entered fd_boot_madeline');
    error_log('[STREAM DEBUG V6] B session=' . (defined('FD_SESSION_PATH') ? FD_SESSION_PATH : 'undefined'));
    register_shutdown_function(function (): void {
        $e = error_get_last();
        error_log('[STREAM DEBUG V6] SHUTDOWN ' . ($e === null ? 'no-last-error' : json_encode([
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
if needle in text and '[STREAM DEBUG V6] C credentials ready' not in text:
    text = text.replace(needle, needle + "\n        error_log('[STREAM DEBUG V6] C credentials ready; entering MadelineProto setup');", 1)

# Trace filesystem immediately before Settings construction.
needle = "    $settings = new \\danog\\MadelineProto\\Settings();"
if needle in text and '[STREAM DEBUG V6] P pre-settings filesystem' not in text:
    replacement = """    error_log('[STREAM DEBUG V6] P pre-settings filesystem ' . json_encode([
        'session_dir' => $sessionDir,
        'dir_exists' => is_dir($sessionDir),
        'dir_writable' => is_writable($sessionDir),
        'session_exists' => is_dir($sessionPath) || is_file($sessionPath),
        'php_version' => PHP_VERSION,
        'sapi' => PHP_SAPI,
    ], JSON_UNESCAPED_SLASHES));
    error_log('[STREAM DEBUG V6] R before Settings class_exists');
    $settingsClassLoaded = class_exists('\\danog\\MadelineProto\\Settings');
    error_log('[STREAM DEBUG V6] U after Settings class_exists ' . ($settingsClassLoaded ? 'true' : 'false'));
    error_log('[STREAM DEBUG V6] S before Settings constructor');
    $settings = new \\danog\\MadelineProto\\Settings();
    error_log('[STREAM DEBUG V6] T after Settings constructor');"""
    text = text.replace(needle, replacement, 1)

# Trace API construction without changing the constructor's class name.
pattern = r'(?m)^(\s*)(\$madeline\s*=\s*new\s+\\danog\\MadelineProto\\API\s*\()'
if '[STREAM DEBUG V6] D before API constructor' not in text:
    text = re.sub(
        pattern,
        r"\1error_log('[STREAM DEBUG V6] D before API constructor');\n\1\2",
        text,
        count=1,
    )

# Trace stream start.
needle = '$madeline->downloadToBrowser('
if needle in text and '[STREAM DEBUG V6] before downloadToBrowser' not in text:
    text = text.replace(
        needle,
        "error_log('[STREAM DEBUG V6] before downloadToBrowser');\n        " + needle,
        1,
    )

path.write_text(text, encoding='utf-8')
print('MadelineProto Settings class-loading diagnostics V6 applied')

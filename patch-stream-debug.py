from pathlib import Path
import re

path = Path('/app/backend.php')
text = path.read_text(encoding='utf-8')

# Precise MadelineProto boot diagnostics. No secrets or session contents are logged.
if '[STREAM DEBUG V2]' not in text:
    m = re.search(r'function\s+fd_boot_madeline\s*\([^)]*\):\s*array\s*\{', text)
    if m:
        insert_at = m.end()
        diagnostic = """
    error_log('[STREAM DEBUG V2] A entered fd_boot_madeline');
    error_log('[STREAM DEBUG V2] B session=' . (defined('FD_SESSION_PATH') ? FD_SESSION_PATH : 'undefined'));
"""
        text = text[:insert_at] + diagnostic + text[insert_at:]

        # Instrument the vendor autoloader if it occurs inside this function.
        text = re.sub(
            r'(?m)^(\s*)(require(?:_once)?\s*[^;]*vendor/autoload\.php[^;]*;)',
            r"\1error_log('[STREAM DEBUG V2] C before vendor autoload');\n\1\2\n\1error_log('[STREAM DEBUG V2] D after vendor autoload');",
            text,
            count=1,
        )

        # Instrument API constructor, accepting both API and MadelineProto\\API.
        text = re.sub(
            r'(?m)^(\s*)(\$[A-Za-z_][A-Za-z0-9_]*\s*=\s*new\s+(?:\\?MadelineProto\\\\)?API\s*\([^;]*\);)',
            r"\1error_log('[STREAM DEBUG V2] E before API constructor');\n\1\2\n\1error_log('[STREAM DEBUG V2] F after API constructor');",
            text,
            count=1,
        )

        # Instrument botLogin/getSelf when these calls are present as standalone statements.
        text = re.sub(
            r'(?m)^(\s*)(\$[A-Za-z_][A-Za-z0-9_]*->botLogin\s*\([^;]*\);)',
            r"\1error_log('[STREAM DEBUG V2] G before botLogin');\n\1\2\n\1error_log('[STREAM DEBUG V2] H after botLogin');",
            text,
            count=1,
        )
        text = re.sub(
            r'(?m)^(\s*)(\$[A-Za-z_][A-Za-z0-9_]*->getSelf\s*\([^;]*\);)',
            r"\1error_log('[STREAM DEBUG V2] I before getSelf');\n\1\2\n\1error_log('[STREAM DEBUG V2] J after getSelf');",
            text,
            count=1,
        )

        # Add a final diagnostic before the first successful [API, null] return.
        text = re.sub(
            r'(?m)^(\s*)return\s*\[\s*\$([A-Za-z_][A-Za-z0-9_]*),\s*null\s*\];',
            r"\1error_log('[STREAM DEBUG V2] K fd_boot_madeline success');\n\1return [$\2, null];",
            text,
            count=1,
        )

# Preserve the existing stream-start marker.
needle = '$madeline->downloadToBrowser('
if needle in text and '[STREAM DEBUG] downloadToBrowser about to start' not in text:
    text = text.replace(
        needle,
        "error_log('[STREAM DEBUG] downloadToBrowser about to start');\n        " + needle,
        1,
    )

path.write_text(text, encoding='utf-8')
print('Precise MadelineProto boot diagnostics V2 applied')

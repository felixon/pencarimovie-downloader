from pathlib import Path

path = Path('/app/backend.php')
text = path.read_text(encoding='utf-8')

# Log the beginning of the MadelineProto boot without changing its behavior.
needle = "function fd_boot_madeline("
if needle in text and "[STREAM DEBUG] fd_boot_madeline" not in text:
    text = text.replace(
        needle,
        "function fd_boot_madeline(\n",
        1,
    )
    # Restore the original signature by removing the accidental newline only;
    # the actual diagnostic is inserted after the opening brace below.
    text = text.replace("function fd_boot_madeline(\n", "function fd_boot_madeline(", 1)

# Insert diagnostics after the function's opening brace using the known
# function signature from the packaged backend. This is deliberately tolerant
# so a minor upstream signature change does not break the build.
marker = "function fd_boot_madeline(string $botToken"
if marker in text and "[STREAM DEBUG] fd_boot_madeline" not in text:
    start = text.index(marker)
    brace = text.find('{', start)
    if brace != -1:
        text = text[:brace+1] + "\n    if (str_starts_with((string) ($_SERVER['REQUEST_URI'] ?? ''), '/api/download')) { error_log('[STREAM DEBUG] fd_boot_madeline entered'); }" + text[brace+1:]

# Log immediately before the actual Telegram-backed browser download call.
needle = "$madeline->downloadToBrowser("
if needle in text and "[STREAM DEBUG] downloadToBrowser" not in text:
    text = text.replace(
        needle,
        "error_log('[STREAM DEBUG] downloadToBrowser about to start');\n        " + needle,
        1,
    )

path.write_text(text, encoding='utf-8')
print('Targeted stream diagnostics patch applied')

<?php
// Render/FrankenPHP stream bootstrap.
// Must run before backend.php so MadelineProto can be forced into
// in-process mode before the application's entrypoint initializes it.
if (!isset($_GET['MadelineSelfRestart'])) {
    $_GET['MadelineSelfRestart'] = '1';
}

@ini_set('max_execution_time', '0');
@ini_set('default_socket_timeout', '0');
@set_time_limit(0);

// Prevent the client disconnect from terminating a long Telegram-backed stream.
@ignore_user_abort(true);

// Narrow diagnostics for stream startup. This runs before backend.php, so if
// this message appears we know the browser request reached the Render/PHP app.
if (str_starts_with((string) ($_SERVER['REQUEST_URI'] ?? ''), '/api/download')) {
    error_log('[STREAM DEBUG] /api/download request received');
}

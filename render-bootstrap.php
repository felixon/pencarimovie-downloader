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

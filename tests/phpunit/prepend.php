<?php
/**
 * Loaded with `php -d auto_prepend_file=tests/phpunit/prepend.php`, before Composer's autoloader.
 *
 * Package autoload `files` define EE_ROOT_DIR as /opt/easyengine and mkdir under it when it isn't set yet,
 * and vendor/bin/phpunit loads the autoloader before any bootstrap file, so these constants must exist first.
 */

define( 'EE_PHPUNIT', true );

// PHP 8.x deprecations in product and vendor code (monolog 1.x, ${var}, dynamic properties) would print into every test.
// EE_PHPUNIT_DEPRECATIONS=1 shows them.
if ( ! getenv( 'EE_PHPUNIT_DEPRECATIONS' ) ) {
	error_reporting( E_ALL & ~E_DEPRECATED & ~E_USER_DEPRECATED );
}

$ee_phpunit_tmp = sys_get_temp_dir() . '/ee-phpunit-' . getmypid();
foreach ( [ 'sites', 'services', 'config', 'db', 'logs', '.backup' ] as $ee_phpunit_dir ) {
	@mkdir( $ee_phpunit_tmp . '/' . $ee_phpunit_dir, 0700, true );
}
unset( $ee_phpunit_dir );

// Same names and derivations as php/init-ee.php and Runner::init_ee(), rooted in a per-process temp dir.
define( 'EE_ROOT', dirname( __DIR__, 2 ) );
define( 'EE', true );
define( 'EE_VERSION', trim( file_get_contents( EE_ROOT . '/VERSION' ) ) );
define( 'EE_START_MICROTIME', microtime( true ) );
define( 'IS_DARWIN', 'Darwin' === php_uname( 's' ) );
define( 'EE_ROOT_DIR', $ee_phpunit_tmp );
define( 'EE_BACKUP_DIR', EE_ROOT_DIR . '/.backup' );
define( 'EE_SERVICE_DIR', EE_ROOT_DIR . '/services' );
define( 'EE_VENDOR_DIR', EE_ROOT . '/vendor' );
define( 'DB', EE_ROOT_DIR . '/db/ee.sqlite' );
define( 'LOCALHOST_IP', '127.0.0.1' );
define( 'SITE_CUSTOM_DOCKER_COMPOSE', 'docker-compose-custom.yml' );
define( 'SITE_CUSTOM_DOCKER_COMPOSE_DIR', 'user-docker-compose' );
define( 'EE_PROXY_TYPE', 'services_global-nginx-proxy_1' );

// Never read or write the host's /opt/easyengine/config/config.yml.
putenv( 'EE_CONFIG_PATH=' . EE_ROOT_DIR . '/config/config.yml' );

register_shutdown_function(
	function () use ( $ee_phpunit_tmp ) {
		if ( is_dir( $ee_phpunit_tmp ) ) {
			exec( 'rm -rf ' . escapeshellarg( $ee_phpunit_tmp ) );
		}
	}
);

<?php
/**
 * PHPUnit bootstrap for core and package unit tests: loads EE without the Runner, Docker or /opt/easyengine.
 *
 * Core:     php -d auto_prepend_file=tests/phpunit/prepend.php vendor/bin/phpunit
 * Packages: php -d auto_prepend_file=tests/phpunit/prepend.php vendor/bin/phpunit --bootstrap tests/phpunit/bootstrap.php -c <pkg>/phpunit.xml.dist
 */

if ( ! defined( 'EE_PHPUNIT' ) ) {
	fwrite( STDERR, "Run PHPUnit with: php -d auto_prepend_file=tests/phpunit/prepend.php vendor/bin/phpunit ...\n" );
	exit( 1 );
}

require_once EE_ROOT . '/vendor/autoload.php';
require_once EE_ROOT . '/php/utils.php';
require_once EE_ROOT . '/php/dispatcher.php';

foreach ( glob( __DIR__ . '/includes/*.php' ) as $ee_phpunit_include ) {
	require_once $ee_phpunit_include;
}
unset( $ee_phpunit_include );

// Every EE::log/debug/error call needs both loggers.
EE::set_logger( new EE\Loggers\Execution() );
EE::set_file_logger( new Monolog\Logger( 'phpunit', [ new Monolog\Handler\NullHandler() ] ) );

// The loggers read the runner config; hide PHPUnit's own argv from the config parser.
$ee_phpunit_argv = $GLOBALS['argv'];
$GLOBALS['argv'] = [ 'ee' ];
EE::get_runner()->init_config();
$GLOBALS['argv'] = $ee_phpunit_argv;
unset( $ee_phpunit_argv );

EE\Tests\TestCase::capture_exit( true );
// Tests that don't install a fake runner must not reach the real shell.
EE::set_process_runner( [ EE\Tests\FakeProcessRunner::class, 'deny' ] );

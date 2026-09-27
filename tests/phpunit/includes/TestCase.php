<?php

namespace EE\Tests;

use EE;
use EE\ExitException;

/**
 * Base class for EE unit tests (core and packages).
 *
 * Per test: a FakeProcessRunner behind EE::launch()/EE::exec() ($this->runner), a fresh SQLite DB with the full schema,
 * EE::error() throwing ExitException instead of exiting, captured log output, restored runner config and cwd,
 * and throwaway directories from sandbox().
 */
abstract class TestCase extends \PHPUnit\Framework\TestCase {

	/** @var FakeProcessRunner */
	protected $runner;

	/** Whether setUp() recreates the DB; set to false in suites that never touch it. */
	protected $reset_db = true;

	private $sandboxes = [];
	private $config_backup;
	private $cwd_backup;

	protected function setUp(): void {
		parent::setUp();
		$this->runner = new FakeProcessRunner();
		EE::set_process_runner( $this->runner );
		self::capture_exit( true );
		self::logger()->stdout = '';
		self::logger()->stderr = '';
		$this->config_backup = EE::get_runner()->config;
		$this->cwd_backup    = getcwd();
		if ( $this->reset_db ) {
			TestDB::reset();
		}
	}

	protected function tearDown(): void {
		EE::set_process_runner( [ FakeProcessRunner::class, 'deny' ] );
		self::set_property( EE::get_runner(), 'config', $this->config_backup );
		if ( $this->cwd_backup ) {
			chdir( $this->cwd_backup );
		}
		foreach ( $this->sandboxes as $dir ) {
			if ( is_dir( $dir ) ) {
				exec( 'rm -rf ' . escapeshellarg( $dir ) );
			}
		}
		$this->sandboxes = [];
		parent::tearDown();
	}

	/** @return \EE\Loggers\Execution The logger capturing EE::log/success/warning/error output. */
	protected static function logger() {
		return self::get_static( 'EE', 'logger' );
	}

	/** @return string What EE::log()/EE::success()/EE::line() printed during this test. */
	protected function stdout() {
		return self::logger()->stdout;
	}

	/** @return string What EE::warning()/EE::error()/EE::debug() printed during this test. */
	protected function stderr() {
		return self::logger()->stderr;
	}

	/** Make EE::error()/EE::halt() throw EE\ExitException instead of exiting the PHPUnit process. */
	public static function capture_exit( $capture ) {
		self::set_static( 'EE', 'capture_exit', (bool) $capture );
	}

	/**
	 * Run $fn and assert it ends in EE::error() (or EE::halt()) with a message containing $contains.
	 *
	 * @return string The captured STDERR.
	 */
	protected function assert_ee_error( callable $fn, $contains = null, $code = 1 ) {
		try {
			$fn();
		} catch ( ExitException $e ) {
			$this->assertSame( $code, $e->getCode(), 'EE exit code' );
			if ( null !== $contains ) {
				$this->assertStringContainsString( $contains, $this->stderr() );
			}

			return $this->stderr();
		}
		$this->fail( 'Expected EE::error(); nothing exited. STDERR: ' . $this->stderr() );
	}

	/** Merge $values into the runner config (e.g. [ 'skip-tty' => true ]); restored after the test. */
	protected function set_config( array $values ) {
		$runner = EE::get_runner();
		self::set_property( $runner, 'config', array_merge( (array) $runner->config, $values ) );
	}

	/** @return string A new empty directory, removed after the test. */
	protected function sandbox() {
		$dir = EE_ROOT_DIR . '/sandbox-' . bin2hex( random_bytes( 6 ) );
		mkdir( $dir, 0700, true );
		$this->sandboxes[] = $dir;

		return $dir;
	}

	/**
	 * Insert a `sites` row with defaults for the NOT NULL columns.
	 *
	 * @return int Row id.
	 */
	protected function insert_site( array $fields ) {
		$fields += [
			'site_type'              => 'html',
			'site_fs_path'           => EE_ROOT_DIR . '/sites/' . ( isset( $fields['site_url'] ) ? $fields['site_url'] : 'x' ),
			'site_container_fs_path' => '/var/www/htdocs',
			'site_enabled'           => 1,
		];

		return (int) EE::db()->table( 'sites' )->insert( $fields );
	}

	/**
	 * Assert that no command run by $sink lets a hostile value reach the shell (see ShellProbe).
	 *
	 * @param callable    $sink    Receives each payload and calls the code under test with it.
	 * @param string|null $pattern Only probe commands matching this regex.
	 *
	 * @return string[] Every command that was probed.
	 */
	protected function assert_shell_safe( callable $sink, $pattern = null ) {
		$dir      = $this->sandbox();
		$failures = [];
		$probed   = [];
		foreach ( ShellProbe::payloads( 'eeprobemarker' ) as $name => $payload ) {
			$this->runner->calls = [];
			try {
				$sink( $payload );
			} catch ( ExitException $e ) {
				// A sink may reject the value after running commands; those still count.
			}
			$commands = $pattern ? $this->runner->matching( $pattern ) : $this->runner->commands();
			foreach ( $commands as $command ) {
				$probed[] = $command;
				ShellProbe::run( $command, $dir );
				if ( file_exists( $dir . '/eeprobemarker' ) ) {
					$failures[] = "[$name] $command";
					unlink( $dir . '/eeprobemarker' );
				}
			}
		}
		$this->assertNotEmpty( $probed, 'The sink ran no command, so nothing was checked.' );
		$this->assertSame( [], $failures, "Payloads reached the shell:\n" . implode( "\n", $failures ) );

		return $probed;
	}

	/** Call a private or protected method; $target is an object or a class name for static methods. */
	public static function call_private( $target, $method, ...$args ) {
		$ref = new \ReflectionMethod( $target, $method );
		if ( PHP_VERSION_ID < 80100 ) {
			$ref->setAccessible( true );
		}

		return $ref->invoke( is_object( $target ) ? $target : null, ...$args );
	}

	/** Read a private or protected static property. */
	public static function get_static( $class, $property ) {
		$ref = new \ReflectionProperty( $class, $property );
		if ( PHP_VERSION_ID < 80100 ) {
			$ref->setAccessible( true );
		}

		return $ref->getValue();
	}

	/** Write a private or protected static property. */
	public static function set_static( $class, $property, $value ) {
		$ref = new \ReflectionProperty( $class, $property );
		if ( PHP_VERSION_ID < 80100 ) {
			$ref->setAccessible( true );
		}
		$ref->setValue( null, $value );
	}

	/** Read a private or protected instance property. */
	public static function get_property( $object, $property ) {
		$ref = new \ReflectionProperty( $object, $property );
		if ( PHP_VERSION_ID < 80100 ) {
			$ref->setAccessible( true );
		}

		return $ref->getValue( $object );
	}

	/** Write a private or protected instance property. */
	public static function set_property( $object, $property, $value ) {
		$ref = new \ReflectionProperty( $object, $property );
		if ( PHP_VERSION_ID < 80100 ) {
			$ref->setAccessible( true );
		}
		$ref->setValue( $object, $value );
	}
}

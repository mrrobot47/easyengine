<?php

use EE\Tests\TestCase;
use EE\Tests\TestDB;

/**
 * DB migrations (core + package migrations/db) against a temp SQLite file, and the schema fixture they produce.
 *
 * Regenerate tests/phpunit/fixtures/schema.sql after a schema migration changes:
 * EE_PHPUNIT_WRITE_SCHEMA=1 php -d auto_prepend_file=tests/phpunit/prepend.php vendor/bin/phpunit --filter test_fresh_install_schema_matches_the_fixture
 */
class DbMigrationsTest extends TestCase {

	// They write the host's /etc/docker/daemon.json and restart Docker.
	const HOST_MIGRATIONS = [
		'20210728160510_site-command_add_daemon_json.php',
		'20230111111011_site-command_update_daemon_json.php',
	];

	const SCHEMA_PACKAGES = [ 'site-command', 'cron-command', 'auth-command' ];

	/** @return string[] Migration file name => path, sorted like Executor::execute_migrations(). */
	private static function db_migration_files( $packages = null ) {
		$files = [];
		foreach ( glob( EE_VENDOR_DIR . '/easyengine/*/migrations/db/*.php' ) as $path ) {
			if ( null === $packages || in_array( basename( dirname( $path, 3 ) ), $packages, true ) ) {
				$files[ basename( $path ) ] = $path;
			}
		}
		if ( null === $packages ) {
			foreach ( glob( EE_ROOT . '/migrations/db/*.php' ) as $path ) {
				$files[ basename( $path ) ] = $path;
			}
		}
		ksort( $files );

		return $files;
	}

	private static function class_name( $file ) {
		return self::call_private( 'EE\Migration\Executor', 'get_migration_class_name', $file );
	}

	/** Run the schema-relevant package migrations the way Executor does: constructor, then up(). */
	private static function migrate() {
		foreach ( self::db_migration_files( self::SCHEMA_PACKAGES ) as $file => $path ) {
			if ( in_array( $file, self::HOST_MIGRATIONS, true ) ) {
				continue;
			}
			require_once $path;
			$class     = self::class_name( $file );
			$migration = new $class();
			$migration->up();
		}
	}

	/** @return string[] Normalised CREATE statement per table. */
	private static function schema( PDO $pdo ) {
		$schema = [];
		foreach ( $pdo->query( "SELECT name, sql FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name" ) as $row ) {
			$schema[ $row['name'] ] = preg_replace( '/\s+/', ' ', trim( $row['sql'] ) );
		}

		return $schema;
	}

	public function migration_files() {
		$data = [];
		foreach ( self::db_migration_files() as $file => $path ) {
			$data[ $file ] = [ $file, $path ];
		}

		return $data;
	}

	/**
	 * REL-7 guard for every shipped migration: the class name derived from the file name is the class the file declares.
	 *
	 * @dataProvider migration_files
	 */
	public function test_class_name_derived_from_the_file_name_is_declared_in_the_file( $file, $path ) {
		$this->assertRegExpCompat( '/^\d+_[a-zA-Z-]+_.*\.php$/', $file, 'Executor only picks up files named <timestamp>_<package>_<name>.php' );
		preg_match( '/^namespace\s+([^;]+);/m', file_get_contents( $path ), $ns );
		preg_match_all( '/^\s*(?:abstract\s+|final\s+)?class\s+(\w+)/m', file_get_contents( $path ), $classes );
		$declared = array_map(
			function ( $class ) use ( $ns ) {
				return '\\' . ( empty( $ns[1] ) ? '' : trim( $ns[1] ) . '\\' ) . $class;
			},
			$classes[1]
		);
		$this->assertContains( self::class_name( $file ), $declared );
	}

	public function class_name_cases() {
		return [
			'plain'               => [ '20180910124650_site-command_create_table_site_migration.php', '\EE\Migration\CreateTableSiteMigration' ],
			'package with dashes' => [ '20181102014830_cron-command_no_overlap_migration.php', '\EE\Migration\NoOverlapMigration' ],
			'dotted version'      => [ '20240512115131_site-command_update_php_version_entry_7.4.php', '\EE\Migration\UpdatePhpVersionEntry7_4' ],
		];
	}

	/** @dataProvider class_name_cases */
	public function test_class_name_from_file_name( $file, $expected ) {
		$this->assertSame( $expected, self::class_name( $file ) );
	}

	public function trailing_letter_cases() {
		return [
			'ends in p' => [ '20240101000000_easyengine_fix_dump.php', '\EE\Migration\FixDump' ],
			'ends in h' => [ '20240101000000_easyengine_add_ssh.php', '\EE\Migration\AddSsh' ],
		];
	}

	/**
	 * REL-7 / MIG-18: rtrim( $name, '.php' ) strips any trailing '.', 'p' and 'h' characters, not the extension.
	 *
	 * @group known-bug
	 * @dataProvider trailing_letter_cases
	 */
	public function test_class_name_keeps_trailing_p_and_h( $file, $expected ) {
		$this->assertSame( $expected, self::class_name( $file ) );
	}

	public function test_container_migration_class_names_strip_only_the_extension() {
		$name = self::call_private( 'EE\Migration\CustomContainerMigrations', 'get_migration_class_name', '20240101000000_site-command_fix_dump.php' );
		$this->assertSame( '\EE\Migration\FixDump', $name );
	}

	public function test_fresh_install_schema_matches_the_fixture() {
		TestDB::reset( false );
		self::migrate();
		$migrated = self::schema( TestDB::pdo() );

		if ( getenv( 'EE_PHPUNIT_WRITE_SCHEMA' ) ) {
			$sql = '';
			foreach ( TestDB::pdo()->query( "SELECT sql FROM sqlite_master WHERE type = 'table' AND name NOT IN ('migrations', 'options') AND name NOT LIKE 'sqlite_%' ORDER BY name" ) as $row ) {
				$sql .= $row['sql'] . ";\n\n";
			}
			file_put_contents( dirname( __DIR__ ) . '/fixtures/schema.sql', "-- Generated by DbMigrationsTest from the package DB migrations (fresh install). Don't edit.\n\n" . $sql );
		}

		$fixture = new PDO( 'sqlite::memory:' );
		$fixture->exec( file_get_contents( dirname( __DIR__ ) . '/fixtures/schema.sql' ) );
		$this->assertSame( array_diff_key( $migrated, [ 'migrations' => 1, 'options' => 1 ] ), self::schema( $fixture ) );
		$this->assertSame( [ 'auth_ips', 'auth_users', 'cron', 'migrations', 'options', 'site_meta', 'sites' ], array_keys( $migrated ) );
	}

	public function test_upgrade_adds_the_newer_sites_columns() {
		TestDB::reset( false );
		EE\Model\Option::set( 'version', '4.0.0' );
		// The sites table of the first release, before site_container_fs_path, proxy_cache and alias_domains.
		TestDB::pdo()->exec( 'CREATE TABLE sites ( id INTEGER NOT NULL, site_url VARCHAR NOT NULL, site_type VARCHAR NOT NULL, site_fs_path VARCHAR NOT NULL, php_version VARCHAR, PRIMARY KEY (id), UNIQUE (site_url) )' );
		TestDB::pdo()->exec( "INSERT INTO sites ( site_url, site_type, site_fs_path, php_version ) VALUES ( 'old.test', 'php', '/opt/easyengine/sites/old.test', 'latest' )" );

		foreach ( [
			'20190104060950_site-command_add_column_site_container_fs_path_migration.php',
			'20200317060950_site-command_add_column_proxy_cache_and_custom_domains_migration.php',
		] as $file ) {
			require_once EE_VENDOR_DIR . '/easyengine/site-command/migrations/db/' . $file;
			$class = self::class_name( $file );
			( new $class() )->up();
		}

		$row = TestDB::rows( 'sites' )[0];
		$this->assertSame( '/var/www/htdocs', $row['site_container_fs_path'] );
		$this->assertSame( 'off', $row['proxy_cache'] );
		$this->assertNull( $row['alias_domains'] );
	}

	public function test_fresh_install_skips_the_add_column_migrations() {
		TestDB::reset();
		$file = '20200317060950_site-command_add_column_proxy_cache_and_custom_domains_migration.php';
		require_once EE_VENDOR_DIR . '/easyengine/site-command/migrations/db/' . $file;
		$class = self::class_name( $file );
		// Would throw "duplicate column name" if it ran on the fresh schema.
		( new $class() )->up();
		$this->assertContains( 'alias_domains', TestDB::columns( 'sites' ) );
	}

	/** Run the docker/compose check migration with a fake docker-compose binary at $compose_version. */
	private function run_check_and_update_docker_one( $compose_version ) {
		$compose = $this->sandbox() . '/docker-compose';
		file_put_contents( $compose, 'binary' );
		$this->runner->on( '/^docker version /', "29.8.1\n" );
		$this->runner->on( '/^docker-compose version --short$/', "$compose_version\n" );
		$this->runner->on( '/^command -v docker-compose$/', "$compose\n" );
		require_once EE_ROOT . '/migrations/db/20240502102550_easyengine_check_and_update_docker_one.php';
		try {
			( new EE\Migration\CheckAndUpdateDockerOne() )->up();
		} catch ( EE\ExitException $e ) {
			// It errors when the (faked) compose version is still not 1.29.2 after the download.
		}
		@unlink( EE_BACKUP_DIR . '/docker-compose.backup' );

		return $compose;
	}

	public function test_check_and_update_docker_one_replaces_compose_on_upgrade() {
		EE\Model\Option::set( 'version', '4.7.0' );
		$compose = $this->run_check_and_update_docker_one( '2.27.0' );
		$new     = EE_BACKUP_DIR . '/docker-compose';
		$this->assertSame(
			[
				"curl -L https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m) -o $new && chmod +x $new",
				"mv $new $compose",
			],
			$this->runner->matching( '/^(curl|mv) /' )
		);
		$this->assertStringContainsString( 'Docker-compose version should be 1.29.2', $this->stderr() );
	}

	/**
	 * MIG-20: the constructor doesn't call parent::__construct(), so the first-execution skip never applies and a fresh install downgrades docker-compose to 1.29.2.
	 *
	 * @group known-bug
	 * @group MIG-20
	 */
	public function test_check_and_update_docker_one_is_skipped_on_a_fresh_install() {
		$this->assertFalse( EE\Model\Option::get( 'version' ) );
		$this->run_check_and_update_docker_one( '5.5.1' );
		$this->assertSame( [], $this->runner->commands() );
	}

	private function assertRegExpCompat( $pattern, $string, $message = '' ) {
		$this->assertSame( 1, preg_match( $pattern, $string ), $message . ": $string" );
	}
}

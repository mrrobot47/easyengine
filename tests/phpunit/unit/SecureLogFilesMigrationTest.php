<?php

use EE\Tests\TestCase;

/**
 * The migration that makes existing logs private and masks the secrets older versions wrote (LOG-4).
 *
 * @group known-bug
 * @group LOG-4
 */
class SecureLogFilesMigrationTest extends TestCase {

	const MIGRATION = 'migrations/db/20261001100000_easyengine_secure_log_files.php';

	private $logs;

	protected function setUp(): void {
		parent::setUp();
		$this->logs = EE_ROOT_DIR . '/logs';
		exec( 'rm -rf ' . escapeshellarg( $this->logs ) );
		mkdir( $this->logs, 0755 );
		chmod( $this->logs, 0755 );
	}

	protected function tearDown(): void {
		if ( property_exists( 'EE', 'obfuscated' ) ) {
			self::set_static( 'EE', 'obfuscated', [] );
			self::set_static( 'EE', 'obfuscated_map', null );
		}
		@unlink( getenv( 'EE_CONFIG_PATH' ) );
		exec( 'rm -rf ' . escapeshellarg( $this->logs ) );
		@mkdir( $this->logs, 0700 );
		parent::tearDown();
	}

	private function write_log( $name, $contents, $mode = 0644 ) {
		$path = $this->logs . '/' . $name;
		if ( '.gz' === substr( $name, -3 ) ) {
			file_put_contents( $path, gzencode( $contents ) );
		} else {
			file_put_contents( $path, $contents );
		}
		chmod( $path, $mode );
		touch( $path, 1700000000 );

		return $path;
	}

	private function read_log( $path ) {
		$data = file_get_contents( $path );

		return '.gz' === substr( $path, -3 ) ? gzdecode( $data ) : $data;
	}

	private function mode( $path ) {
		clearstatcache();

		return substr( sprintf( '%o', fileperms( $path ) ), -4 );
	}

	private function run_migration() {
		$this->assertFileExists( EE_ROOT . '/' . self::MIGRATION );
		require_once EE_ROOT . '/' . self::MIGRATION;
		$migration = new EE\Migration\SecureLogFiles();
		$migration->up();
	}

	public function test_modes_are_restricted_and_old_secret_shapes_are_masked() {
		$this->insert_site( [ 'site_url' => 'live.test', 'site_type' => 'wp', 'db_password' => 'LiveDbPw123', 'app_admin_password' => 'LiveAdmin99' ] );
		EE::db()->table( 'auth_users' )->insert( [ 'site_url' => 'default', 'username' => 'u', 'password' => 'AuthPw4567' ] );
		file_put_contents( getenv( 'EE_CONFIG_PATH' ), "le-mail: a@b.test\ncloudflare-api-key: CfKey0123456789\n" );

		$old = implode(
			"\n",
			[
				'[d] ee.DEBUG: argv: /usr/local/bin/ee site create gone.test --type=wp --admin-pass=GoneAdmin1 --dbpass=GoneDb1  ',
				'[d] site_wp_command.DEBUG: assoc_args: {"type":"wp","admin-pass":"GoneAdmin1","dbpass":"GoneDb1"} []',
				'[d] ee.INFO: CfKey0123456789  ',
				'[d] ee.DEBUG: argv: /usr/local/bin/ee config set cloudflare-api-key OldCfKey987  ',
				"[d] ee.DEBUG: STDERR: CREATE USER 'u1'@'%' IDENTIFIED BY 'Gone\\'Pw2'",
				"[d] ee.DEBUG: STDOUT: Success: Updated the constant 'DB_PASSWORD' in the 'wp-config.php' file with the value 'LiveDbPw123'.",
				'[d] ee.DEBUG: COMMAND: ee shell gone.test --command=\'mysql -u"u" -p"CloneDb9" db\'',
				"[d] ee.DEBUG: COMMAND: openssl genrsa -des3 -passout pass:'CaPass77' -out k 2048",
				'[d] ee.DEBUG: wp login LiveAdmin99 and auth AuthPw4567',
				'[d] ee.INFO: ::::::::::::::::::::::::ee invoked::::::::::::::::::::::::  ',
				'[d] ee.DEBUG: argv: /usr/local/bin/ee config get cloudflare-api-key  ',
				'[d] ee.INFO: GoneCfKey55  ',
				'[d] ee.INFO: ::::::::::::::::::::::::ee invoked::::::::::::::::::::::::  ',
				'[d] ee.DEBUG: argv: /usr/local/bin/ee config list --format=text  ',
				'[d] ee.INFO: le-mail: a@b.test  ',
				'[d] ee.INFO: cloudflare-api-key: GoneCfKey66  ',
				'[d] ee.DEBUG: Parsed verify_token: DashTok77  ',
				'[d] ee.DEBUG: Payload being sent: {"site":"gone.test","verify":"DashTok88","metadata":{}}  ',
				"[d] ee.ERROR: Issues found in input password: `weak1` \t* Password too short!  ",
				'[d] ee.INFO: ::::::::::::::::::::::::ee invoked::::::::::::::::::::::::  ',
				'[d] ee.INFO: Site gone.test created. user=admin',
				'',
			]
		);
		$plain   = $this->write_log( 'ee.log.1', $old );
		$gz      = $this->write_log( 'ee.log.2.gz', $old );
		$active  = $this->write_log( 'ee.log', $old );
		$cron    = $this->write_log( 'cron.log', "renewed\n" );
		// A handler opened before the migration must write to the new ee.log afterwards.
		$logger = EE::get_file_logger();
		EE::set_file_logger( new Monolog\Logger( 'ee', [ new Monolog\Handler\StreamHandler( $active ) ] ) );
		EE::get_file_logger()->info( 'before the migration --dbpass=BeforePw1' );

		try {
			$this->run_migration();
			EE::get_file_logger()->info( 'after the migration' );
		} finally {
			EE::set_file_logger( $logger );
		}

		$this->assertSame( '0700', $this->mode( $this->logs ) );
		foreach ( [ $plain, $gz, $active, $cron ] as $file ) {
			$this->assertSame( '0600', $this->mode( $file ), $file );
		}
		foreach ( [ $plain, $gz, $active ] as $file ) {
			$contents = $this->read_log( $file );
			foreach ( [ 'GoneAdmin1', 'GoneDb1', 'CfKey0123456789', 'OldCfKey987', 'Gone\\\'Pw2', 'Pw2', 'LiveDbPw123', 'CloneDb9', 'CaPass77', 'LiveAdmin99', 'AuthPw4567', 'GoneCfKey55', 'GoneCfKey66', 'DashTok77', 'DashTok88', 'weak1', 'BeforePw1' ] as $secret ) {
				$this->assertStringNotContainsString( $secret, $contents, "$secret in $file" );
			}
			$this->assertStringContainsString( 'Site gone.test created. user=admin', $contents );
			$this->assertStringContainsString( '--type=wp --admin-pass=****** --dbpass=******', $contents );
			$this->assertStringContainsString( 'ee.INFO: le-mail: a@b.test', $contents );
			$this->assertGreaterThanOrEqual( 21, substr_count( $contents, "\n" ), $file );
		}
		$active_log = file_get_contents( $active );
		$this->assertStringContainsString( 'before the migration --dbpass=******', $active_log );
		$this->assertStringContainsString( 'after the migration', $active_log );
		$this->assertSame( 1700000000, filemtime( $gz ), 'rotated logs keep their time' );
		$this->assertSame( 1700000000, filemtime( $plain ), 'rotated logs keep their time' );
		$this->assertSame( 21, substr_count( $this->read_log( $plain ), "\n" ) );
		$this->assertSame( [], glob( $this->logs . '/*.ee-scrub' ) );
		$this->assertSame( "renewed\n", file_get_contents( $cron ) );
	}

	public function test_symlinks_are_not_followed() {
		$target = $this->sandbox() . '/elsewhere.log';
		file_put_contents( $target, "--admin-pass=Secret123\n" );
		chmod( $target, 0644 );
		symlink( $target, $this->logs . '/link.log' );

		$this->run_migration();

		$this->assertSame( '0644', $this->mode( $target ) );
		$this->assertSame( "--admin-pass=Secret123\n", file_get_contents( $target ) );
	}

	public function test_unchanged_files_keep_their_time() {
		$path = $this->write_log( 'ee.log.3', "nothing secret\n" );

		$this->run_migration();

		$this->assertSame( 1700000000, filemtime( $path ) );
		$this->assertSame( '0600', $this->mode( $path ) );
	}
}

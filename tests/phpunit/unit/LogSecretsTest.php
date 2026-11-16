<?php

use EE\Tests\TestCase;

/**
 * Secrets stay out of ee.log and debug output, and the log is readable by root only (LOG-2, LOG-4, CFG-8).
 *
 * @group known-bug
 */
class LogSecretsTest extends TestCase {

	private $file_logger;

	protected function setUp(): void {
		parent::setUp();
		$this->file_logger = EE::get_file_logger();
		exec( 'rm -rf ' . escapeshellarg( EE_ROOT_DIR . '/logs' ) );
	}

	protected function tearDown(): void {
		EE::set_file_logger( $this->file_logger );
		if ( property_exists( 'EE', 'obfuscated' ) ) {
			self::set_static( 'EE', 'obfuscated', [] );
			self::set_static( 'EE', 'obfuscated_map', null );
		}
		exec( 'rm -rf ' . escapeshellarg( EE_ROOT_DIR . '/logs' ) );
		@mkdir( EE_ROOT_DIR . '/logs', 0700 );
		parent::tearDown();
	}

	/**
	 * Give $dir a default ACL granting others rwx, as GitHub runners have on /opt; skips where that isn't possible or has no effect.
	 */
	private function give_default_acl( $dir ) {
		exec( 'command -v setfacl', $out, $rc );
		if ( 0 !== $rc ) {
			$this->markTestSkipped( 'setfacl (package acl) is not installed.' );
		}
		exec( 'setfacl -d -m o::rwx ' . escapeshellarg( $dir ) . ' 2>&1', $out, $rc );
		$probe = $dir . '/acl-probe';
		$umask = umask( 0077 );
		touch( $probe );
		umask( $umask );
		clearstatcache();
		$mode = fileperms( $probe ) & 0777;
		unlink( $probe );
		if ( 0 !== $rc || 0600 === $mode ) {
			$this->markTestSkipped( 'A default ACL has no effect on this filesystem.' );
		}
	}

	/** @return string The log file written by the real file logger set up by Runner::init_logger(). */
	private function init_file_logger() {
		// init_logger() also replaces the terminal logger.
		$logger = self::logger();
		EE::get_runner()->init_logger();
		EE::set_logger( $logger );

		return EE_ROOT_DIR . '/logs/ee.log';
	}

	/**
	 * @group LOG-2
	 */
	public function test_obfuscated_values_are_masked_in_logged_stdout_and_stderr() {
		$this->set_config( [ 'debug' => true ] );
		$this->runner->on( '/^htpasswd/', "stored s3cretPW\n", 0, 'Adding password s3cretPW' );

		EE::exec( "htpasswd -b f user 's3cretPW'", false, false, [ 's3cretPW' ] );

		$this->assertStringContainsString( 'STDOUT: stored ******', $this->stderr() );
		$this->assertStringContainsString( 'STDERR: Adding password ******', $this->stderr() );
		$this->assertStringNotContainsString( 's3cretPW', $this->stderr() );
		$this->assertSame( [ "htpasswd -b f user 's3cretPW'" ], $this->runner->commands() );
	}

	/**
	 * @group LOG-2
	 */
	public function test_registered_values_are_masked_in_every_command_and_its_output() {
		$this->set_config( [ 'debug' => true ] );
		$this->runner->on( '/^wp/', "value it'\\''s-Pass99\n", 0, 'p="it\'s-Pass99"' );

		EE::obfuscate( "it's-Pass99" );
		EE::launch( "wp config set DB_PASSWORD 'it'\\''s-Pass99'" );

		$this->assertStringNotContainsString( 'Pass99', $this->stderr() );
		$this->assertStringContainsString( "COMMAND: wp config set DB_PASSWORD '******'", $this->stderr() );
	}

	/**
	 * @group LOG-2
	 */
	public function test_short_values_are_not_registered_but_explicit_obfuscate_still_masks_them() {
		$this->set_config( [ 'debug' => true ] );
		EE::obfuscate( 'abc' );
		EE::exec( 'echo abc xyz', false, false, [ 'xyz' ] );

		$this->assertStringContainsString( 'COMMAND: echo abc ******', $this->stderr() );
	}

	/**
	 * @group LOG-4
	 */
	public function test_a_new_log_directory_and_file_are_private() {
		$umask = umask( 0022 );
		$log   = $this->init_file_logger();
		umask( $umask );

		$this->assertSame( '0700', substr( sprintf( '%o', fileperms( dirname( $log ) ) ), -4 ) );
		$this->assertSame( '0600', substr( sprintf( '%o', fileperms( $log ) ), -4 ) );
	}

	/**
	 * LOG-6: a default ACL on the logs dir overrides the umask, so the new log needs an explicit mode.
	 *
	 * @group LOG-6
	 */
	public function test_a_new_log_file_is_private_under_a_default_acl() {
		mkdir( EE_ROOT_DIR . '/logs', 0700 );
		$this->give_default_acl( EE_ROOT_DIR . '/logs' );

		$log = $this->init_file_logger();

		clearstatcache();
		$this->assertSame( '0600', substr( sprintf( '%o', fileperms( $log ) ), -4 ) );
	}

	/**
	 * @group LOG-4
	 */
	public function test_existing_log_modes_are_left_for_the_migration() {
		mkdir( EE_ROOT_DIR . '/logs', 0755 );
		touch( EE_ROOT_DIR . '/logs/ee.log' );
		chmod( EE_ROOT_DIR . '/logs', 0755 );
		chmod( EE_ROOT_DIR . '/logs/ee.log', 0644 );

		$log = $this->init_file_logger();

		$this->assertSame( '0644', substr( sprintf( '%o', fileperms( $log ) ), -4 ) );
	}

	/**
	 * @group LOG-4
	 * @group CFG-8
	 */
	public function test_log_file_masks_registered_values_secret_flags_and_secret_context_keys() {
		$log = $this->init_file_logger();

		EE::obfuscate( 'CfKey0123456789' );
		EE::log( 'CfKey0123456789' );
		EE::debug( 'argv: ee site create a.test --admin-pass=Adm1nPass --dbpass="x y" --type=wp' );
		EE::warning( 'remote said {"db_password":"Rem0tePw","db_user":"u"}' );
		EE::get_file_logger()->withName( 'site_wp_command' )->debug(
			'assoc_args:',
			[
				'type'       => 'wp',
				'admin-pass' => 'ab1',
				'nested'     => [ 'cloudflare-api-key' => 'k1' ],
			]
		);

		$contents = file_get_contents( $log );
		foreach ( [ 'CfKey0123456789', 'Adm1nPass', 'x y', 'Rem0tePw', 'ab1', 'k1' ] as $secret ) {
			$this->assertStringNotContainsString( $secret, $contents, $secret );
		}
		$this->assertStringContainsString( '--admin-pass=****** --dbpass="******" --type=wp', $contents );
		$this->assertStringContainsString( '"type":"wp"', $contents );
		$this->assertStringContainsString( '"db_user":"u"', $contents );
		// What the user asked to see is printed unchanged.
		$this->assertStringContainsString( 'CfKey0123456789', $this->stdout() );
	}

	/**
	 * @group LOG-4
	 * @group CFG-8
	 */
	public function test_argv_secret_flags_and_config_set_values_are_masked() {
		list( $argv, $secrets ) = EE\Utils\mask_secret_argv( [ 'ee', '--debug', 'config', 'set', 'cloudflare-api-key', 'Key9' ] );
		$this->assertSame( [ 'ee', '--debug', 'config', 'set', 'cloudflare-api-key', '******' ], $argv );
		$this->assertSame( [ 'Key9' ], $secrets );

		list( $argv, $secrets ) = EE\Utils\mask_secret_argv( [ 'ee', 'site', 'create', 'a.test', '--admin-pass=a b', '--dash-auth=1:tok', '--admin-user=admin', '--api=t:k' ] );
		$this->assertSame( [ 'ee', 'site', 'create', 'a.test', '--admin-pass=******', '--dash-auth=******', '--admin-user=admin', '--api=******' ], $argv );
		$this->assertSame( [ 'a b', '1:tok', 'tok', 't:k', 'k' ], $secrets );

		list( $argv ) = EE\Utils\mask_secret_argv( [ 'ee', 'config', 'set', 'le-mail', 'a@b.test' ] );
		$this->assertSame( 'a@b.test', $argv[4] );
	}

	/**
	 * @group LOG-4
	 */
	public function test_secret_key_names() {
		foreach ( [ 'admin-pass', 'dbpass', 'dbrootpass', 'pass', 'password', '--admin_password', 'cloudflare-api-key', 'dash-auth', 'api', 'verify_token', 'client-secret' ] as $key ) {
			$this->assertTrue( EE\Utils\is_secret_key( $key ), $key );
		}
		foreach ( [ 'admin-user', 'dbuser', 'le-mail', 'ssl-key', 'type', 'title', 0 ] as $key ) {
			$this->assertFalse( EE\Utils\is_secret_key( $key ), (string) $key );
		}
	}

	/**
	 * @group LOG-4
	 */
	public function test_loaded_and_saved_models_mask_their_secrets() {
		$this->set_config( [ 'debug' => true ] );
		$this->insert_site( [ 'site_url' => 'model.test', 'site_type' => 'wp', 'db_password' => 'ModelDbPw1', 'app_admin_password' => 'ModelAdm2' ] );
		EE\Model\Option::set( 'self-signed-secret', 'SelfSigned3' );
		self::set_static( 'EE', 'obfuscated', [] );
		self::set_static( 'EE', 'obfuscated_map', null );

		EE::db()->table( 'sites' )->select()->get();
		EE::debug( 'raw query rows are not models: ModelDbPw1' );
		$this->assertStringContainsString( 'ModelDbPw1', $this->stderr() );

		EE\Model\Option::get( 'self-signed-secret' );
		$this->assertNotFalse( LogSecretsTestSite::find( 'model.test' ) );
		self::logger()->stderr = '';
		EE::debug( 'ModelDbPw1 ModelAdm2 SelfSigned3' );
		$this->assertSame( "Debug: ****** ****** ******\n", preg_replace( '/ \(\d+\.\d+s\)/', '', $this->stderr() ) );
	}

	/**
	 * @group LOG-4
	 */
	public function test_token_part_of_a_secret_flag_and_long_values_are_masked() {
		list( , $secrets ) = EE\Utils\mask_secret_argv( [ 'ee', 'site', 'backup', 'a.test', '--dash-auth=17:VerifyTok99' ] );
		$this->assertSame( [ '17:VerifyTok99', 'VerifyTok99' ], $secrets );

		$long = str_repeat( 'x', 300000 );
		$this->assertSame( '--admin-pass=****** --dbpass=****** x', EE\Utils\mask_secret_patterns( "--admin-pass=$long --dbpass=zz x" ) );
		$this->assertSame( '{"api_key":"******","n":"zz"}', EE\Utils\mask_secret_patterns( '{"api_key":"' . $long . '","n":"zz"}' ) );
	}

	/**
	 * @group LOG-4
	 */
	public function test_flag_patterns_keep_shell_variables_and_cover_quoting() {
		$cases = [
			"wp core install --admin_password='p w' --admin_user='a'" => "wp core install --admin_password='******' --admin_user='a'",
			"x --dbpass='it'\\''s' y"                                 => "x --dbpass='******' y",
			'mysql --password="a\\"b" -e 1'                           => 'mysql --password="******" -e 1',
			'wp config set DB_PASSWORD "$value" --dbpass="$value"'    => 'wp config set DB_PASSWORD "$value" --dbpass="$value"',
			'--password= --le-mail=a@b.test'                          => '--password= --le-mail=a@b.test',
			"x --dbpass='\$ecret' y"                                  => "x --dbpass='******' y",
			'{"api_key":12345,"x":1}'                                 => '{"api_key":******,"x":1}',
			"mysql -u'u' -p'S3cret' db"                               => "mysql -u'u' -p'******' db",
			'mysqldump --skip-ssl -u u1 -pDumpPw4 -h db d1'           => 'mysqldump --skip-ssl -u u1 -p****** -h db d1',
			'mkdir -p /x && ssh -p22 h'                               => 'mkdir -p /x && ssh -p22 h',
			"openssl genrsa -des3 -passout pass:'CaPw' -out k"        => "openssl genrsa -des3 -passout pass:'******' -out k",
		];
		foreach ( $cases as $in => $out ) {
			$this->assertSame( $out, EE\Utils\mask_secret_patterns( $in ), $in );
		}
	}
}

/** A sites model as the packages define it. */
class LogSecretsTestSite extends EE\Model\Base {
	protected static $table       = 'sites';
	protected static $primary_key = 'site_url';
}

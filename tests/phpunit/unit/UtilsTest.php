<?php

use EE\Tests\TestCase;
use EE\Utils;

/**
 * Functions in php/utils.php (EE\Utils).
 */
class UtilsTest extends TestCase {

	protected $reset_db = false;

	public function test_is_path_absolute() {
		$this->assertTrue( Utils\is_path_absolute( '/opt/easyengine' ) );
		$this->assertTrue( Utils\is_path_absolute( 'C:\\sites' ) );
		$this->assertFalse( Utils\is_path_absolute( 'sites/a.test' ) );
		$this->assertFalse( Utils\is_path_absolute( './x' ) );
	}

	public function test_args_and_assoc_args_to_str_quote_every_value() {
		$this->assertSame( " 'a.test' 'it'\\''s'", Utils\args_to_str( [ 'a.test', "it's" ] ) );
		$this->assertSame(
			" --url='foo.dev' --require='file-a.php' --require='file-b.php' --porcelain --apple='banana'",
			Utils\assoc_args_to_str( [ 'url' => 'foo.dev', 'require' => [ 'file-a.php', 'file-b.php' ], 'porcelain' => true, 'apple' => 'banana' ] )
		);
		$this->assertSame( " --title=''", Utils\assoc_args_to_str( [ 'title' => false ] ) );
	}

	public function test_command_builders_are_shell_safe() {
		$this->assert_shell_safe(
			function ( $payload ) {
				EE::exec( 'true' . Utils\args_to_str( [ $payload ] ) . Utils\assoc_args_to_str( [ 'title' => $payload, 'list' => [ $payload ] ] ) );
				EE::exec( Utils\esc_cmd( 'true %s --name=%s', $payload, $payload ) );
			}
		);
	}

	public function test_esc_cmd_quotes_the_arguments_into_the_template() {
		$this->assertSame( "tar xz --directory='/tmp/a b' -f 'x.tar.gz'", Utils\esc_cmd( 'tar xz --directory=%s -f %s', '/tmp/a b', 'x.tar.gz' ) );
	}

	public function test_pick_fields_fills_missing_fields_with_null() {
		$this->assertSame( [ 'a' => 1, 'c' => null ], Utils\pick_fields( [ 'a' => 1, 'b' => 2 ], [ 'a', 'c' ] ) );
		$this->assertSame( [ 'b' => 2 ], Utils\pick_fields( (object) [ 'a' => 1, 'b' => 2 ], [ 'b' ] ) );
	}

	public function test_mustache_render_does_not_html_escape() {
		$dir = $this->sandbox();
		file_put_contents( "$dir/t.mustache", "server_name {{domain}};\n{{#aliases}}alias {{.}};\n{{/aliases}}{{^ssl}}no ssl{{/ssl}}" );
		$this->assertSame(
			"server_name a.test <b>&amp;</b>;\nalias b.test;\nalias c.test;\nno ssl",
			Utils\mustache_render( "$dir/t.mustache", [ 'domain' => 'a.test <b>&amp;</b>', 'aliases' => [ 'b.test', 'c.test' ], 'ssl' => false ] )
		);
	}

	public function test_mustache_render_falls_back_to_the_core_templates_dir() {
		$out = Utils\mustache_render( 'man-params.mustache', [ 'parameters' => [ [ 'synopsis' => '--debug', 'desc' => 'Verbose.' ] ], 'root_command' => true ] );
		$this->assertStringContainsString( "## GLOBAL PARAMETERS\n\n  --debug\n      Verbose.\n", $out );
		$this->assertStringContainsString( "Run 'ee help <command>'", $out );
	}

	public function test_is_assoc() {
		$this->assertTrue( Utils\is_assoc( [ 'a' => 1 ] ) );
		$this->assertTrue( Utils\is_assoc( [ 1, 'b' => 2 ] ) );
		$this->assertFalse( Utils\is_assoc( [ 1, 2 ] ) );
		$this->assertFalse( Utils\is_assoc( [] ) );
	}

	public function test_parse_url_adds_a_default_scheme() {
		$this->assertSame( [ 'scheme' => 'http', 'host' => 'a.test', 'path' => '/wp-admin' ], Utils\parse_url( 'a.test/wp-admin' ) );
		$this->assertSame( [ 'scheme' => 'https', 'host' => 'a.test', 'port' => 8443 ], Utils\parse_url( 'https://a.test:8443' ) );
	}

	public function test_flag_helpers() {
		$args = [ 'ssl' => 'le', 'cache' => true, 'empty' => '', 'no' => false ];
		$this->assertSame( 'le', Utils\get_flag_value( $args, 'ssl' ) );
		$this->assertSame( 'd', Utils\get_flag_value( $args, 'missing', 'd' ) );
		$this->assertFalse( Utils\get_flag_value( $args, 'no', 'd' ) );

		// A bare flag or empty value takes the default; a value wins; an unset flag is ''.
		$this->assertSame( 'le', Utils\get_value_if_flag_isset( $args, 'cache', 'le' ) );
		$this->assertSame( 'le', Utils\get_value_if_flag_isset( $args, 'empty', 'le' ) );
		$this->assertSame( 'le', Utils\get_value_if_flag_isset( $args, 'ssl', 'self' ) );
		$this->assertSame( '', Utils\get_value_if_flag_isset( $args, 'missing', 'le' ) );
		$this->assertTrue( Utils\get_value_if_flag_isset( $args, 'cache' ) );
	}

	public function test_get_type_needs_exactly_one_flag() {
		$types = [ 'wp', 'php', 'html' ];
		$this->assertSame( 'php', Utils\get_type( [ 'php' => true ], $types ) );
		$this->assertSame( 'html', Utils\get_type( [], $types, 'html' ) );
		$this->assertFalse( Utils\get_type( [ 'wp' => true, 'php' => true ], $types, 'html' ) );
		$this->assertSame( 'html', Utils\get_type( [ 'wp' => false ], $types, 'html' ) );
	}

	public function test_random_password_length_and_alphabet() {
		$this->assertMatchesRegularExpression( '/^[a-zA-Z0-9]{18}$/', Utils\random_password() );
		$this->assertMatchesRegularExpression( '/^[a-zA-Z0-9]{40}$/', Utils\random_password( 40 ) );
		$this->assertSame( '', Utils\random_password( 0 ) );
	}

	public function test_random_wp_user_name_has_a_digit_at_the_second_or_third_position() {
		for ( $i = 0; $i < 50; $i++ ) {
			$name = Utils\random_name_generator();
			$this->assertMatchesRegularExpression( '/^wp-user-[a-z0-9]{4,6}$/', $name );
			$suffix = substr( $name, 8 );
			$this->assertTrue( ctype_digit( $suffix[1] ) || ctype_digit( $suffix[2] ), $name );
		}
	}

	public function test_array_flatten_and_callable_names() {
		$this->assertSame( [ 1, 2, 3, 4 ], Utils\array_flatten( [ 1, [ 2, [ 3 ] ], [ 'k' => 4 ] ] ) );
		$this->assertSame( 'EE\Utils\trailingslashit', Utils\get_callable_name( 'EE\Utils\trailingslashit' ) );
		$this->assertSame( 'EE_DOCKER::get_docker_style_prefix', Utils\get_callable_name( [ 'EE_DOCKER', 'get_docker_style_prefix' ] ) );
		$this->assertSame( 'UtilsTest::test_is_assoc', Utils\get_callable_name( [ $this, 'test_is_assoc' ] ) );
		$this->assertSame( 'closure', Utils\get_callable_name( function () {} ) );
	}

	public function test_get_image_versions_reads_img_versions_json() {
		$versions = Utils\get_image_versions();
		$this->assertSame( json_decode( file_get_contents( EE_ROOT . '/img-versions.json' ), true ), $versions );
		foreach ( $versions as $image => $tag ) {
			$this->assertMatchesRegularExpression( '#^easyengine/[a-z0-9.-]+$#', $image );
			$this->assertMatchesRegularExpression( '/^v\d+\.\d+\.\d+$/', $tag, $image );
		}
		foreach ( [ 'nginx-proxy', 'nginx', 'mariadb', 'redis', 'cron', 'postfix', 'php', 'php7.4', 'php8.4', 'php8.5' ] as $image ) {
			$this->assertArrayHasKey( "easyengine/$image", $versions );
		}
	}

	public function test_get_config_value_reads_the_config_file() {
		file_put_contents( getenv( 'EE_CONFIG_PATH' ), "le-mail: admin@example.test\nno-of-backups: 3\nempty: ''\n" );
		try {
			$this->assertSame( 'admin@example.test', Utils\get_config_value( 'le-mail' ) );
			$this->assertSame( 3, Utils\get_config_value( 'no-of-backups', 7 ) );
			$this->assertSame( 7, Utils\get_config_value( 'empty', 7 ) );
			$this->assertNull( Utils\get_config_value( 'missing' ) );
		} finally {
			unlink( getenv( 'EE_CONFIG_PATH' ) );
		}
	}

	public function sanitized_names() {
		return [
			'plain'              => [ 'backup-2024_01', true, false, 'backup-2024_01' ],
			'illegal chars'      => [ 'a"b*c:d<e>f?g\'h|i', true, false, 'abcdefghi' ],
			'strict drops space' => [ 'my site.sql', true, false, 'mysitesql' ],
			'loose keeps dots'   => [ 'my site.sql', false, false, 'my-site.sql' ],
			'leading dash'       => [ '--rm -rf', false, false, 'rm-rf' ],
			'slashes kept'       => [ 'a/b', true, false, 'a/b' ],
			'slashes removed'    => [ '../a/b', true, true, 'ab' ],
			'repeats collapsed'  => [ 'a--b__c', true, false, 'a-b_c' ],
		];
	}

	/**
	 * @dataProvider sanitized_names
	 */
	public function test_sanitize_file_folder_name( $input, $strict, $remove_slashes, $expected ) {
		$this->assertSame( $expected, Utils\sanitize_file_folder_name( $input, $strict, $remove_slashes ) );
	}

	public function test_get_suggestion() {
		$options = [ 'create', 'delete', 'list', 'info', 'enable' ];
		$this->assertSame( 'create', Utils\get_suggestion( 'add', $options ) );
		$this->assertSame( 'delete', Utils\get_suggestion( 'remove', $options ) );
		$this->assertSame( 'list', Utils\get_suggestion( 'lsit', $options ) );
		$this->assertSame( '', Utils\get_suggestion( 'zzzzzz', $options ) );
		$this->assertSame( '', Utils\get_suggestion( 'list', $options ) );
		$this->assertSame( '', Utils\get_suggestion( 'x', [] ) );
	}

	public function test_basename_is_locale_independent() {
		$this->assertSame( 'wp-config.php', Utils\basename( '/var/www/htdocs/wp-config.php' ) );
		$this->assertSame( 'ñandú.sql', Utils\basename( '/tmp/ñandú.sql' ) );
		$this->assertSame( 'site', Utils\basename( 'C:\\backups\\site.zip', '.zip' ) );
	}

	public function test_replace_path_consts() {
		$this->assertSame( "require '/opt/ee/a.php'; \$d = '/opt/ee';", Utils\replace_path_consts( 'require __FILE__; $d = __DIR__;', '/opt/ee/a.php' ) );
	}

	public function test_copy_recursive_and_delete_dir() {
		$src = $this->sandbox();
		mkdir( "$src/conf/nginx", 0755, true );
		file_put_contents( "$src/conf/nginx/main.conf", 'server {}' );
		file_put_contents( "$src/.env", 'A=1' );
		$dest = $this->sandbox() . '/copy';

		$this->assertTrue( Utils\copy_recursive( $src, $dest ) );
		$this->assertSame( 'server {}', file_get_contents( "$dest/conf/nginx/main.conf" ) );
		$this->assertSame( 'A=1', file_get_contents( "$dest/.env" ) );

		$this->assertTrue( Utils\delete_dir( $dest ) );
		$this->assertDirectoryDoesNotExist( $dest );
		$this->assertFalse( Utils\copy_recursive( $src, "$dest/missing-parent/x" ) );
	}

	public function test_format_table_prints_rows_between_separators() {
		Utils\format_table( [ [ 'Site', 'a.test' ], [ 'Type', 'wp' ] ] );
		$this->assertSame( "+------+--------+\n| Site | a.test |\n+------+--------+\n| Type | wp     |\n+------+--------+\n", $this->stdout() );
	}

	public function test_remove_trailing_slash_and_trailingslashit() {
		$this->assertSame( '/opt/easyengine', Utils\remove_trailing_slash( '/opt/easyengine//' ) );
		$this->assertSame( 'a/', Utils\trailingslashit( 'a' ) );
		$this->assertSame( 'a/', Utils\trailingslashit( 'a\\//\\' ) );
	}

	/** Run $fn with environment variables set (null unsets), restoring them afterwards. */
	private static function with_env( array $vars, callable $fn ) {
		$saved = [];
		foreach ( $vars as $name => $value ) {
			$saved[ $name ] = getenv( $name );
			putenv( null === $value ? $name : "$name=$value" );
		}
		try {
			return $fn();
		} finally {
			foreach ( $saved as $name => $value ) {
				putenv( false === $value ? $name : "$name=$value" );
			}
		}
	}

	public function test_increment_version() {
		$this->assertSame( '1.2.3-pre', Utils\increment_version( '1.2.3-pre', 'same' ) );
		$this->assertSame( '1.2.4', Utils\increment_version( '1.2.3-pre', 'patch' ) );
		$this->assertSame( '1.3.0', Utils\increment_version( '1.2.3-pre', 'minor' ) );
		$this->assertSame( '2.0.0', Utils\increment_version( '1.2.3-pre', 'major' ) );
		$this->assertSame( '4.5.6-alpha1', Utils\increment_version( '1.2.3-pre', '4.5.6-alpha1' ) );
	}

	public function sem_ver_cases() {
		return [
			[ '0.18.0', '0.19.1', '' ],
			[ '0.19.1', '0.19.1', '' ],
			[ '0.19.2', '0.19.1', 'patch' ],
			[ '0.20.0', '0.19.1', 'minor' ],
			[ '0.20.3', '0.19.1', 'minor' ],
			[ '1.0.0', '0.19.1', 'major' ],
			[ '4.13.1', '4.13.0', 'patch' ],
			[ '4.14.0', '4.13.0', 'minor' ],
			[ '2.9.1', '3.0', '' ],
			[ '3.0.1', '3.0', 'patch' ],
			[ '3.1.1', '3.0', 'minor' ],
			[ '4.1.1', '3.0', 'major' ],
		];
	}

	/**
	 * @dataProvider sem_ver_cases
	 */
	public function test_get_named_sem_ver( $new, $original, $expected ) {
		$this->assertSame( $expected, Utils\get_named_sem_ver( $new, $original ) );
	}

	public function ssh_urls() {
		return [
			[ 'foo', [ 'host' => 'foo' ] ],
			[ 'foo.com:2222', [ 'host' => 'foo.com', 'port' => '2222' ] ],
			[ 'foo.com:2222/path/to/dir', [ 'host' => 'foo.com', 'port' => '2222', 'path' => '/path/to/dir' ] ],
			[ 'foo.com~/path/to/dir', [ 'host' => 'foo.com', 'path' => '~/path/to/dir' ] ],
			[ '~/path/to/dir', [] ],
			[ 'foo.com:~/path/to/dir', [ 'host' => 'foo.com', 'path' => '~/path/to/dir' ] ],
			[ 'foo.com:2222~/path/to/dir', [ 'host' => 'foo.com', 'port' => '2222', 'path' => '~/path/to/dir' ] ],
			[ 'ssh:bar@foo.com:~/path/to/dir', [ 'scheme' => 'ssh', 'user' => 'bar', 'host' => 'foo.com', 'path' => '~/path/to/dir' ] ],
			[ 'docker:wordpress', [ 'scheme' => 'docker', 'host' => 'wordpress' ] ],
			[ 'docker-compose:bar@wordpress:~/path/to/dir', [ 'scheme' => 'docker-compose', 'user' => 'bar', 'host' => 'wordpress', 'path' => '~/path/to/dir' ] ],
			[ 'vagrant:default', [ 'scheme' => 'vagrant', 'host' => 'default' ] ],
			[ 'vagrant:/var/www/html', [ 'host' => 'vagrant', 'path' => '/var/www/html' ] ],
			[ 'foo:bar', [] ],
		];
	}

	/**
	 * @dataProvider ssh_urls
	 */
	public function test_parse_ssh_url( $url, $expected ) {
		$bits = Utils\parse_ssh_url( $url );
		ksort( $bits );
		ksort( $expected );
		$this->assertSame( $expected, $bits );
		$components = [ PHP_URL_SCHEME => 'scheme', PHP_URL_USER => 'user', PHP_URL_HOST => 'host', PHP_URL_PORT => 'port', PHP_URL_PATH => 'path' ];
		foreach ( $components as $component => $key ) {
			$this->assertSame( isset( $expected[ $key ] ) ? $expected[ $key ] : null, Utils\parse_ssh_url( $url, $component ), $key );
		}
	}

	public function test_parse_str_to_argv() {
		$this->assertSame( [], Utils\parse_str_to_argv( '' ) );
		$this->assertSame( [ 'option', 'get', 'home' ], Utils\parse_str_to_argv( 'option get home' ) );
		$this->assertSame( [ 'core', 'download', '--path=/var/www/' ], Utils\parse_str_to_argv( 'core download --path=/var/www/' ) );
		$this->assertSame( [ 'eval', 'echo wp_get_current_user()->user_login;' ], Utils\parse_str_to_argv( 'eval "echo wp_get_current_user()->user_login;"' ) );
	}

	public function test_force_env_on_nix_systems() {
		self::with_env(
			[ 'EE_TEST_IS_WINDOWS' => '0' ],
			function () {
				$this->assertSame( '/usr/bin/env cmd', Utils\force_env_on_nix_systems( 'cmd' ) );
				$this->assertSame( '/usr/bin/env cmd', Utils\force_env_on_nix_systems( '/usr/bin/env cmd' ) );
			}
		);
		self::with_env(
			[ 'EE_TEST_IS_WINDOWS' => '1' ],
			function () {
				$this->assertSame( 'cmd', Utils\force_env_on_nix_systems( 'cmd' ) );
				$this->assertSame( 'cmd', Utils\force_env_on_nix_systems( '/usr/bin/env cmd' ) );
			}
		);
	}

	public function test_get_home_dir() {
		self::with_env(
			[ 'HOME' => '/home/user/', 'HOMEDRIVE' => 'D:', 'HOMEPATH' => '\\Windows\\User\\' ],
			function () {
				$this->assertSame( '/home/user', Utils\get_home_dir() );
				putenv( 'HOME' );
				$this->assertSame( 'D:\\Windows\\User', Utils\get_home_dir() );
				putenv( 'HOMEPATH' );
				$this->assertSame( 'D:', Utils\get_home_dir() );
			}
		);
	}

	public function test_normalize_eols_and_temp_dir() {
		$this->assertSame( "\na\ra\na\n", Utils\normalize_eols( "\r\na\ra\r\na\r\n" ) );
		$this->assertSame( '/', substr( Utils\get_temp_dir(), -1 ) );
		$this->assertDirectoryIsWritable( Utils\get_temp_dir() );
	}

	public function past_tense_verbs() {
		return [
			[ 'activate', 'activated' ],
			[ 'delete', 'deleted' ],
			[ 'install', 'installed' ],
			[ 'network activate', 'network activated' ],
			[ 'reset', 'reset' ],
			[ 'spam', 'spammed' ],
			[ 'update', 'updated' ],
			[ 'crop', 'cropped' ],
			[ 'fix', 'fixed' ],
			[ 'ah', 'ahed' ],
			[ 'show', 'showed' ],
			[ 'ski', 'skied' ],
			[ 'slay', 'slayed' ],
			// Multi-vowel verbs that double aren't handled.
			[ 'submit', 'submited' ],
			[ 'try', 'tried' ],
		];
	}

	/**
	 * @dataProvider past_tense_verbs
	 */
	public function test_past_tense_verb( $verb, $expected ) {
		$this->assertSame( $expected, Utils\past_tense_verb( $verb ) );
	}

	public function globs() {
		return [
			[ 'foo.ab1', [ 'foo.ab1' ] ],
			[ '{foo,bar}.ab1', [ 'foo.ab1', 'bar.ab1' ] ],
			[ '{foo,baz}.a{b,c}1', [ 'foo.ab1', 'baz.ab1', 'baz.ac1' ] ],
			[ '{foo,bar}.{ab1,efg1}', [ 'foo.ab1', 'foo.efg1', 'bar.ab1' ] ],
			[ '{foo,ba{r,z}}.ab1', [ 'foo.ab1', 'bar.ab1', 'baz.ab1' ] ],
			[ '{foo,bar}.{ab{1,2},efg1}', [ 'foo.ab1', 'foo.ab2', 'foo.efg1', 'bar.ab1', 'bar.ab2' ] ],
			[ '{foo,ba{r,z}}.{a{b,c}{1,2},efg{1,2}}', [ 'foo.ab1', 'foo.ab2', 'foo.efg1', 'foo.efg2', 'bar.ab1', 'bar.ab2', 'baz.ab1', 'baz.ac1', 'baz.efg2' ] ],
			// A path without glob characters is returned even if it doesn't exist.
			[ 'no_such_file', [ 'no_such_file' ] ],
		];
	}

	/**
	 * @dataProvider globs
	 */
	public function test_expand_globs_with_and_without_glob_brace( $pattern, $expected ) {
		$dir      = dirname( __DIR__ ) . '/fixtures/expand_globs/';
		$expected = array_map(
			function ( $file ) use ( $dir ) {
				return $dir . $file;
			},
			$expected
		);
		sort( $expected );
		foreach ( [ '0', '1' ] as $no_brace ) {
			$out = self::with_env(
				[ 'EE_TEST_EXPAND_GLOBS_NO_GLOB_BRACE' => $no_brace ],
				function () use ( $dir, $pattern ) {
					return Utils\expand_globs( $dir . $pattern );
				}
			);
			sort( $out );
			$this->assertSame( $expected, $out, "EE_TEST_EXPAND_GLOBS_NO_GLOB_BRACE=$no_brace" );
		}
	}

	public function batch_results() {
		return [
			[ "Success: Noun already verbed.\n", '', 1, 0, 0, null ],
			[ "Success: Nouns already verbed.\n", '', 2, 0, 0, null ],
			[ "Success: Verbed 1 of 2 nouns.\n", '', 2, 1, 0, null ],
			[ "Success: Verbed 1 of 2 nouns (1 skipped).\n", '', 2, 1, 0, 1 ],
			[ '', "Error: No nouns verbed.\n", 1, 0, 1, null ],
			[ '', "Error: No nouns verbed (2 failed, 1 skipped).\n", 3, 0, 2, 1 ],
			[ '', "Error: Only verbed 1 of 3 nouns (2 failed).\n", 3, 1, 2, 0 ],
			[ '', "Error: Only verbed 1 of 6 nouns (3 failed, 2 skipped).\n", 6, 1, 3, 2 ],
		];
	}

	/**
	 * @dataProvider batch_results
	 */
	public function test_report_batch_operation_results( $stdout, $stderr, $total, $successes, $failures, $skips ) {
		try {
			Utils\report_batch_operation_results( 'noun', 'verb', $total, $successes, $failures, $skips );
			$this->assertSame( '', $stderr, 'Expected an error' );
		} catch ( EE\ExitException $e ) {
			$this->assertNotSame( '', $stderr, 'Unexpected error' );
		}
		$this->assertSame( $stdout, $this->stdout() );
		$this->assertSame( $stderr, $this->stderr() );
	}

	public function test_get_php_binary_prefers_ee_php_used_then_ee_php() {
		$this->assertSame( EE\Utils\get_php_binary(), EE::get_php_binary() );
		self::with_env(
			[ 'EE_PHP_USED' => null, 'EE_PHP' => null ],
			function () {
				$this->assertSame( PHP_BINARY, Utils\get_php_binary() );
				putenv( 'EE_PHP=/my-php-7.3' );
				$this->assertSame( '/my-php-7.3', Utils\get_php_binary() );
				putenv( 'EE_PHP_USED=/my-php-5.3' );
				$this->assertSame( '/my-php-5.3', Utils\get_php_binary() );
			}
		);
	}

	public function win_env_commands() {
		return [
			[ 'echo', [], 'echo', [] ],
			[ 'ENV=blah echo', [], 'echo', [ 'ENV' => 'blah' ] ],
			[ 'ENV="blah blah" echo', [], 'echo', [ 'ENV' => 'blah blah' ] ],
			[ 'ENV_1="blah1 blah1" ENV_2="blah2" ENV_3=blah3 echo', [], 'echo', [ 'ENV_1' => 'blah1 blah1', 'ENV_2' => 'blah2', 'ENV_3' => 'blah3' ] ],
			[ 'ENV= echo', [], 'echo', [ 'ENV' => '' ] ],
			[ 'ENV=0 echo', [], 'echo', [ 'ENV' => '0' ] ],
			[ 'ENV=blah echo', [ 'ENV_1' => 'in1' ], 'echo', [ 'ENV_1' => 'in1', 'ENV' => 'blah' ] ],
			[ 'ENV="blah blah" echo', [ 'ENV' => 'in' ], 'echo', [ 'ENV' => 'blah blah' ] ],
			[ '1=1 echo', [], '1=1 echo', [] ],
			[ '_eNv=1 echo', [], 'echo', [ '_eNv' => '1' ] ],
			[ 'ENV=\'blah blah\' echo', [], 'blah\' echo', [ 'ENV' => '\'blah' ] ],
		];
	}

	/**
	 * @dataProvider win_env_commands
	 */
	public function test_proc_open_compat_win_env_moves_prefixes_into_env( $cmd, $env, $expected_cmd, $expected_env ) {
		$this->assertSame( $expected_cmd, Utils\_proc_open_compat_win_env( $cmd, $env ) );
		$this->assertSame( $expected_env, $env );
	}

	public function json_cases() {
		return [
			[ '42', true, false ],
			[ '42', false, true ],
			[ '"test"', true, false ],
			[ '"test"', false, true ],
			[ '{"key1":"value1","key2":"value2"}', true, true ],
			[ '["value1","value2"]', true, true ],
			[ '{bad', true, false ],
			[ '', false, false ],
		];
	}

	/**
	 * @dataProvider json_cases
	 */
	public function test_is_json( $argument, $ignore_scalars, $expected ) {
		$this->assertSame( $expected, Utils\is_json( $argument, $ignore_scalars ) );
	}

	public function test_parse_shell_arrays_decodes_only_the_named_json_arguments() {
		$this->assertSame( [ 'alpha' => '{"key":"value"}' ], Utils\parse_shell_arrays( [ 'alpha' => '{"key":"value"}' ], [] ) );
		$this->assertSame( [ 'alpha' => [ 'key' => 'value' ] ], Utils\parse_shell_arrays( [ 'alpha' => '{"key":"value"}' ], [ 'alpha' ] ) );
		$this->assertSame( [ 'alpha' => '{"key":"value"}' ], Utils\parse_shell_arrays( [ 'alpha' => '{"key":"value"}' ], [ 'beta' ] ) );
	}
}

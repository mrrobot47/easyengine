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
}

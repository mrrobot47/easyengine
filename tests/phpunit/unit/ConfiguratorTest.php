<?php

use EE\Configurator;
use EE\Tests\TestCase;

/**
 * EE\Configurator: argv splitting, runtime vs command arguments, and config.yml merging.
 */
class ConfiguratorTest extends TestCase {

	protected $reset_db = false;

	private static function configurator() {
		return new Configurator( EE_ROOT . '/php/config-spec.php' );
	}

	public function test_extract_assoc_splits_positionals_flags_and_values() {
		list( $positional, $assoc ) = Configurator::extract_assoc( [ 'foo', '--bar', '--baz=text', '--no-color', '--empty=', '--test=text--text' ] );
		$this->assertSame( [ 'foo' ], $positional );
		$this->assertSame( [ [ 'bar', true ], [ 'baz', 'text' ], [ 'color', false ], [ 'empty', '' ], [ 'test', 'text--text' ] ], $assoc );
	}

	public function test_extract_assoc_keeps_multiline_values() {
		list( , $assoc ) = Configurator::extract_assoc( [ "--command=a\nb" ] );
		$this->assertSame( [ [ 'command', "a\nb" ] ], $assoc );
	}

	public function test_extract_assoc_separates_global_and_local_arguments() {
		list( $positional, $assoc, $global, $local ) = Configurator::extract_assoc( [ '--url=foo.dev', '--path=wp', 'foo', '--bar=', '--baz=text', '--url=bar.dev' ] );
		$this->assertSame( [ 'foo' ], $positional );
		$this->assertCount( 5, $assoc );
		$this->assertSame( [ [ 'url', 'foo.dev' ], [ 'path', 'wp' ] ], $global );
		$this->assertSame( [ [ 'bar', '' ], [ 'baz', 'text' ], [ 'url', 'bar.dev' ] ], $local );
	}

	public function test_parse_args_moves_runtime_parameters_into_the_config() {
		list( $args, $assoc, $runtime ) = self::configurator()->parse_args( [ 'site', 'create', 'a.test', '--type=wp', '--skip-tty', '--debug=bootstrap', '--quiet' ] );
		$this->assertSame( [ 'site', 'create', 'a.test' ], $args );
		$this->assertSame( [ 'type' => 'wp' ], $assoc );
		$this->assertSame( [ 'skip-tty' => true, 'debug' => 'bootstrap', 'quiet' => true ], $runtime );
	}

	public function test_file_only_keys_stay_command_arguments() {
		// disabled_commands has no runtime form, so --disabled_commands is passed to the command.
		list( , $assoc, $runtime ) = self::configurator()->parse_args( [ 'site', '--disabled_commands=x' ] );
		$this->assertSame( [ 'disabled_commands' => 'x' ], $assoc );
		$this->assertSame( [], $runtime );
	}

	public function skip_tty_forms() {
		return [
			'--skip-tty'       => [ '--skip-tty', true ],
			'--no-skip-tty'    => [ '--no-skip-tty', false ],
			'--skip-tty=0'     => [ '--skip-tty=0', '0' ],
			// CORE-2 root cause: the value stays the string 'false', which is truthy, so docker_compose_exec() still adds -T.
			'--skip-tty=false' => [ '--skip-tty=false', 'false' ],
		];
	}

	/**
	 * @dataProvider skip_tty_forms
	 */
	public function test_skip_tty_runtime_values( $arg, $expected ) {
		list( , , $runtime ) = self::configurator()->parse_args( [ 'shell', 'a.test', $arg ] );
		$this->assertSame( $expected, $runtime['skip-tty'] );
	}

	public function test_strict_args_mode_only_reads_runtime_config_before_the_command() {
		putenv( 'EE_STRICT_ARGS_MODE=1' );
		try {
			list( , $assoc, $runtime ) = self::configurator()->parse_args( [ '--debug', 'site', 'list', '--quiet', '--format=json' ] );
		} finally {
			putenv( 'EE_STRICT_ARGS_MODE' );
		}
		$this->assertSame( [ 'debug' => true ], $runtime );
		$this->assertSame( [ 'quiet' => true, 'format' => 'json' ], $assoc );
	}

	public function test_defaults_come_from_the_spec() {
		list( $config, $extra ) = self::configurator()->to_array();
		$this->assertFalse( $config['skip-tty'] );
		$this->assertSame( 'auto', $config['color'] );
		$this->assertSame( [], $config['disabled_commands'] );
		$this->assertNull( $config['le-mail'] );
		$this->assertSame( [], $extra );
	}

	public function test_merge_yml_sets_known_keys_and_keeps_unknown_ones_as_extra_config() {
		$dir = $this->sandbox();
		file_put_contents( "$dir/config.yml", "le-mail: admin@example.test\nskip-tty: true\ndisabled_commands:\n  - site delete\nrclone-path: remote:backups\nno-of-backups: 3\n" );
		$configurator = self::configurator();
		$configurator->merge_yml( "$dir/config.yml" );
		list( $config, $extra ) = $configurator->to_array();
		$this->assertSame( 'admin@example.test', $config['le-mail'] );
		$this->assertTrue( $config['skip-tty'] );
		$this->assertSame( [ 'site delete' ], $config['disabled_commands'] );
		$this->assertSame( [ 'rclone-path' => 'remote:backups', 'no-of-backups' => 3 ], $extra );
	}

	public function test_merge_yml_follows_inherit_and_reads_aliases() {
		$dir = $this->sandbox();
		file_put_contents( "$dir/base.yml", "env: staging\nwp-mail: base@example.test\n" );
		file_put_contents( "$dir/config.yml", "_:\n  inherit: $dir/base.yml\nwp-mail: child@example.test\n'@prod':\n  ssh: user@host\n  path: /var/www\n'@local':\n  path: sites/a\n'@both':\n  - '@prod'\n  - '@local'\n" );
		$configurator = self::configurator();
		$configurator->merge_yml( "$dir/config.yml" );
		list( $config ) = $configurator->to_array();
		$this->assertSame( 'staging', $config['env'] );
		$this->assertSame( 'child@example.test', $config['wp-mail'] );
		$this->assertSame(
			[
				'@prod'  => [ 'path' => '/var/www', 'ssh' => 'user@host' ],
				// A local alias path is made absolute against the config file's directory.
				'@local' => [ 'path' => "$dir/sites/a" ],
				'@both'  => [ '@prod', '@local' ],
			],
			$configurator->get_aliases()
		);
	}

	public function test_runtime_alias_env_overrides_file_aliases_and_drops_unknown_keys() {
		putenv( 'EE_RUNTIME_ALIAS=' . json_encode( [ '@dev' => [ 'path' => '/srv', 'bogus' => 1 ], 'notalias' => [ 'path' => '/x' ] ] ) );
		try {
			$aliases = self::configurator()->get_aliases();
		} finally {
			putenv( 'EE_RUNTIME_ALIAS' );
		}
		$this->assertSame( [ '@dev' => [ 'path' => '/srv' ] ], $aliases );
	}

	public function test_merge_array_only_takes_runtime_keys() {
		$configurator = self::configurator();
		$configurator->merge_array( [ 'skip-tty' => 'false', 'disabled_commands' => [ 'x' ], 'unknown' => 1 ] );
		list( $config, $extra ) = $configurator->to_array();
		$this->assertSame( 'false', $config['skip-tty'] );
		$this->assertSame( [], $config['disabled_commands'] );
		$this->assertSame( [], $extra );
	}
}

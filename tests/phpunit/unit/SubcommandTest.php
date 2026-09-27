<?php

use EE\Dispatcher\CommandFactory;
use EE\Tests\TestCase;

require_once EE_ROOT . '/php/class-ee-command.php';

/**
 * EE\Dispatcher\Subcommand argument validation, on commands built by CommandFactory the way EE::add_command() does.
 */
class SubcommandTest extends TestCase {

	protected $reset_db = false;

	protected function setUp(): void {
		parent::setUp();
		PHPUnit_Probe_Site_Command::$calls = [];
	}

	/** @return \EE\Dispatcher\Subcommand */
	private static function subcommand( $name ) {
		$composite = CommandFactory::create( 'probe', 'PHPUnit_Probe_Site_Command', EE::get_root_command() );

		return $composite->get_subcommands()[ $name ];
	}

	/** Invoke the subcommand and return the args its method received. */
	private static function invoke( $name, array $args, array $assoc_args = [] ) {
		self::subcommand( $name )->invoke( $args, $assoc_args, [] );

		return end( PHPUnit_Probe_Site_Command::$calls );
	}

	public function test_factory_registers_public_methods_by_name_or_subcommand_tag() {
		$composite = CommandFactory::create( 'probe', 'PHPUnit_Probe_Site_Command', EE::get_root_command() );
		$names     = array_keys( $composite->get_subcommands() );
		sort( $names );
		// Not: @ignorecommand, protected, static and magic methods.
		$this->assertSame( [ 'create', 'delete-site', 'mode', 'publish' ], $names );
		$this->assertSame( 'Creates a probe site.', $composite->get_subcommands()['create']->get_shortdesc() );
	}

	public function test_alias_resolves_to_the_subcommand() {
		$composite = CommandFactory::create( 'probe', 'PHPUnit_Probe_Site_Command', EE::get_root_command() );
		$args      = [ 'add', 'a.test' ];
		$this->assertSame( 'create', $composite->find_subcommand( $args )->get_name() );
		$this->assertSame( [ 'a.test' ], $args );
		$args = [ 'nope' ];
		$this->assertFalse( $composite->find_subcommand( $args ) );
	}

	public function test_synopsis_is_extracted_from_the_options_section() {
		$this->assertSame( '<site-name> [--type=<type>] [--proxy-cache=<on-or-off>] [--php=<php-version>] [--cache] [--title=<title>]', self::subcommand( 'create' )->get_synopsis() );
		$this->assertSame( 'usage: ee probe create <site-name> [--type=<type>] [--proxy-cache=<on-or-off>] [--php=<php-version>] [--cache] [--title=<title>]', self::subcommand( 'create' )->get_usage( 'usage: ' ) );
	}

	public function test_defaults_are_filled_in_for_missing_parameters() {
		list( $args, $assoc ) = self::invoke( 'create', [ 'a.test' ] );
		$this->assertSame( [ 'a.test' ], $args );
		$this->assertSame( 'html', $assoc['type'] );
		$this->assertSame( 8.4, $assoc['php'] );
		// WPT-3: the `off` default arrives as boolean false.
		$this->assertFalse( $assoc['proxy-cache'] );
		$this->assertArrayNotHasKey( 'cache', $assoc );
	}

	public function allowed_values() {
		return [
			'type'        => [ [ 'type' => 'wp' ] ],
			'php 7.4'     => [ [ 'php' => '7.4' ] ],
			'php 8.0'     => [ [ 'php' => '8.0' ] ],
			'php 8.4'     => [ [ 'php' => '8.4' ] ],
			'flag'        => [ [ 'cache' => true ] ],
			'free text'   => [ [ 'title' => "it's; \$(x)" ] ],
		];
	}

	/**
	 * @dataProvider allowed_values
	 */
	public function test_allowed_values_pass_through_unchanged( array $assoc ) {
		list( , $received ) = self::invoke( 'create', [ 'a.test' ], $assoc );
		foreach ( $assoc as $key => $value ) {
			$this->assertSame( $value, $received[ $key ] );
		}
	}

	public function rejected_values() {
		return [
			'type'   => [ 'type', 'ruby' ],
			'php'    => [ 'php', '9.9' ],
			'php 5'  => [ 'php', '5.6' ],
			'php ab' => [ 'php', 'latest' ],
		];
	}

	/**
	 * @dataProvider rejected_values
	 */
	public function test_values_outside_the_options_are_rejected( $key, $value ) {
		$this->assert_ee_error(
			function () use ( $key, $value ) {
				self::invoke( 'create', [ 'a.test' ], [ $key => $value ] );
			},
			"Invalid value specified for '$key'"
		);
		$this->assertSame( [], PHPUnit_Probe_Site_Command::$calls );
	}

	public function loose_php_values() {
		return [ [ '8' ], [ '8.40' ], [ '08.4' ], [ '8e0' ], [ '7.40' ] ];
	}

	/**
	 * PHPT-11/WPT-4: `in_array()` is loose against the float options, so `--php=8` passes and the compose file gets `easyengine/php8:`.
	 *
	 * @group known-bug
	 * @group PHPT-11
	 * @group WPT-4
	 * @dataProvider loose_php_values
	 */
	public function test_php_version_must_match_an_option_exactly( $value ) {
		$this->assert_ee_error(
			function () use ( $value ) {
				self::invoke( 'create', [ 'a.test' ], [ 'php' => $value ] );
			},
			"Invalid value specified for 'php'"
		);
	}

	/**
	 * WPT-3: the on/off options load as booleans, so `--proxy-cache=maybe` passes validation (any non-empty string == true).
	 *
	 * @group known-bug
	 * @group WPT-3
	 */
	public function test_proxy_cache_rejects_values_other_than_on_and_off() {
		$this->assert_ee_error(
			function () {
				self::invoke( 'create', [ 'a.test' ], [ 'proxy-cache' => 'maybe' ] );
			},
			"Invalid value specified for 'proxy-cache'"
		);
	}

	public function test_positional_options_are_validated() {
		list( $args ) = self::invoke( 'mode', [ 'enable' ] );
		$this->assertSame( [ 'enable' ], $args );
		$this->assert_ee_error(
			function () {
				self::invoke( 'mode', [ 'explode' ] );
			},
			'Invalid value specified for positional arg.'
		);
	}

	public function test_repeating_positional_checks_every_value() {
		list( $args ) = self::invoke( 'publish', [ 'a.test', 'b.test' ], [ 'channel' => 'stable' ] );
		$this->assertSame( [ 'a.test', 'b.test' ], $args );
	}

	public function test_missing_required_parameter_is_fatal() {
		$this->assert_ee_error(
			function () {
				self::invoke( 'publish', [ 'a.test' ] );
			},
			'missing --channel parameter'
		);
	}

	public function test_too_many_positionals_are_rejected() {
		$this->assert_ee_error(
			function () {
				self::invoke( 'create', [ 'a.test', 'b.test' ] );
			},
			'Too many positional arguments: b.test'
		);
	}

	public function test_unknown_parameter_gets_a_suggestion() {
		$this->assert_ee_error(
			function () {
				self::invoke( 'create', [ 'a.test' ], [ 'tittle' => 'x' ] );
			},
			"unknown --tittle parameter\nDid you mean '--title'?"
		);
	}

	public function test_value_parameter_given_as_a_flag_warns_and_is_dropped() {
		list( , $assoc ) = self::invoke( 'create', [ 'a.test' ], [ 'title' => true ] );
		$this->assertArrayNotHasKey( 'title', $assoc );
		$this->assertStringContainsString( 'Warning: --title parameter needs a value', $this->stderr() );
	}

	public function test_extra_args_bypass_the_unknown_parameter_check() {
		self::subcommand( 'create' )->invoke( [ 'a.test' ], [], [ 'custom' => 'x' ] );
		list( $args, $assoc ) = end( PHPUnit_Probe_Site_Command::$calls );
		$this->assertSame( 'x', $assoc['custom'] );
		$this->assertSame( [ 'a.test' ], $args );
	}
}

/**
 * Probe command group.
 */
class PHPUnit_Probe_Site_Command extends EE_Command {

	public static $calls = [];

	/**
	 * Creates a probe site.
	 *
	 * ## OPTIONS
	 *
	 * <site-name>
	 * : Name of website.
	 *
	 * [--type=<type>]
	 * : Type of the site.
	 * ---
	 * default: html
	 * options:
	 *   - html
	 *   - php
	 *   - wp
	 * ---
	 *
	 * [--proxy-cache=<on-or-off>]
	 * : Proxy cache.
	 * ---
	 * default: off
	 * options:
	 *  - on
	 *  - off
	 * ---
	 *
	 * [--php=<php-version>]
	 * : PHP version.
	 * ---
	 * default: 8.4
	 * options:
	 *  - 7.4
	 *  - 8.0
	 *  - 8.4
	 * ---
	 *
	 * [--cache]
	 * : Redis cache.
	 *
	 * [--title=<title>]
	 * : Title.
	 *
	 * @alias add
	 */
	public function create( $args, $assoc_args ) {
		self::$calls[] = [ $args, $assoc_args ];
	}

	/**
	 * Switches a mode.
	 *
	 * ## OPTIONS
	 *
	 * <mode>
	 * : Mode.
	 * ---
	 * options:
	 *   - enable
	 *   - disable
	 * ---
	 */
	public function mode( $args, $assoc_args ) {
		self::$calls[] = [ $args, $assoc_args ];
	}

	/**
	 * Publishes sites.
	 *
	 * ## OPTIONS
	 *
	 * <site-name>...
	 * : Sites.
	 *
	 * --channel=<channel>
	 * : Channel.
	 */
	public function publish( $args, $assoc_args ) {
		self::$calls[] = [ $args, $assoc_args ];
	}

	/**
	 * Deletes a probe site.
	 *
	 * @subcommand delete-site
	 */
	public function delete_it( $args, $assoc_args ) {
	}

	/**
	 * Not a command.
	 *
	 * @ignorecommand
	 */
	public function helper() {
	}

	protected function hidden() {
	}

	public static function util() {
	}

	public function __call( $name, $arguments ) {
	}
}

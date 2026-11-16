<?php

use EE\ExitException;
use EE\Tests\TestCase;

require_once EE_ROOT . '/php/class-ee-command.php';
require_once EE_ROOT . '/php/commands/src/CLI_Command.php';

/**
 * `ee cli has-command` (CLI_Command::has_command()) against probe commands registered with EE::add_command().
 */
class CliCommandTest extends TestCase {

	protected $reset_db = false;

	public static function setUpBeforeClass(): void {
		parent::setUpBeforeClass();
		EE::add_command( 'phpunit-group', 'PHPUnit_Cli_Probe_Command' );
		EE::add_command( 'phpunit-leaf', 'PHPUnit_Cli_Probe_Leaf' );
	}

	/** @return int The exit code has_command() halts with. */
	private static function has_command( $command ) {
		try {
			( new CLI_Command() )->has_command( [ $command ], [] );
		} catch ( ExitException $e ) {
			return $e->getCode();
		}

		return -1;
	}

	public function registered_commands() {
		return [
			[ 'phpunit-group' ],
			[ 'phpunit-group run' ],
			[ 'phpunit-leaf' ],
			[ 'cli' ],
		];
	}

	/**
	 * @dataProvider registered_commands
	 */
	public function test_registered_commands_exit_0( $command ) {
		$this->assertSame( 0, self::has_command( $command ) );
	}

	public function test_unknown_commands_exit_1() {
		$this->assertSame( 1, self::has_command( 'phpunit-nope' ) );
		$this->assertSame( 1, self::has_command( 'phpunit-group nope' ) );
	}

	public function extra_words() {
		return [
			[ 'phpunit-group run extra' ],
			[ 'phpunit-leaf anything' ],
		];
	}

	/**
	 * CORE-6: the lookup stops at the first leaf and ignores the remaining words, so a command that doesn't exist reports 0.
	 *
	 * @group known-bug
	 * @group CORE-6
	 * @dataProvider extra_words
	 */
	public function test_words_after_a_leaf_command_exit_1( $command ) {
		$this->assertSame( 1, self::has_command( $command ) );
	}
}

/**
 * Probe group.
 */
class PHPUnit_Cli_Probe_Command extends EE_Command {
	/**
	 * Runs.
	 */
	public function run( $args, $assoc_args ) {
	}
}

/**
 * Probe leaf routed through __invoke, like `ee site`.
 */
class PHPUnit_Cli_Probe_Leaf extends EE_Command {
	public function __invoke( $args, $assoc_args ) {
	}
}

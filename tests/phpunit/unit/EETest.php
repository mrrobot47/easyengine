<?php

use EE\ProcessRun;
use EE\Tests\TestCase;

/**
 * The EE static API: process helpers, config access, errors and value printing.
 */
class EETest extends TestCase {

	protected $reset_db = false;

	public function test_exec_returns_success_and_can_echo_stdout() {
		$this->runner->on( '/^false$/', '', 1 );
		$this->runner->on( '/^echo hi$/', "hi\n" );
		$this->assertTrue( EE::exec( 'true' ) );
		$this->assertFalse( EE::exec( 'false' ) );
		$this->expectOutputString( "hi\n" );
		$this->assertTrue( EE::exec( 'echo hi', true ) );
	}

	public function test_launch_returns_the_run_or_the_exit_code() {
		$this->runner->on( '/^docker ps$/', "x\n", 2, 'err' );
		$run = EE::launch( 'docker ps', false, true, [], [ 'A' => '1' ], '/tmp' );
		$this->assertInstanceOf( ProcessRun::class, $run );
		$this->assertSame( [ "x\n", 'err', 2 ], [ $run->stdout, $run->stderr, $run->return_code ] );
		$this->assertSame( [ 'command' => 'docker ps', 'cwd' => '/tmp', 'env' => [ 'A' => '1' ] ], $this->runner->calls[0] );
		$this->assertSame( 2, EE::launch( 'docker ps', false, false ) );
	}

	public function test_debug_log_obfuscates_secrets() {
		$this->set_config( [ 'debug' => true ] );
		EE::exec( "mysql -p's3cret' -e 'select 1'", false, false, [ 's3cret' ] );
		$this->assertStringContainsString( "COMMAND: mysql -p'******' -e 'select 1'", $this->stderr() );
		$this->assertStringNotContainsString( 's3cret', $this->stderr() );
		$this->assertSame( [ "mysql -p's3cret' -e 'select 1'" ], $this->runner->commands() );
	}

	public function test_get_config_warns_on_unknown_keys() {
		$this->set_config( [ 'le-mail' => 'a@example.test' ] );
		$this->assertSame( 'a@example.test', EE::get_config( 'le-mail' ) );
		$this->assertNull( EE::get_config( 'nope' ) );
		$this->assertStringContainsString( "Warning: Unknown config option 'nope'.", $this->stderr() );
	}

	public function test_error_exit_codes() {
		EE::error( 'soft', false );
		$this->assertSame( "Error: soft\n", $this->stderr() );
		$this->assert_ee_error(
			function () {
				EE::error( 'hard', 3 );
			},
			'Error: hard',
			3
		);
	}

	public function test_print_value_formats() {
		$this->expectOutputString( "{\"a\":1}\n---\na: 1\n\nplain\n" );
		EE::print_value( [ 'a' => 1 ], [ 'format' => 'json' ] );
		EE::print_value( [ 'a' => 1 ], [ 'format' => 'yaml' ] );
		EE::print_value( 'plain' );
	}

	public function test_get_php_binary_is_the_utils_one() {
		$this->assertSame( EE\Utils\get_php_binary(), EE::get_php_binary() );
	}
}

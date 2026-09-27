<?php

use EE\Tests\TestCase;

/**
 * The console loggers (EE\Loggers\Regular, Quiet, Execution).
 */
class LoggingTest extends TestCase {

	protected $reset_db = false;

	public function test_regular_and_quiet_loggers_print_debug_with_the_elapsed_time() {
		$this->expectOutputRegex( '/^Debug: This is a test\. \(\d+(\.\d+)?s\)\nDebug: This is a test\. \(\d+(\.\d+)?s\)\n$/' );
		( new PHPUnit_Debug_Regular_Logger( false ) )->debug( 'This is a test.' );
		( new PHPUnit_Debug_Quiet_Logger() )->debug( 'This is a test.' );
	}

	public function test_quiet_logger_drops_info_and_success() {
		$this->expectOutputString( '' );
		$logger = new PHPUnit_Debug_Quiet_Logger();
		$logger->info( 'info' );
		$logger->success( 'success' );
	}

	public function test_messages_are_not_printf_formatted() {
		$this->expectOutputString( "Success: foo%20bar %s\n" );
		( new PHPUnit_Debug_Regular_Logger( false ) )->success( 'foo%20bar %s' );
	}

	public function test_execution_logger_captures_stdout_and_stderr() {
		$this->set_config( [ 'debug' => true ] );
		$logger = new EE\Loggers\Execution();

		$logger->info( 'info' );
		$logger->success( 'success' );
		$logger->warning( 'warning' );
		$logger->error( 'error' );
		$logger->debug( 'debug', 'group' );
		$logger->error_multi_line( [ 'line11', 'line12' ] );

		$this->assertSame( "info\nSuccess: success\n", $logger->stdout );
		$this->assertMatchesRegularExpression( '/^Warning: warning\nError: error\nDebug \(group\): debug \([0-9.]+s\)\nError:\nline11\nline12\n---------\n\n$/', $logger->stderr );
	}

	public function test_debug_group_filter() {
		$this->set_config( [ 'debug' => 'migration' ] );
		$logger = new EE\Loggers\Execution();
		$logger->debug( 'shown', 'migration' );
		$logger->debug( 'hidden', 'bootstrap' );
		$logger->debug( 'hidden too' );
		$this->assertMatchesRegularExpression( '/^Debug: shown \([0-9.]+s\)\n$/', $logger->stderr );

		$this->set_config( [ 'debug' => false ] );
		$logger->stderr = '';
		$logger->debug( 'off', 'migration' );
		$this->assertSame( '', $logger->stderr );
	}

	public function test_execution_logger_captures_echo_while_buffering() {
		$logger = new EE\Loggers\Execution();
		$logger->ob_start();
		echo 'echo';
		$logger->info( 'info' );
		print "print\n";
		$logger->error( 'error' );
		echo 'echo2';
		$logger->ob_end();

		$this->assertSame( "echoinfo\nprint\necho2", $logger->stdout );
		$this->assertSame( "Error: error\n", $logger->stderr );
	}
}

class PHPUnit_Debug_Regular_Logger extends EE\Loggers\Regular {

	protected function get_runner() {
		return (object) [ 'config' => [ 'debug' => true ] ];
	}

	protected function write( $handle, $str ) {
		echo $str;
	}
}

class PHPUnit_Debug_Quiet_Logger extends EE\Loggers\Quiet {

	protected function get_runner() {
		return (object) [ 'config' => [ 'debug' => true ] ];
	}

	protected function write( $handle, $str ) {
		echo $str;
	}
}

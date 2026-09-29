<?php

use EE\Process;
use EE\ProcessRun;
use EE\Tests\TestCase;
use EE\Utils;

/**
 * EE\Process with real (tiny) child processes: the one place the unit suite runs real commands.
 */
class ProcessTest extends TestCase {

	protected $reset_db = false;

	private static function php( $code ) {
		return escapeshellarg( Utils\get_php_binary() ) . ' -r ' . escapeshellarg( $code );
	}

	public function test_run_captures_stdout_stderr_and_exit_code() {
		$run = Process::create( self::php( 'echo "out"; fwrite(STDERR, "err"); exit(3);' ) )->run();
		$this->assertInstanceOf( ProcessRun::class, $run );
		$this->assertSame( [ 'out', 'err', 3 ], [ $run->stdout, $run->stderr, $run->return_code ] );
	}

	public function test_run_uses_cwd() {
		$dir = realpath( $this->sandbox() );
		$this->assertSame( $dir, Process::create( self::php( 'echo getcwd();' ), $dir )->run()->stdout );
	}

	public function env_cases() {
		return [
			'none'                 => [ '', [], [], '' ],
			'prefix'               => [ 'ENV=blah', [], [ 'ENV' ], 'blah' ],
			'quoted prefix'        => [ 'ENV="blah blah"', [], [ 'ENV' ], 'blah blah' ],
			'prefixes and env'     => [ 'ENV_1="blah1 blah1" ENV_2="blah2" ENV_3=blah3', [ 'ENV' => 'in' ], [ 'ENV', 'ENV_1', 'ENV_2', 'ENV_3' ], 'inblah1 blah1blah2blah3' ],
			'env and prefix'       => [ 'ENV=blah', [ 'ENV_1' => 'in1', 'ENV_2' => 'in2' ], [ 'ENV_1', 'ENV_2', 'ENV' ], 'in1in2blah' ],
		];
	}

	/**
	 * @dataProvider env_cases
	 */
	public function test_run_passes_env_and_command_prefixes( $prefix, $env, $vars, $expected ) {
		$code = vsprintf( str_repeat( 'echo getenv( \'%s\' );', count( $vars ) ), $vars );
		$this->assertSame( $expected, Process::create( trim( $prefix . ' ' . self::php( $code ) ), null, $env )->run()->stdout );
	}

	public function test_run_check_stderr_throws_on_stderr_output_or_failure() {
		$this->assertSame( 'ok', Process::create( self::php( 'echo "ok";' ) )->run_check_stderr()->stdout );
		foreach ( [ 'fwrite(STDERR, "warn");', 'exit(1);' ] as $code ) {
			try {
				Process::create( self::php( $code ) )->run_check_stderr();
				$this->fail( "No exception for: $code" );
			} catch ( RuntimeException $e ) {
				$this->assertStringContainsString( 'exit status: ', $e->getMessage() );
			}
		}
	}

	public function test_process_run_to_string() {
		$run = new ProcessRun( [ 'command' => 'ls', 'stdout' => 'a', 'stderr' => 'b', 'cwd' => '/tmp', 'run_time' => 0.5, 'return_code' => 2 ] );
		$this->assertSame( "$ ls\na\nbcwd: /tmp\nrun time: 0.5\nexit status: 2", (string) $run );
	}

	/**
	 * MIG-12 (fixed in v4.13.1): run() reads stdout to EOF before stderr, so a child writing more than a pipe buffer (64 KiB) to stderr first deadlocks.
	 * Runs Process in a child PHP that is killed after 5 s.
	 *
	 * @group MIG-12
	 */
	public function test_run_does_not_deadlock_on_large_stderr() {
		$script = $this->sandbox() . '/run.php';
		file_put_contents(
			$script,
			'<?php require ' . var_export( EE_ROOT . '/php/utils.php', true ) . '; require ' . var_export( EE_ROOT . '/php/EE/ProcessRun.php', true ) . '; require ' . var_export( EE_ROOT . '/php/EE/Process.php', true ) . ";\n"
			. 'define( "EE_ROOT", ' . var_export( EE_ROOT, true ) . " );\n"
			. '$r = EE\Process::create( ' . var_export( self::php( 'fwrite(STDERR, str_repeat("x", 200000)); echo "done";' ), true ) . " )->run();\n"
			. 'echo strlen( $r->stderr ), " ", $r->stdout;'
		);

		$proc     = proc_open( [ Utils\get_php_binary(), $script ], [ 1 => [ 'pipe', 'w' ], 2 => [ 'pipe', 'w' ] ], $pipes );
		$deadline = microtime( true ) + 5;
		while ( proc_get_status( $proc )['running'] && microtime( true ) < $deadline ) {
			usleep( 20000 );
		}
		$finished = ! proc_get_status( $proc )['running'];
		if ( ! $finished ) {
			proc_terminate( $proc, 9 );
		}
		$out = stream_get_contents( $pipes[1] ) . stream_get_contents( $pipes[2] );
		proc_close( $proc );

		$this->assertTrue( $finished, 'Process::run() still blocked after 5 s' );
		$this->assertSame( '200000 done', $out );
	}
}

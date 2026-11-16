<?php

namespace EE\Tests;

use EE\ProcessRun;

/**
 * Stands in for real processes behind EE::launch() / EE::exec() (see EE::set_process_runner()).
 *
 * Records every command and answers from regex rules; unmatched commands succeed with empty output.
 */
class FakeProcessRunner {

	/** @var array[] Each: command, cwd, env. */
	public $calls = [];

	private $rules = [];

	/**
	 * Answer commands matching $pattern. The most recently added matching rule wins.
	 *
	 * @param string          $pattern     PCRE pattern matched against the full command.
	 * @param string|callable $stdout      Output, or callable( $command ) returning a ProcessRun or [ stdout, return_code, stderr ].
	 * @param int             $return_code Exit code.
	 * @param string          $stderr      Error output.
	 * @param int|null        $times       Stop matching after this many uses; null = unlimited.
	 *
	 * @return $this
	 */
	public function on( $pattern, $stdout = '', $return_code = 0, $stderr = '', $times = null ) {
		$this->rules[] = compact( 'pattern', 'stdout', 'return_code', 'stderr', 'times' );

		return $this;
	}

	public function __invoke( $command, $cwd = null, $env = null ) {
		$this->calls[] = compact( 'command', 'cwd', 'env' );

		for ( $i = count( $this->rules ) - 1; $i >= 0; $i-- ) {
			$rule = &$this->rules[ $i ];
			if ( 0 === $rule['times'] || ! preg_match( $rule['pattern'], $command ) ) {
				continue;
			}
			if ( null !== $rule['times'] ) {
				$rule['times']--;
			}
			if ( is_callable( $rule['stdout'] ) ) {
				$result = call_user_func( $rule['stdout'], $command );
				if ( $result instanceof ProcessRun ) {
					return $result;
				}
				list( $stdout, $return_code, $stderr ) = array_pad( (array) $result, 3, '' );

				return self::result( $command, $stdout, (int) $return_code, $stderr, $cwd, $env );
			}

			return self::result( $command, $rule['stdout'], $rule['return_code'], $rule['stderr'], $cwd, $env );
		}

		return self::result( $command, '', 0, '', $cwd, $env );
	}

	/** @return string[] Commands in the order they ran. */
	public function commands() {
		return array_column( $this->calls, 'command' );
	}

	/** @return string[] Commands matching $pattern. */
	public function matching( $pattern ) {
		return array_values( preg_grep( $pattern, $this->commands() ) );
	}

	public function reset() {
		$this->calls = [];
		$this->rules = [];
	}

	public static function result( $command, $stdout = '', $return_code = 0, $stderr = '', $cwd = null, $env = null ) {
		return new ProcessRun(
			[
				'command'     => $command,
				'stdout'      => $stdout,
				'stderr'      => $stderr,
				'return_code' => $return_code,
				'cwd'         => $cwd,
				'env'         => $env,
				'run_time'    => 0,
			]
		);
	}

	/** Default runner between tests: fail loudly instead of running a real command. */
	public static function deny( $command ) {
		throw new \LogicException( "Unit tests must not run real processes; extend EE\\Tests\\TestCase to get a fake runner. Command: $command" );
	}
}

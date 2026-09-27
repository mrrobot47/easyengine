<?php

namespace EE\Tests;

/**
 * Checks recorded command strings for shell injection by running them in a shell that can't reach any program.
 *
 * Each payload creates a marker file with the `:` builtin and a redirection, which only happens when the shell
 * interprets the payload; PATH points nowhere, so the rest of the command (docker, rm, ...) can't run.
 */
class ShellProbe {

	/**
	 * @param string $marker File name, relative to the cwd of run(), that a successful injection creates. Letters only, so
	 *                       sinks that lowercase the value or strip dots and dashes keep it intact.
	 *
	 * @return string[] Payload by name.
	 */
	public static function payloads( $marker ) {
		return [
			'command substitution' => 'a$(: >' . $marker . ')b',
			'backticks'            => 'a`: >' . $marker . '`b',
			'semicolon'            => 'a;: >' . $marker . ';b',
			'pipe'                 => 'a|: >' . $marker . '|b',
			'newline'              => "a\n: >$marker\nb",
			'single-quote break'   => "a'; : >$marker; '",
			'double-quote break'   => 'a"; : >' . $marker . '; "',
		];
	}

	/**
	 * Run $command with /bin/sh in $cwd, without PATH, stdin or output, for at most $timeout seconds.
	 *
	 * @return int|null Exit code, or null when it was killed on timeout.
	 */
	public static function run( $command, $cwd, $timeout = 5 ) {
		$spec = [
			0 => [ 'file', '/dev/null', 'r' ],
			1 => [ 'file', '/dev/null', 'w' ],
			2 => [ 'file', '/dev/null', 'w' ],
		];
		$proc = proc_open( [ '/bin/sh', '-c', $command ], $spec, $pipes, $cwd, [ 'PATH' => '/nonexistent' ] );
		if ( ! is_resource( $proc ) ) {
			throw new \RuntimeException( 'Could not start /bin/sh.' );
		}
		$deadline = microtime( true ) + $timeout;
		do {
			$status = proc_get_status( $proc );
			if ( ! $status['running'] ) {
				proc_close( $proc );

				return $status['exitcode'];
			}
			usleep( 10000 );
		} while ( microtime( true ) < $deadline );
		proc_terminate( $proc, 9 );
		proc_close( $proc );

		return null;
	}
}

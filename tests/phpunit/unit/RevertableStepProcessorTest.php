<?php

use EE\RevertableStepProcessor;
use EE\Tests\TestCase;

/**
 * EE\RevertableStepProcessor: steps run in order; a failure reverts what ran, newest first.
 */
class RevertableStepProcessorTest extends TestCase {

	protected $reset_db = false;

	private $log = [];

	/** A step callable that logs "$name($args)" and throws when $fail is set. */
	private function step( $name, $fail = false ) {
		return function ( ...$args ) use ( $name, $fail ) {
			$this->log[] = $name . ( $args ? '(' . implode( ',', $args ) . ')' : '' );
			if ( $fail ) {
				throw new Exception( "$name failed" );
			}
		};
	}

	public function test_all_steps_run_in_order_with_their_params() {
		$rsp = ( new RevertableStepProcessor() )
			->add_step( 'one', $this->step( 'up1' ), $this->step( 'down1' ), [ 'a', 'b' ] )
			->add_step( 'two', $this->step( 'up2' ), $this->step( 'down2' ) );

		$this->assertTrue( $rsp->execute() );
		$this->assertSame( [ 'up1(a,b)', 'up2' ], $this->log );
		$this->assertSame( '', $this->stderr() );
	}

	public function test_failure_reverts_the_failed_step_and_the_completed_ones_in_reverse() {
		$rsp = ( new RevertableStepProcessor() )
			->add_step( 'one', $this->step( 'up1' ), $this->step( 'down1' ), null, [ 'x' ] )
			->add_step( 'two', $this->step( 'up2' ), null )
			->add_step( 'three', $this->step( 'up3', true ), $this->step( 'down3' ) )
			->add_step( 'four', $this->step( 'up4' ), $this->step( 'down4' ) );

		$this->assertFalse( $rsp->execute() );
		// The failed step's own down runs too (it may have half-done its work); step two has none.
		$this->assertSame( [ 'up1', 'up2', 'up3', 'down3', 'down1(x)' ], $this->log );
		$this->assertStringContainsString( 'Error: Error while executing three. closure: up3 failed', $this->stderr() );
	}

	public function test_error_names_a_string_callable_and_can_be_silenced() {
		$rsp = ( new RevertableStepProcessor() )->add_step( 'pull', 'PHPUnit_Rsp_Steps::fail' );
		$this->assertFalse( $rsp->execute() );
		$this->assertStringContainsString( 'Error while executing pull. PHPUnit_Rsp_Steps::fail: pull failed', $this->stderr() );

		self::logger()->stderr = '';
		$rsp = ( new RevertableStepProcessor() )->add_step( 'pull', 'PHPUnit_Rsp_Steps::fail' );
		$this->assertFalse( $rsp->execute( false ) );
		$this->assertStringNotContainsString( 'Error', $this->stderr() );
	}

	public function test_a_failing_down_step_does_not_stop_the_rollback() {
		$rsp = ( new RevertableStepProcessor() )
			->add_step( 'one', $this->step( 'up1' ), $this->step( 'down1' ) )
			->add_step( 'two', $this->step( 'up2' ), $this->step( 'down2', true ) )
			->add_step( 'three', $this->step( 'up3', true ) );

		$this->assertFalse( $rsp->execute( false ) );
		$this->assertSame( [ 'up1', 'up2', 'up3', 'down2', 'down1' ], $this->log );
	}

	public function test_execute_again_runs_only_the_steps_added_since() {
		$rsp = ( new RevertableStepProcessor() )->add_step( 'one', $this->step( 'up1' ), $this->step( 'down1' ) );
		$this->assertTrue( $rsp->execute() );
		$rsp->add_step( 'two', $this->step( 'up2' ), $this->step( 'down2' ) );
		$this->assertTrue( $rsp->execute() );
		$this->assertSame( [ 'up1', 'up2' ], $this->log );

		// A manual rollback reverts everything that ran.
		$rsp->rollback();
		$this->assertSame( [ 'up1', 'up2', 'down2', 'down1' ], $this->log );
	}

	/**
	 * CORE-18 (new): after a failed execute() the index is left at -1 and the steps are cleared, so the next execute() on the same processor slices from -1 and runs only the last new step.
	 *
	 * @group known-bug
	 * @group CORE-18
	 */
	public function test_processor_is_reusable_after_a_failure() {
		$rsp = ( new RevertableStepProcessor() )->add_step( 'bad', $this->step( 'bad', true ) );
		$this->assertFalse( $rsp->execute( false ) );

		$this->log = [];
		$rsp->add_step( 'one', $this->step( 'up1' ) )->add_step( 'two', $this->step( 'up2' ) );
		$this->assertTrue( $rsp->execute() );
		$this->assertSame( [ 'up1', 'up2' ], $this->log );
	}
}

class PHPUnit_Rsp_Steps {
	public static function fail() {
		throw new Exception( 'pull failed' );
	}
}

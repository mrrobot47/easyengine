<?php

use EE\SynopsisParser;
use EE\SynopsisValidator;
use EE\Tests\TestCase;

/**
 * EE\SynopsisParser (tokens to specs and back) and EE\SynopsisValidator (argument checks against a synopsis).
 */
class SynopsisTest extends TestCase {

	protected $reset_db = false;

	/** @return array[] Each token's [ type, optional ] (plus repeating/value flags where set). */
	private static function shape( $synopsis ) {
		return array_map(
			function ( $param ) {
				$shape = [ $param['type'] ];
				if ( isset( $param['optional'] ) ) {
					$shape[] = $param['optional'];
				}
				if ( ! empty( $param['repeating'] ) ) {
					$shape[] = 'repeating';
				}
				if ( ! empty( $param['value']['optional'] ) ) {
					$shape[] = 'value-optional';
				}

				return $shape;
			},
			SynopsisParser::parse( $synopsis )
		);
	}

	public function synopses() {
		return [
			'empty'                   => [ ' ', [] ],
			'positionals'             => [ '<plugin|zip> [<bar>]', [ [ 'positional', false ], [ 'positional', true ] ] ],
			'optional flag'           => [ '[--foo]', [ [ 'flag', true ] ] ],
			'mandatory flag'          => [ '--foo', [ [ 'unknown', false ] ] ],
			'generic'                 => [ '--<field>=<value> [--<field>=<value>] --<field>[=<value>] [--<field>[=<value>]]', [ [ 'generic', false ], [ 'generic', true ], [ 'unknown', false ], [ 'unknown', true ] ] ],
			'assoc'                   => [ '--foo=<value> [--bar=<value>] [--bar[=<value>]]', [ [ 'assoc', false ], [ 'assoc', true ], [ 'assoc', true, 'value-optional' ] ] ],
			// Only an optional parameter may have an optional value.
			'invalid assoc'           => [ '--bar[=<value>] --bar=[<value>] --count=100', [ [ 'unknown', false, 'value-optional' ], [ 'unknown' ], [ 'unknown' ] ] ],
			'repeating'               => [ '<positional>... [--<field>=<value>...]', [ [ 'positional', false, 'repeating' ], [ 'generic', true, 'repeating' ] ] ],
			'value characters'        => [ '--capitals=<VALUE> --hyphen=<val-ue> --disallowed=<wrong:char>', [ [ 'assoc', false ], [ 'assoc', false ], [ 'unknown' ] ] ],
			'negatable flag'          => [ '[--[no-]color]', [ [ 'flag', true ] ] ],
		];
	}

	/**
	 * @dataProvider synopses
	 */
	public function test_parse_classifies_tokens( $synopsis, $expected ) {
		$this->assertSame( $expected, self::shape( $synopsis ) );
	}

	public function test_parse_keeps_names_and_tokens() {
		$spec = SynopsisParser::parse( '<site-name> [--php=<php-version>] [--[no-]color]' );
		$this->assertSame( [ 'site-name', 'php', 'color' ], array_column( $spec, 'name' ) );
		$this->assertSame( 'php-version', $spec[1]['value']['name'] );
		$this->assertSame( [ '<site-name>', '[--php=<php-version>]', '[--[no-]color]' ], array_column( $spec, 'token' ) );
	}

	public function test_render_orders_positional_assoc_generic_flag() {
		$spec = [
			[ 'name' => 'force', 'type' => 'flag', 'optional' => true ],
			[ 'name' => 'meal', 'type' => 'assoc' ],
			[ 'name' => 'message', 'type' => 'positional' ],
			[ 'name' => 'secrets', 'type' => 'positional', 'optional' => true, 'repeating' => true ],
			[ 'name' => 'snack', 'type' => 'assoc', 'optional' => true, 'value' => [ 'name' => 'food' ] ],
			[ 'type' => 'generic', 'optional' => true ],
			[ 'type' => 'assoc' ],
		];
		$this->assertSame( '<message> [<secrets>...] --meal=<meal> [--snack=<food>] [--<field>=<value>] [--force]', SynopsisParser::render( $spec ) );
		$this->assertSame( '', SynopsisParser::render( 'not an array' ) );
	}

	public function round_trips() {
		return [
			[ '<positional> --assoc=<assoc> --<field>=<value> [--flag]' ],
			[ '<p1ositional> --a2ssoc=<assoc> --<field>=<value> [--f3lag]' ],
		];
	}

	/**
	 * @dataProvider round_trips
	 */
	public function test_parse_then_render_round_trips( $synopsis ) {
		$this->assertSame( $synopsis, SynopsisParser::render( SynopsisParser::parse( $synopsis ) ) );
	}

	public function test_enough_and_unknown_positionals() {
		$validator = new SynopsisValidator( '<foo> <bar> [<baz>]' );
		$this->assertFalse( $validator->enough_positionals( [] ) );
		$this->assertFalse( $validator->enough_positionals( [ 1 ] ) );
		$this->assertTrue( $validator->enough_positionals( [ 1, 2 ] ) );
		$this->assertSame( [ 4 ], $validator->unknown_positionals( [ 1, 2, 3, 4 ] ) );
		$this->assertSame( [], $validator->unknown_positionals( [ 1, 2, 3 ] ) );
	}

	public function test_repeating_positional_accepts_any_count() {
		$validator = new SynopsisValidator( '<foo> [<bar>...]' );
		$this->assertFalse( $validator->enough_positionals( [] ) );
		$this->assertTrue( $validator->enough_positionals( [ 1 ] ) );
		$this->assertSame( [], $validator->unknown_positionals( [ 1, 2, 3 ] ) );
	}

	public function test_unknown_assoc() {
		$this->assertSame( [ 'foo', 'bar' ], ( new SynopsisValidator( '' ) )->unknown_assoc( [ 'foo' => true, 'bar' => false ] ) );

		$validator = new SynopsisValidator( '--type=<type> [--brand=<brand>] [--flag]' );
		$this->assertSame( [], $validator->unknown_assoc( [ 'type' => 'analog', 'brand' => true, 'flag' => true ] ) );
		$this->assertSame( [ 3 => 'another' ], $validator->unknown_assoc( [ 'type' => 'analog', 'brand' => true, 'flag' => true, 'another' => true ] ) );
		// A generic --<field>=<value> accepts anything.
		$this->assertSame( [], ( new SynopsisValidator( '[--<field>=<value>]' ) )->unknown_assoc( [ 'any' => 1 ] ) );
	}

	public function test_validate_assoc_reports_missing_and_valueless_parameters() {
		$validator = new SynopsisValidator( '--type=<type> [--brand=<brand>] [--flag]' );
		list( $errors, $to_unset ) = $validator->validate_assoc( [ 'brand' => true, 'flag' => true ] );
		$this->assertSame( [ 'type' => 'missing --type parameter' ], $errors['fatal'] );
		$this->assertSame( [ 'brand' => '--brand parameter needs a value' ], $errors['warning'] );
		$this->assertSame( [ 'brand' ], $to_unset );

		list( $errors, $to_unset ) = $validator->validate_assoc( [ 'type' => true ] );
		$this->assertSame( [ 'type' => '--type parameter needs a value' ], $errors['fatal'] );
		$this->assertSame( [ 'type' ], $to_unset );
	}

	public function test_optional_value_may_be_given_as_a_flag() {
		list( $errors, $to_unset ) = ( new SynopsisValidator( '[--network[=<id>]]' ) )->validate_assoc( [ 'network' => true ] );
		$this->assertSame( [ 'fatal' => [], 'warning' => [] ], $errors );
		$this->assertSame( [], $to_unset );
	}

	public function test_get_unknown_lists_invalid_tokens() {
		$this->assertSame( [ '--foo', '--count=100' ], ( new SynopsisValidator( '<site> --foo --count=100 [--ok]' ) )->get_unknown() );
	}
}

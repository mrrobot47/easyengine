<?php

use EE\Tests\TestCase;
use EE\Tests\TestDB;

/**
 * EE_DB query builder (php/class-ee-db.php) on the fixture SQLite DB.
 */
class DbTest extends TestCase {

	protected function setUp(): void {
		parent::setUp();
		foreach ( [ 'a.test' => 'wp', 'b.test' => 'php', 'c.test' => 'wp', 'd.test' => 'html' ] as $url => $type ) {
			$this->insert_site( [ 'site_url' => $url, 'site_type' => $type ] );
		}
	}

	private static function urls( array $rows ) {
		return array_column( $rows, 'site_url' );
	}

	public function where_conditions() {
		return [
			'implicit ='  => [ [ 'site_type', 'wp' ], [ 'a.test', 'c.test' ] ],
			'='           => [ [ 'site_type', '=', 'php' ], [ 'b.test' ] ],
			'!='          => [ [ 'site_type', '!=', 'wp' ], [ 'b.test', 'd.test' ] ],
			'<>'          => [ [ 'site_type', '<>', 'wp' ], [ 'b.test', 'd.test' ] ],
			'>'           => [ [ 'id', '>', 2 ], [ 'c.test', 'd.test' ] ],
			'<='          => [ [ 'id', '<=', 2 ], [ 'a.test', 'b.test' ] ],
			'like'        => [ [ 'site_url', 'like', '%c.%' ], [ 'c.test' ] ],
			'LIKE'        => [ [ 'site_url', 'LIKE', 'd%' ], [ 'd.test' ] ],
			'int 0 value' => [ [ 'site_enabled', 0 ], [] ],
		];
	}

	/**
	 * @dataProvider where_conditions
	 */
	public function test_where_operators( array $condition, array $expected ) {
		$this->assertSame( $expected, self::urls( EE::db()->table( 'sites' )->where( ...$condition )->all() ) );
	}

	public function test_where_with_an_assoc_array_or_a_list_of_conditions_ands_them() {
		$this->assertSame( [ 'c.test' ], self::urls( EE::db()->table( 'sites' )->where( [ 'site_type' => 'wp', 'id' => 3 ] )->all() ) );
		$this->assertSame( [ 'c.test' ], self::urls( EE::db()->table( 'sites' )->where( [ [ 'site_type', 'wp' ], [ 'id', '>', 1 ] ] )->all() ) );
	}

	public function hostile_values() {
		return [
			[ "' OR '1'='1" ],
			[ "a.test' --" ],
			[ "x'); DROP TABLE sites; --" ],
			[ '%' ],
		];
	}

	/**
	 * @dataProvider hostile_values
	 */
	public function test_bound_values_stay_data( $value ) {
		$this->assertSame( [], EE::db()->table( 'sites' )->where( 'site_url', $value )->all() );
		EE::db()->table( 'sites' )->where( 'site_url', 'a.test' )->update( [ 'db_password' => $value ] );
		$this->insert_site( [ 'site_url' => $value ] );

		$this->assertSame( $value, EE::db()->table( 'sites' )->where( 'site_url', 'a.test' )->first()['db_password'] );
		$this->assertSame( [ $value ], self::urls( EE::db()->table( 'sites' )->where( 'site_url', '=', $value )->all() ) );
		$this->assertCount( 5, TestDB::rows( 'sites' ) );
	}

	public function invalid_conditions() {
		return [
			'operator'      => [ [ 'site_url', 'glob', 'a*' ], 'Where clause operator should be in one of following' ],
			'column type'   => [ [ 1, 'a' ], 'Where clause column must be of type string' ],
			'null value'    => [ [ 'site_url', null ], 'Where clause value must be set' ],
			'array value'   => [ [ 'site_url', '=', [ 'a' ] ], 'Where clause operator and value must be string' ],
			'too many'      => [ [ [ [ 'a', '=', 'b', 'c' ] ] ], 'Where clause array must non empty' ],
		];
	}

	/**
	 * @dataProvider invalid_conditions
	 */
	public function test_invalid_where_conditions_throw( array $condition, $message ) {
		$this->expectException( Exception::class );
		$this->expectExceptionMessage( $message );
		EE::db()->table( 'sites' )->where( ...$condition );
	}

	public function test_select_first_limit_and_offset() {
		$this->assertSame( [ 'site_url' => 'a.test', 'site_type' => 'wp' ], EE::db()->table( 'sites' )->select( 'site_url', 'site_type' )->first() );
		$this->assertSame( [ 'b.test', 'c.test' ], self::urls( EE::db()->table( 'sites' )->select( 'site_url' )->limit( 2 )->offset( 1 )->get() ) );
		$this->assertFalse( EE::db()->table( 'sites' )->where( 'site_url', 'nope' )->first() );
	}

	public function test_insert_returns_the_new_row_id() {
		$this->assertSame( '1', (string) EE::db()->table( 'options' )->insert( [ 'key' => 'k', 'value' => 'v' ] ) );
		$this->assertSame( [ [ 'key' => 'k', 'value' => 'v' ] ], TestDB::rows( 'options' ) );
	}

	public function test_update_and_delete_only_touch_matching_rows() {
		$this->assertTrue( EE::db()->table( 'sites' )->where( 'site_type', 'wp' )->update( [ 'php_version' => '8.4', 'admin_tools' => 1 ] ) );
		$this->assertSame( [ '8.4', null, '8.4', null ], array_column( TestDB::rows( 'sites' ), 'php_version' ) );

		$this->assertTrue( EE::db()->table( 'sites' )->where( 'id', '>', 2 )->delete() );
		$this->assertSame( [ 'a.test', 'b.test' ], self::urls( TestDB::rows( 'sites' ) ) );
		$this->assertFalse( EE::db()->table( 'sites' )->where( 'id', 1 )->update( [] ) );
	}

	public function test_writes_need_exactly_one_table() {
		foreach ( [
			'Insert: No table specified'       => function () { EE::db()->insert( [ 'a' => 1 ] ); },
			'Insert: Multiple table specified' => function () { EE::db()->table( 'sites', 'options' )->insert( [ 'a' => 1 ] ); },
			'Update: Multiple table specified' => function () { EE::db()->table( 'sites', 'options' )->where( 'id', 1 )->update( [ 'a' => 1 ] ); },
			'Delete: No table specified'       => function () { EE::db()->where( 'id', 1 )->delete(); },
		] as $message => $fn ) {
			try {
				$fn();
				$this->fail( "No exception: $message" );
			} catch ( Exception $e ) {
				$this->assertSame( $message, $e->getMessage() );
			}
		}
	}

	/**
	 * CORE-16 (new): the "No where clause specified" guards never fire (`$this->where` is always a non-empty array), so a where-less delete() empties the table.
	 *
	 * @group known-bug
	 * @group CORE-16
	 */
	public function test_delete_without_where_is_refused() {
		try {
			@EE::db()->table( 'sites' )->delete();
		} catch ( Exception $e ) {
			$this->assertSame( 'Delete: No where clause specified', $e->getMessage() );
		}
		$this->assertCount( 4, TestDB::rows( 'sites' ) );
	}

	/**
	 * CORE-17 (new): `in` is an allowed where() operator, but it renders `site_type in ?`, which is an SQL syntax error.
	 *
	 * @group known-bug
	 * @group CORE-17
	 */
	public function test_where_in_operator() {
		$this->assertSame( [ 'b.test' ], self::urls( EE::db()->table( 'sites' )->where( 'site_type', 'in', 'php' )->all() ) );
	}
}

<?php

use EE\Model\Migration;
use EE\Model\Option;
use EE\Tests\TestCase;
use EE\Tests\TestDB;

/**
 * EE\Model\Base CRUD on the fixture DB, and the Option and Migration models.
 */
class ModelTest extends TestCase {

	public function test_create_then_find_by_primary_key() {
		$id = PHPUnit_Probe_Site::create( [ 'site_url' => 'a.test', 'site_type' => 'wp', 'site_fs_path' => '/x/a.test', 'site_container_fs_path' => '/var/www/htdocs' ] );
		$this->assertSame( '1', (string) $id );

		$site = PHPUnit_Probe_Site::find( '1' );
		$this->assertInstanceOf( PHPUnit_Probe_Site::class, $site );
		$this->assertSame( 'a.test', $site->site_url );
		$this->assertSame( 'off', $site->proxy_cache );
		$this->assertNull( $site->db_name );
	}

	public function test_find_selects_columns_and_returns_false_when_missing() {
		$this->insert_site( [ 'site_url' => 'a.test', 'site_type' => 'php' ] );
		$site = PHPUnit_Probe_Site::find( '1', [ 'site_url', 'site_type' ] );
		$this->assertFalse( isset( $site->id ) );
		$this->assertSame( 'php', $site->site_type );
		$this->assertFalse( PHPUnit_Probe_Site::find( '99' ) );
	}

	public function test_all_and_where() {
		$this->insert_site( [ 'site_url' => 'a.test', 'site_type' => 'wp', 'site_enabled' => 1 ] );
		$this->insert_site( [ 'site_url' => 'b.test', 'site_type' => 'php', 'site_enabled' => 0 ] );
		$this->insert_site( [ 'site_url' => 'c.test', 'site_type' => 'wp', 'site_enabled' => 1 ] );

		$this->assertSame( [ 'a.test', 'b.test', 'c.test' ], array_column( PHPUnit_Probe_Site::all(), 'site_url' ) );
		$this->assertSame( [ 'a.test', 'c.test' ], array_column( PHPUnit_Probe_Site::where( 'site_type', 'wp' ), 'site_url' ) );
		// Booleans are compared as 0/1.
		$this->assertSame( [ 'b.test' ], array_column( PHPUnit_Probe_Site::where( 'site_enabled', false ), 'site_url' ) );
		$this->assertSame( [ 'c.test' ], array_column( PHPUnit_Probe_Site::where( [ 'site_type' => 'wp', 'site_url' => 'c.test' ] ), 'site_url' ) );
		$this->assertSame( [], PHPUnit_Probe_Site::where( 'site_url', 'nope.test' ) );
	}

	public function test_save_writes_changed_fields_casts_booleans_and_bumps_modified_on() {
		$this->insert_site( [ 'site_url' => 'a.test', 'modified_on' => '2000-01-01 00:00:00' ] );
		$this->insert_site( [ 'site_url' => 'b.test', 'modified_on' => '2000-01-01 00:00:00' ] );
		$site               = PHPUnit_Probe_Site::find( '1' );
		$site->php_version  = '8.4';
		$site->admin_tools  = true;
		$this->assertTrue( $site->save() );

		$rows = TestDB::rows( 'sites' );
		// PDO SQLite returns integers as strings before PHP 8.1.
		$this->assertSame( [ '8.4', '1' ], [ $rows[0]['php_version'], (string) $rows[0]['admin_tools'] ] );
		$this->assertNotSame( '2000-01-01 00:00:00', $rows[0]['modified_on'] );
		$this->assertSame( [ null, '0', '2000-01-01 00:00:00' ], [ $rows[1]['php_version'], (string) $rows[1]['admin_tools'], $rows[1]['modified_on'] ] );
	}

	public function test_static_update_and_delete() {
		$this->insert_site( [ 'site_url' => 'a.test', 'site_type' => 'wp' ] );
		$this->insert_site( [ 'site_url' => 'b.test', 'site_type' => 'php' ] );

		$this->assertTrue( PHPUnit_Probe_Site::update( [ 'site_type' => 'php' ], [ 'php_version' => '7.4' ] ) );
		$this->assertSame( [ null, '7.4' ], array_column( TestDB::rows( 'sites' ), 'php_version' ) );

		$this->assertTrue( PHPUnit_Probe_Site::find( '1' )->delete() );
		$this->assertSame( [ 'b.test' ], array_column( TestDB::rows( 'sites' ), 'site_url' ) );
	}

	public function test_magic_accessors() {
		$model = new PHPUnit_Probe_Site( [ 'site_url' => 'a.test', 'site_ssl' => null ] );
		$this->assertTrue( isset( $model->site_url ) );
		$this->assertFalse( isset( $model->nope ) );
		$this->assertNull( $model->site_ssl );
		$model->site_ssl = 'le';
		$this->assertSame( 'le', $model->site_ssl );
		unset( $model->site_ssl );
		$this->expectExceptionMessage( 'Unable to find variable: site_ssl' );
		$model->site_ssl;
	}

	/**
	 * CORE-15 (new): find_or_fail()/find_or_error() pass their `string $column = null` to find()'s `array $columns`, so every call is a TypeError (neither has a caller today).
	 *
	 * @group known-bug
	 * @group CORE-15
	 */
	public function test_find_or_fail_with_one_argument() {
		Option::set( 'version', '4.13.0' );
		$this->assertSame( '4.13.0', Option::find_or_fail( 'version' )->value );
		$this->assert_ee_error(
			function () {
				Option::find_or_error( 'nope' );
			},
			'Unable to find EE\Model\Base : with primary key: key and value: nope'
		);
		$this->expectExceptionMessage( 'Unable to find' );
		Option::find_or_fail( 'nope' );
	}

	public function test_option_set_creates_then_updates() {
		$this->assertFalse( Option::get( 'version' ) );
		Option::set( 'version', '4.12.0' );
		Option::set( 'easyengine/nginx', 'v4.11.0' );
		Option::set( 'version', '4.13.0' );
		$this->assertSame( '4.13.0', Option::get( 'version' ) );
		$this->assertSame( [ [ 'key' => 'version', 'value' => '4.13.0' ], [ 'key' => 'easyengine/nginx', 'value' => 'v4.11.0' ] ], TestDB::rows( 'options' ) );
	}

	public function test_migration_names_come_from_the_migrations_table() {
		$this->assertSame( [], Migration::get_migrations() );
		Migration::create( [ 'migration' => '20180101_easyengine_a.php', 'type' => 'db', 'timestamp' => '2018-01-01 00:00:00' ] );
		Migration::create( [ 'migration' => '20190101_site-command_b.php', 'type' => 'container', 'timestamp' => '2019-01-01 00:00:00' ] );
		$this->assertSame( [ '20180101_easyengine_a.php', '20190101_site-command_b.php' ], Migration::get_migrations() );
		$this->assertSame( [ '20190101_site-command_b.php' ], array_column( Migration::where( 'type', 'container' ), 'migration' ) );
	}
}

class PHPUnit_Probe_Site extends EE\Model\Base {
	protected static $table                  = 'sites';
	protected static $needs_update_timestamp = true;
}

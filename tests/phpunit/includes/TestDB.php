<?php

namespace EE\Tests;

/**
 * The EE SQLite database of a unit test: a fresh file at DB with the schema the DB migrations create.
 */
class TestDB {

	/**
	 * Drop the database and recreate it; EE_DB then creates `migrations` and `options` itself.
	 *
	 * @param bool $with_schema Also create the package tables (sites, site_meta, cron, auth_*) from fixtures/schema.sql.
	 */
	public static function reset( $with_schema = true ) {
		TestCase::set_static( 'EE_DB', 'pdo', null );
		if ( file_exists( DB ) ) {
			unlink( DB );
		}
		new \EE_DB();
		if ( $with_schema ) {
			self::pdo()->exec( file_get_contents( __DIR__ . '/../fixtures/schema.sql' ) );
		}
	}

	/** @return \PDO The connection EE_DB uses. */
	public static function pdo() {
		new \EE_DB();

		return TestCase::get_static( 'EE_DB', 'pdo' );
	}

	/** @return array[] Rows of $table, ordered by rowid. */
	public static function rows( $table ) {
		return self::pdo()->query( "SELECT * FROM $table ORDER BY rowid" )->fetchAll( \PDO::FETCH_ASSOC );
	}

	/** @return string[] Column names of $table. */
	public static function columns( $table ) {
		return array_column( self::pdo()->query( "PRAGMA table_info($table)" )->fetchAll( \PDO::FETCH_ASSOC ), 'name' );
	}

	/** @return string[] User tables, sorted. */
	public static function tables() {
		return self::pdo()->query( "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name" )->fetchAll( \PDO::FETCH_COLUMN );
	}
}

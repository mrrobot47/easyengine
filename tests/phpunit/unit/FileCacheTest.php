<?php

use EE\FileCache;
use EE\Tests\TestCase;

/**
 * EE\FileCache (backs the update-check timestamp in Runner): keys, TTL and size limits.
 */
class FileCacheTest extends TestCase {

	protected $reset_db = false;

	public function test_root_gets_one_trailing_slash() {
		$dir = $this->sandbox() . '/cache';
		foreach ( [ $dir, "$dir/", "$dir\\" ] as $given ) {
			$this->assertSame( "$dir/", ( new FileCache( $given, 60, 32 ) )->get_root() );
		}
		$this->assertDirectoryExists( $dir );
	}

	public function test_an_uncreatable_root_disables_the_cache_with_a_warning() {
		$file = $this->sandbox() . '/file';
		touch( $file );
		$cache = new FileCache( "$file/cache", 60, 32 );
		$this->assertFalse( $cache->is_enabled() );
		$this->assertMatchesRegularExpression( "/^Warning: Failed to create directory '.+': mkdir\(\): Not a directory\.$/m", $this->stderr() );
		$this->assertFalse( $cache->write( 'k', 'v' ) );
		$this->assertFalse( $cache->has( 'k' ) );
	}

	public function test_ensure_dir_exists_warns_when_a_file_is_in_the_way() {
		$dir   = $this->sandbox();
		$cache = new FileCache( $dir, 60, 32 );
		$this->assertTrue( self::call_private( $cache, 'ensure_dir_exists', "$dir/test1" ) );
		$this->assertTrue( self::call_private( $cache, 'ensure_dir_exists', "$dir/test1" ) );
		file_put_contents( "$dir/test2", '' );
		$this->assertFalse( self::call_private( $cache, 'ensure_dir_exists', "$dir/test2" ) );
		$this->assertMatchesRegularExpression( "/^Warning: Failed to create directory '.+': mkdir\(\): File exists\.$/", $this->stderr() );
	}

	public function test_write_read_import_export_remove() {
		$dir   = $this->sandbox();
		$cache = new FileCache( "$dir/cache", 0, 0 );
		$this->assertTrue( $cache->write( 'ee-update-check', '1700000000' ) );
		$this->assertSame( '1700000000', $cache->read( 'ee-update-check' ) );
		$this->assertSame( "$dir/cache/ee-update-check", $cache->has( 'ee-update-check' ) );

		file_put_contents( "$dir/src.phar", 'phar' );
		$this->assertTrue( $cache->import( 'phar/ee-4.13.0.phar', "$dir/src.phar" ) );
		$this->assertTrue( $cache->export( 'phar/ee-4.13.0.phar', "$dir/out.phar" ) );
		$this->assertSame( 'phar', file_get_contents( "$dir/out.phar" ) );

		$this->assertTrue( $cache->remove( 'ee-update-check' ) );
		$this->assertFalse( $cache->remove( 'ee-update-check' ) );
		$this->assertFalse( $cache->read( 'ee-update-check' ) );
	}

	public function keys() {
		return [
			'plain'          => [ 'ee-update-check', 'ee-update-check' ],
			'nested'         => [ 'phar/ee.phar', 'phar/ee.phar' ],
			'backslashes'    => [ 'a\\b', 'a/b' ],
			'illegal chars'  => [ 'a b$c', 'a-b-c' ],
			'url'            => [ 'https://github.com:443/EasyEngine/ee.phar?x=1', 'misc/https-github.com-443/EasyEngine-ee.phar-x-1' ],
		];
	}

	/**
	 * @dataProvider keys
	 */
	public function test_keys_map_to_whitelisted_relative_paths( $key, $expected ) {
		$this->assertSame( $expected, self::call_private( new FileCache( $this->sandbox(), 0, 0 ), 'validate_key', $key ) );
	}

	public function test_expired_entries_are_misses_and_removed_at_the_global_ttl() {
		$dir   = $this->sandbox();
		$cache = new FileCache( $dir, 60, 0 );
		$cache->write( 'old', 'x' );
		touch( "$dir/old", time() - 120 );

		// A shorter per-call TTL misses without deleting; the global TTL deletes.
		$this->assertFalse( $cache->has( 'old', 30 ) );
		$this->assertFileExists( "$dir/old" );
		$this->assertFalse( $cache->has( 'old' ) );
		$this->assertFileDoesNotExist( "$dir/old" );
	}

	public function test_clean_drops_expired_files_then_the_oldest_over_the_size_limit() {
		$dir   = $this->sandbox();
		$cache = new FileCache( $dir, 3600, 10 );
		foreach ( [ 'expired' => 7200, 'older' => 60, 'newer' => 30 ] as $key => $age ) {
			$cache->write( $key, '123456' );
			touch( "$dir/$key", time() - $age, time() - $age );
		}
		$this->assertTrue( $cache->clean() );
		$this->assertSame( [ 'newer' ], array_values( array_diff( scandir( $dir ), [ '.', '..' ] ) ) );
	}
}

<?php

use EE\Extractor;
use EE\Tests\TestCase;

/**
 * EE\Extractor (zip/tar.gz extraction and recursive copy/delete; shipped, no EE caller today).
 */
class ExtractorTest extends TestCase {

	protected $reset_db = false;

	const TREE = [
		'index1.php',
		'license2.php',
		'wp-admin/',
		'wp-admin/about3.php',
		'wp-admin/includes/',
		'wp-admin/includes/file4.php',
		'wp-admin/widgets5.php',
		'wp-config6.php',
		'wp-includes/',
		'wp-includes/file7.php',
		'xmlrpc8.php',
	];

	/** @return string[] [ temp dir, src dir holding wordpress/ ] */
	private function tree() {
		$temp = $this->sandbox();
		$wp   = "$temp/src/wordpress";
		mkdir( $wp, 0755, true );
		foreach ( self::TREE as $entry ) {
			if ( '/' === substr( $entry, -1 ) ) {
				mkdir( "$wp/$entry" );
			} else {
				file_put_contents( "$wp/$entry", $entry );
			}
		}

		return [ $temp, "$temp/src" ];
	}

	private static function scan( $dir, $prefix = '' ) {
		$out = [];
		foreach ( array_diff( scandir( $dir ), [ '.', '..' ] ) as $file ) {
			$rel = $prefix ? "$prefix/$file" : $file;
			if ( is_dir( "$dir/$file" ) ) {
				$out[] = "$rel/";
				$out   = array_merge( $out, self::scan( "$dir/$file", $rel ) );
			} else {
				$out[] = $rel;
			}
		}

		return $out;
	}

	public function test_rmdir_removes_a_tree() {
		list( $temp, $src ) = $this->tree();
		Extractor::rmdir( "$src/wordpress" );
		$this->assertDirectoryDoesNotExist( "$src/wordpress" );
		$this->assertDirectoryExists( $src );
	}

	public function test_rmdir_of_a_missing_dir_throws() {
		$this->expectExceptionMessage( 'no-such-dir' );
		Extractor::rmdir( 'no-such-dir' );
	}

	public function test_copy_overwrite_files_copies_the_tree_and_overwrites() {
		list( $temp, $src ) = $this->tree();
		mkdir( "$temp/dest" );
		file_put_contents( "$temp/dest/index1.php", 'old' );

		Extractor::copy_overwrite_files( "$src/wordpress", "$temp/dest" );
		$this->assertSame( self::TREE, self::scan( "$temp/dest" ) );
		$this->assertSame( 'index1.php', file_get_contents( "$temp/dest/index1.php" ) );
		$this->assertSame( '', $this->stderr() );
	}

	public function test_copy_overwrite_files_of_a_missing_source_throws() {
		$this->expectExceptionMessage( 'no-such-dir' );
		Extractor::copy_overwrite_files( 'no-such-dir', $this->sandbox() . '/dest' );
	}

	/**
	 * @requires extension zip
	 */
	public function test_extract_zip_strips_the_top_directory() {
		list( $temp, $src ) = $this->tree();
		$zip = new ZipArchive();
		$this->assertTrue( $zip->open( "$temp/test.zip", ZipArchive::CREATE ) );
		foreach ( self::scan( $src ) as $entry ) {
			'/' === substr( $entry, -1 ) ? $zip->addEmptyDir( $entry ) : $zip->addFile( "$src/$entry", $entry );
		}
		$zip->close();

		Extractor::extract( "$temp/test.zip", "$temp/dest" );
		$this->assertSame( self::TREE, self::scan( "$temp/dest" ) );
		$this->assertSame( '', $this->stderr() );
		$this->assertDirectoryDoesNotExist( "$temp/test" );
	}

	public function test_extract_tarball_strips_the_top_directory() {
		list( $temp, $src ) = $this->tree();
		$tar = new PharData( "$temp/test.tar" );
		$tar->buildFromDirectory( $src );
		$tar->compress( Phar::GZ );
		unset( $tar );

		Extractor::extract( "$temp/test.tar.gz", "$temp/dest" );
		$this->assertSame( self::TREE, self::scan( "$temp/dest" ) );
		$this->assertSame( '', $this->stderr() );
	}

	public function test_unreadable_tarball_falls_back_to_tar_and_reports_its_error() {
		$dest = $this->sandbox();
		$this->runner->on( '/^tar xz /', '', 2, "tar: no-such-tar.tar.gz: Cannot open: No such file or directory\ntar: Error is not recoverable" );
		try {
			Extractor::extract( 'no-such-tar.tar.gz', $dest );
			$this->fail( 'No exception' );
		} catch ( Exception $e ) {
			$this->assertSame( "Failed to execute `tar xz --strip-components=1 --directory='$dest' -f 'no-such-tar.tar.gz'`: tar: no-such-tar.tar.gz: Cannot open: No such file or directory (2).", $e->getMessage() );
		}
		$this->assertStringStartsWith( 'Warning: PharData failed', $this->stderr() );
		$this->assertStringContainsString( 'no-such-tar', $this->stderr() );
	}

	public function test_zip_without_the_zip_extension_says_so() {
		if ( class_exists( 'ZipArchive' ) ) {
			$this->markTestSkipped( 'The zip extension is loaded.' );
		}
		$this->expectExceptionMessage( 'Extracting a zip file requires ZipArchive.' );
		Extractor::extract( 'a.zip', 'dest-dir' );
	}

	/**
	 * @requires extension zip
	 */
	public function test_bad_zip_errors_name_the_file() {
		try {
			Extractor::extract( 'no-such-zip.zip', 'dest-dir' );
			$this->fail( 'No exception' );
		} catch ( Exception $e ) {
			$this->assertSame( "ZipArchive failed to unzip 'no-such-zip.zip': No such file (9).", $e->getMessage() );
		}
		// Depending on libzip, an empty file is rejected or opens as an empty archive; either way the error names it.
		$empty = $this->sandbox() . '/zero-zip.zip';
		touch( $empty );
		try {
			Extractor::extract( $empty, 'dest-dir' );
			$this->fail( 'No exception' );
		} catch ( Exception $e ) {
			$this->assertStringContainsString( 'zero-zip', $e->getMessage() );
		}
		$this->assertSame( '', $this->stderr() );
	}

	public function test_unsupported_archive_type() {
		$this->expectExceptionMessage( "Extraction only supported for '.zip' and '.tar.gz' file types." );
		Extractor::extract( 'not-supported.tar.xz', 'dest-dir' );
	}

	/**
	 * @requires extension zip
	 */
	public function test_zip_error_message() {
		$this->assertSame( 'Not a zip archive (19)', Extractor::zip_error_msg( ZipArchive::ER_NOZIP ) );
		$this->assertSame( 999, Extractor::zip_error_msg( 999 ) );
	}

	public function test_tar_error_message() {
		$this->assertSame( 'first line (2)', Extractor::tar_error_msg( (object) [ 'stderr' => " first line \nsecond", 'return_code' => 2 ] ) );
		$this->assertSame( 2, Extractor::tar_error_msg( (object) [ 'stderr' => '', 'return_code' => 2 ] ) );
	}
}

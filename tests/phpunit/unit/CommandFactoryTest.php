<?php

use EE\Dispatcher\CommandFactory;
use EE\Tests\TestCase;

require_once EE_ROOT . '/php/class-ee-command.php';

/**
 * CommandFactory doc comment lookup: the source-reading fallback used when opcache drops comments (ported from the WP-CLI suite).
 */
class CommandFactoryTest extends TestCase {

	protected $reset_db = false;

	const FIXTURES = __DIR__ . '/../fixtures/commandfactory';

	public function doc_comment_sources() {
		return [
			[ '', false ],
			[ '*/', false ],
			[ '/*/  ', false ],
			[ '/**/', false ],
			[ '/***/ */', false ],
			[ '/***/', '/***/' ],
			[ "\n /**\n  \n  \t\n  */ \t\n \n ", "/**\n  \n  \t\n  */" ],
			[ "\r\n /**\r\n  \r\n  \t\r\n  */ \t\r\n \r\n ", "/**\r\n  \r\n  \t\r\n  */" ],
			[ '/**/ /***/ /***/', '/***/' ],
			[ 'asdfasdf/** /** */', '/** /** */' ],
			[ '*//** /** */', '/** /** */' ],
			[ '/** *//** /** */', '/** /** */' ],
			[ '*//** */ /** /** */', '/** /** */' ],
			[ '*//** *//** /** /** */', '/** /** /** */' ],
			[ '/** */class qwer', '/** */' ],
			[ '/**1*/class qwer{}/**2*/class asdf', '/**2*/' ],
			[ "/** */class qwer {}\nclass asdf", false ],
			[ "/** */class qwer {}\r\nclass asdf", false ],
			[ '/** */function qwer', '/** */' ],
			[ '/** */function qwer( $function ) {}', '/** */' ],
			[ '/**1*/function qwer() {}/**2*/function asdf()', '/**2*/' ],
			[ "/** */function qwer() {}\nfunction asdf()", false ],
			[ "/** */function qwer() {}\r\nfunction asdf()", false ],
			[ '/** */function qwer() {}function asdf()', false ],
			[ '/** */function qwer() {};function asdf( $function )', false ],
		];
	}

	/**
	 * @dataProvider doc_comment_sources
	 */
	public function test_extract_last_doc_comment( $content, $expected ) {
		$this->assertSame( $expected, self::call_private( CommandFactory::class, 'extract_last_doc_comment', $content ) );
	}

	public function line_endings() {
		return [
			'LF'   => [ '' ],
			'CRLF' => [ '-win' ],
		];
	}

	/**
	 * The fixtures put `*\/`, `function` and `class` in awkward places; the source fallback must agree with Reflection.
	 *
	 * @dataProvider line_endings
	 */
	public function test_doc_comment_read_from_the_source_matches_reflection( $suffix ) {
		$class_suffix = $suffix ? '_Win' : '';
		require_once self::FIXTURES . "/doc_comment-class$suffix.php";
		require self::FIXTURES . "/doc_comment-function$suffix.php";
		$func_3 = $suffix ? $commandfactorytests_get_doc_comment_func_3_win : $commandfactorytests_get_doc_comment_func_3;
		$fn     = $suffix ? '_win' : '';

		$reflections = [
			new ReflectionClass( "CommandFactoryTests_Get_Doc_Comment_1_Command$class_suffix" ),
			new ReflectionClass( "CommandFactoryTests_Get_Doc_Comment_2_Command$class_suffix" ),
			new ReflectionMethod( "CommandFactoryTests_Get_Doc_Comment_2_Command$class_suffix", 'command1' ),
			new ReflectionFunction( "commandfactorytests_get_doc_comment_func_1$fn" ),
			new ReflectionFunction( "commandfactorytests_get_doc_comment_func_2$fn" ),
			new ReflectionFunction( $func_3 ),
		];
		foreach ( [ 'command1', 'command2', 'command3', 'command4' ] as $method ) {
			$reflections[] = new ReflectionMethod( "CommandFactoryTests_Get_Doc_Comment_1_Command$class_suffix", $method );
		}

		putenv( 'EE_TEST_GET_DOC_COMMENT=1' );
		CommandFactory::clear_file_contents_cache();
		try {
			foreach ( $reflections as $reflection ) {
				$this->assertSame( $reflection->getDocComment(), self::call_private( CommandFactory::class, 'get_doc_comment', $reflection ), $reflection->getName() );
			}
		} finally {
			putenv( 'EE_TEST_GET_DOC_COMMENT' );
			CommandFactory::clear_file_contents_cache();
		}
		// The methods without a doc comment really have none.
		$this->assertFalse( ( new ReflectionMethod( "CommandFactoryTests_Get_Doc_Comment_1_Command$class_suffix", 'command4' ) )->getDocComment() );
	}
}

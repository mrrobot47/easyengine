<?php

use EE\DocParser;
use EE\Tests\TestCase;

/**
 * EE\DocParser: command docblocks (descriptions, tags, synopsis, per-argument YAML).
 */
class DocParserTest extends TestCase {

	protected $reset_db = false;

	const SITE_CREATE_DOC = <<<'EOB'
/**
 * Creates a site.
 *
 * ## OPTIONS
 *
 * <site-name>
 * : Name of website.
 *
 * [--cache]
 * : Use redis cache for WordPress.
 *
 * [--proxy-cache=<on-or-off>]
 * : Enable or disable proxy cache on site.
 * ---
 * default: off
 * options:
 *  - on
 *  - off
 * ---
 *
 * [--php=<php-version>]
 * : PHP version for site.
 * ---
 * default: 8.4
 * options:
 *  - 7.4
 *  - 8.0
 *  - 8.4
 * ---
 *
 * [--ssl]
 * : Enables ssl on site.
 * ---
 * options:
 *      - le
 *      - self
 * ---
 *
 * ## EXAMPLES
 *
 *     $ ee site create example.com
 *
 * @subcommand create
 * @alias add
 */
EOB;

	public function test_empty_docblock() {
		$doc = new DocParser( '' );
		$this->assertSame( '', $doc->get_shortdesc() );
		$this->assertSame( '', $doc->get_longdesc() );
		$this->assertSame( '', $doc->get_synopsis() );
		$this->assertSame( '', $doc->get_tag( 'alias' ) );
	}

	public function test_only_tags() {
		$doc = new DocParser( "/**\n * @alias rock-on\n * @subcommand revoke-md5-passwords\n */" );
		$this->assertSame( '', $doc->get_shortdesc() );
		$this->assertSame( '', $doc->get_longdesc() );
		$this->assertSame( '', $doc->get_tag( 'foo' ) );
		$this->assertSame( 'rock-on', $doc->get_tag( 'alias' ) );
		$this->assertSame( 'revoke-md5-passwords', $doc->get_tag( 'subcommand' ) );
		$this->assertSame( 1, $doc->has_tag( 'alias' ) );
		$this->assertSame( 0, $doc->has_tag( 'when' ) );
	}

	public function test_shortdesc_without_longdesc() {
		$doc = new DocParser( "/**\n * Rock and roll!\n * @alias rock-on\n */" );
		$this->assertSame( 'Rock and roll!', $doc->get_shortdesc() );
		$this->assertSame( '', $doc->get_longdesc() );
	}

	public function test_crlf_docblock_parses_like_lf() {
		$doc = new DocParser( str_replace( "\n", "\r\n", self::SITE_CREATE_DOC ) );
		$this->assertSame( 'Creates a site.', $doc->get_shortdesc() );
		$this->assertSame( 'add', $doc->get_tag( 'alias' ) );
		$this->assertSame( ( new DocParser( self::SITE_CREATE_DOC ) )->get_param_args( 'php' ), $doc->get_param_args( 'php' ) );
		$this->assertSame( 'PHP version for site.', $doc->get_param_desc( 'php' ) );
	}

	public function test_longdesc_stops_at_the_first_tag_and_keeps_yaml_blocks() {
		$doc      = new DocParser( self::SITE_CREATE_DOC );
		$longdesc = $doc->get_longdesc();
		$this->assertStringStartsWith( "## OPTIONS\n\n<site-name>\n: Name of website.", $longdesc );
		$this->assertStringEndsWith( "## EXAMPLES\n\n    \$ ee site create example.com", $longdesc );
		$this->assertStringNotContainsString( '@subcommand', $longdesc );
		$this->assertStringContainsString( "---\ndefault: off\n", $longdesc );
	}

	public function test_explicit_synopsis_tag() {
		$doc = new DocParser( "/**\n * Rock.\n *\n * @synopsis <genre>... [--volume=<number>]\n */" );
		$this->assertSame( '<genre>... [--volume=<number>]', $doc->get_synopsis() );
	}

	public function test_argument_and_parameter_descriptions() {
		$doc = new DocParser( self::SITE_CREATE_DOC );
		$this->assertSame( 'PHP version for site.', $doc->get_param_desc( 'php' ) );
		$this->assertSame( 'Enable or disable proxy cache on site.', $doc->get_param_desc( 'proxy-cache' ) );
		$this->assertSame( '', $doc->get_param_desc( 'nope' ) );
	}

	public function test_parameters_without_a_yaml_block_have_no_args() {
		$doc = new DocParser( self::SITE_CREATE_DOC );
		$this->assertNull( $doc->get_param_args( 'cache' ) );
		$this->assertNull( $doc->get_arg_args( 'site-name' ) );
		$this->assertNull( $doc->get_param_args( 'nope' ) );
	}

	public function test_numeric_options_load_as_floats_except_trailing_zero() {
		$php = ( new DocParser( self::SITE_CREATE_DOC ) )->get_param_args( 'php' );
		// Root cause of PHPT-11/WPT-4: validate_args() compares these loosely.
		$this->assertSame( [ 7.4, '8.0', 8.4 ], $php['options'] );
		$this->assertSame( 8.4, $php['default'] );
	}

	public function test_quoted_on_off_options_stay_strings() {
		$doc = new DocParser( "/**\n * X.\n *\n * [--proxy-cache=<on-or-off>]\n * : Proxy cache.\n * ---\n * default: 'off'\n * options:\n *  - 'on'\n *  - 'off'\n * ---\n */" );
		$this->assertSame( [ 'default' => 'off', 'options' => [ 'on', 'off' ] ], $doc->get_param_args( 'proxy-cache' ) );
	}

	/**
	 * WPT-3: unquoted `on`/`off` options load as booleans, so they can't be compared with the string the user passes.
	 *
	 * @group known-bug
	 * @group WPT-3
	 */
	public function test_unquoted_on_off_options_stay_strings() {
		$this->assertSame( [ 'default' => 'off', 'options' => [ 'on', 'off' ] ], ( new DocParser( self::SITE_CREATE_DOC ) )->get_param_args( 'proxy-cache' ) );
	}

	public function test_flag_declared_parameter_gets_no_args() {
		// WPT-13/PHPT-17 root cause: `[--ssl]` is a flag, so its `options:` block is never read and --ssl=<anything> passes.
		$this->assertNull( ( new DocParser( self::SITE_CREATE_DOC ) )->get_param_args( 'ssl' ) );
	}

	public function test_yaml_of_a_later_parameter_is_not_attributed_to_an_earlier_one() {
		$doc = new DocParser( "## OPTIONS\n\n<hook>\n: The hook.\n\n[--format=<format>]\n: Format.\n---\ndefault: table\noptions:\n  - table\n  - json\n---" );
		$this->assertSame( [ 'default' => 'table', 'options' => [ 'table', 'json' ] ], $doc->get_param_args( 'format' ) );
		$this->assertNull( $doc->get_arg_args( 'hook' ) );
	}

	public function test_positional_args_yaml() {
		$doc = new DocParser( "## OPTIONS\n\n<genre>...\n: Genres.\n---\noptions:\n  - rock\n  - electronic\ndefault: rock\n---\n\n--volume=<number>\n: Volume.\n---\ndefault: 10\n---\n" );
		$this->assertSame( 'Genres.', $doc->get_arg_desc( 'genre' ) );
		$this->assertSame( [ 'options' => [ 'rock', 'electronic' ], 'default' => 'rock' ], $doc->get_arg_args( 'genre' ) );
		$this->assertSame( [ 'default' => 10 ], $doc->get_param_args( 'volume' ) );
	}
}

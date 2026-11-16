<?php

use EE\Formatter;
use EE\Tests\TestCase;

/**
 * EE\Formatter and format_items(): field lookup, JSON flattening and the table/json/yaml/csv/count/ids formats.
 */
class FormatterTest extends TestCase {

	protected $reset_db = false;

	private $shell_pipe;

	protected function setUp(): void {
		parent::setUp();
		// cli\Table renders tab-separated when STDOUT isn't a TTY; pin the ASCII table users see.
		$this->shell_pipe = getenv( 'SHELL_PIPE' );
		putenv( 'SHELL_PIPE=0' );
	}

	protected function tearDown(): void {
		putenv( false === $this->shell_pipe ? 'SHELL_PIPE' : 'SHELL_PIPE=' . $this->shell_pipe );
		parent::tearDown();
	}

	private static function items() {
		return [
			[ 'site_url' => 'a.test', 'site_type' => 'wp', 'meta' => [ 'ssl' => 'le' ] ],
			[ 'site_url' => 'b.test', 'site_type' => 'php', 'meta' => null ],
		];
	}

	private static function formatter( $format, $fields, $prefix = false ) {
		$args = [ 'format' => $format ];

		return new Formatter( $args, $fields, $prefix );
	}

	/** @return string What $fn echoed. */
	private static function echoed( callable $fn ) {
		ob_start();
		try {
			$fn();
		} finally {
			$out = ob_get_clean();
		}

		return $out;
	}

	public function test_constructor_takes_format_arguments_out_of_assoc_args() {
		$assoc     = [ 'format' => 'json', 'fields' => 'site_url, site_type', 'all' => true ];
		$formatter = new Formatter( $assoc, [ 'ignored' ] );
		$this->assertSame( [ 'all' => true ], $assoc );
		$this->assertSame( 'json', $formatter->format );
		$this->assertSame( [ 'site_url', 'site_type' ], $formatter->fields );
		$this->assertNull( $formatter->field );
	}

	public function test_find_item_key_prefers_the_plain_field_then_the_prefixed_one() {
		$formatter = self::formatter( 'table', 'url', 'site' );
		$this->assertSame( 'url', self::call_private( $formatter, 'find_item_key', [ 'url' => 1, 'site_url' => 2 ], 'url' ) );
		$this->assertSame( 'site_url', self::call_private( $formatter, 'find_item_key', [ 'site_url' => 2 ], 'url' ) );
		$this->assertSame( 'site_url', self::call_private( $formatter, 'find_item_key', (object) [ 'site_url' => null ], 'url' ) );
		// Arrays: a NULL value still counts as present.
		$this->assertSame( 'meta', self::call_private( $formatter, 'find_item_key', [ 'meta' => null ], 'meta' ) );
	}

	public function test_find_item_key_errors_on_a_missing_field() {
		$formatter = self::formatter( 'table', 'x' );
		$this->assert_ee_error(
			function () use ( $formatter ) {
				self::call_private( $formatter, 'find_item_key', [ 'a' => 1 ], 'nope' );
			},
			'Invalid field: nope.'
		);
	}

	public function test_transform_item_values_to_json_only_touches_arrays_and_objects() {
		$formatter = self::formatter( 'table', 'site_url,meta' );
		$this->assertSame( [ 'site_url' => 'a.test', 'site_type' => 'wp', 'meta' => '{"ssl":"le"}' ], $formatter->transform_item_values_to_json( self::items()[0] ) );
		$this->assertSame( self::items()[1], $formatter->transform_item_values_to_json( self::items()[1] ) );
		$object = $formatter->transform_item_values_to_json( (object) [ 'site_url' => 'c.test', 'meta' => (object) [ 'a' => 1 ] ] );
		$this->assertSame( '{"a":1}', $object->meta );
	}

	public function test_piped_table_output_is_tab_separated() {
		putenv( 'SHELL_PIPE=1' );
		EE\Utils\format_items( 'table', self::items(), [ 'site_url', 'site_type' ] );
		$this->assertSame( "site_url\tsite_type\na.test\twp\nb.test\tphp\n", $this->stdout() );
	}

	public function test_table_output() {
		EE\Utils\format_items( 'table', self::items(), [ 'site_url', 'site_type' ] );
		$this->assertSame(
			"+----------+-----------+\n| site_url | site_type |\n+----------+-----------+\n| a.test   | wp        |\n| b.test   | php       |\n+----------+-----------+\n",
			$this->stdout()
		);
	}

	public function test_table_encodes_nested_values_as_json() {
		EE\Utils\format_items( 'table', self::items(), 'site_url,meta' );
		$this->assertStringContainsString( '| a.test   | {"ssl":"le"} |', $this->stdout() );
	}

	public function test_json_output_picks_the_fields() {
		$out = self::echoed(
			function () {
				EE\Utils\format_items( 'json', self::items(), [ 'site_url', 'meta' ] );
			}
		);
		$this->assertSame( [ [ 'site_url' => 'a.test', 'meta' => [ 'ssl' => 'le' ] ], [ 'site_url' => 'b.test', 'meta' => null ] ], json_decode( $out, true ) );
	}

	public function test_yaml_output() {
		$out = self::echoed(
			function () {
				EE\Utils\format_items( 'yaml', self::items(), [ 'site_url', 'site_type' ] );
			}
		);
		$this->assertSame( "---\n- \n  site_url: a.test\n  site_type: wp\n- \n  site_url: b.test\n  site_type: php\n", $out );
	}

	public function test_count_and_ids() {
		$this->assertSame( '2', self::echoed( function () { EE\Utils\format_items( 'count', self::items(), 'site_url' ); } ) );
		$this->assertSame( '3 5 8', self::echoed( function () { EE\Utils\format_items( 'ids', [ 3, 5, 8 ], 'id' ); } ) );
	}

	public function test_single_field_prints_one_value_per_line() {
		$args      = [ 'field' => 'url' ];
		$formatter = new Formatter( $args, [ 'site_url' ], 'site' );
		$out       = self::echoed(
			function () use ( $formatter ) {
				$formatter->display_items( self::items() );
			}
		);
		$this->assertSame( "a.test\nb.test\n", $out );
	}

	public function test_display_item_as_table_lists_field_value_rows() {
		self::formatter( 'table', [ 'site_url', 'meta' ] )->display_item( self::items()[0] );
		$this->assertSame(
			"+----------+--------------+\n| Field    | Value        |\n+----------+--------------+\n| site_url | a.test       |\n| meta     | {\"ssl\":\"le\"} |\n+----------+--------------+\n",
			$this->stdout()
		);
	}

	public function test_invalid_format_is_an_error() {
		$this->assert_ee_error(
			function () {
				EE\Utils\format_items( 'xml', self::items(), 'site_url' );
			},
			'Invalid format: xml'
		);
	}

	public function test_write_csv_quotes_and_picks_headers() {
		$fd = fopen( 'php://memory', 'w+' );
		EE\Utils\write_csv( $fd, [ [ 'a' => 'x,y', 'b' => 'say "hi"', 'c' => 'dropped' ] ], [ 'a', 'b' ] );
		rewind( $fd );
		$this->assertSame( "a,b\n\"x,y\",\"say \"\"hi\"\"\"\n", stream_get_contents( $fd ) );
	}

	public function test_model_rows_with_values_format_as_a_table() {
		EE\Utils\format_items( 'table', [ new PHPUnit_Formatter_Row( [ 'id' => 1, 'user' => 'root' ] ) ], [ 'id', 'user' ] );
		$this->assertStringContainsString( '| 1  | root |', $this->stdout() );
	}

	/**
	 * CRON-12: Model\Base::__isset() is false for a NULL column, so a model row with a NULL field fails with "Invalid field".
	 *
	 * @group known-bug
	 * @group CRON-12
	 */
	public function test_model_rows_with_a_null_column_format_as_a_table() {
		try {
			EE\Utils\format_items(
				'table',
				[ new PHPUnit_Formatter_Row( [ 'id' => 1, 'user' => 'root' ] ), new PHPUnit_Formatter_Row( [ 'id' => 2, 'user' => null ] ) ],
				[ 'id', 'user' ]
			);
		} catch ( EE\ExitException $e ) {
			$this->fail( 'EE::error(): ' . $this->stderr() );
		}
		$this->assertStringContainsString( '| 2  |      |', $this->stdout() );
	}
}

class PHPUnit_Formatter_Row extends EE\Model\Base {
	protected static $table = 'cron';
}

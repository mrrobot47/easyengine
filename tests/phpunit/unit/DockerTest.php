<?php

use EE\Tests\TestCase;

/**
 * EE_DOCKER command building and result parsing (php/class-ee-docker.php).
 */
class DockerTest extends TestCase {

	protected $reset_db = false;

	public function test_docker_style_prefix_drops_dots_and_dashes() {
		$this->assertSame( 'examplecom', EE_DOCKER::get_docker_style_prefix( 'example.com' ) );
		$this->assertSame( 'mysitetest', EE_DOCKER::get_docker_style_prefix( 'my-site.test' ) );
	}

	/**
	 * PHPT-4: different sites map to the same volume prefix, so they share htdocs, config and db volumes.
	 *
	 * @group known-bug
	 * @group PHPT-4
	 */
	public function test_docker_style_prefix_is_unique_per_site() {
		$prefixes = array_map( [ EE_DOCKER::class, 'get_docker_style_prefix' ], [ 'a-b.test', 'ab.test', 'a.b.test' ] );
		$this->assertCount( 3, array_unique( $prefixes ), implode( ', ', $prefixes ) );
	}

	public function test_create_volumes_skips_existing_volumes_and_labels_new_ones() {
		$dir = $this->sandbox();
		$this->runner->on( '/^docker info /', "/var/lib/docker\n" );
		$this->runner->on( "/^docker volume inspect '?exampletest_htdocs'?$/", '[]', 0 );
		$this->runner->on( "/^docker volume inspect '?exampletest_config'?$/", '', 1 );

		EE_DOCKER::create_volumes(
			'example.test',
			[
				[ 'name' => 'htdocs', 'path_to_symlink' => "$dir/app/htdocs" ],
				[ 'name' => 'config', 'path_to_symlink' => "$dir/config/nginx" ],
				[ 'name' => 'logs', 'path_to_symlink' => "$dir/logs", 'skip_volume' => true ],
			]
		);

		$creates = $this->runner->matching( '/docker volume create/' );
		$this->assertCount( 1, $creates );
		$this->assertStringContainsString( 'io.easyengine.site=example.test', $creates[0] );
		$this->assertStringContainsString( 'org.label-schema.vendor=EasyEngine', $creates[0] );
		$this->assertMatchesRegularExpression( "/\s'?exampletest_config'?$/", trim( $creates[0] ) );
		$this->assertSame( '/var/lib/docker/volumes/exampletest_config/_data', readlink( "$dir/config/nginx" ) );
		$this->assertFalse( is_link( "$dir/app/htdocs" ) );
		$this->assertEmpty( $this->runner->matching( '/inspect exampletest_logs/' ) );
	}

	public function test_create_volumes_can_keep_the_prefix_as_given() {
		$this->runner->on( '/^docker volume inspect /', '', 1 );
		EE_DOCKER::create_volumes( 'global-db', [ [ 'name' => 'data', 'path_to_symlink' => '' ] ], false );
		$this->assertCount( 1, $this->runner->matching( "/docker volume create.*\s'?global-db_data'?$/s" ) );
	}

	public function test_get_volumes_by_label_filters_by_site_and_parses_names() {
		$this->runner->on( '/^docker volume ls /', "exampletest_htdocs\nexampletest_config\n\n" );
		$this->assertSame( [ 'exampletest_htdocs', 'exampletest_config' ], EE_DOCKER::get_volumes_by_label( 'example.test' ) );
		$this->assertStringContainsString( 'label=io.easyengine.site=example.test', $this->runner->commands()[0] );
	}

	/**
	 * SEC-1 sink: the site name reaches the shell unquoted in the volume label filter.
	 *
	 * @group known-bug
	 * @group SEC-1
	 */
	public function test_get_volumes_by_label_is_shell_safe() {
		$this->assert_shell_safe(
			function ( $site ) {
				EE_DOCKER::get_volumes_by_label( $site );
			}
		);
	}

	/**
	 * SEC-1 sinks: `docker volume inspect` and `docker volume create` interpolate the site name unquoted.
	 *
	 * @group known-bug
	 * @group SEC-1
	 */
	public function test_create_volumes_is_shell_safe() {
		$this->runner->on( '/^docker volume inspect /', '', 1 );
		$this->assert_shell_safe(
			function ( $site ) {
				EE_DOCKER::create_volumes( $site, [ [ 'name' => 'htdocs', 'path_to_symlink' => '' ] ] );
			},
			'/^docker volume /'
		);
	}

	public function test_docker_compose_exec_adds_user_and_tty_flags() {
		$dir = $this->sandbox();
		$this->set_config( [ 'skip-tty' => true, 'custom-compose' => null ] );
		EE_DOCKER::docker_compose_exec( 'wp plugin list', 'php', 'bash', 'www-data', $dir );
		$this->assertSame( [ "docker-compose -f docker-compose.yml  exec -T --user='www-data' php wp plugin list" ], $this->runner->commands() );

		$this->runner->reset();
		$this->set_config( [ 'skip-tty' => false ] );
		EE_DOCKER::docker_compose_exec( 'ls', 'nginx', 'sh', '', $dir, true );
		$this->assertSame( [ 'docker-compose -f docker-compose.yml  exec   nginx sh -c "ls"' ], $this->runner->commands() );
	}

	/**
	 * CORE-2: `--skip-tty=false` arrives as the string 'false', which is non-empty, so -T is still added.
	 *
	 * @group known-bug
	 * @group CORE-2
	 */
	public function test_docker_compose_exec_honours_skip_tty_false() {
		$this->set_config( [ 'skip-tty' => 'false', 'custom-compose' => null ] );
		EE_DOCKER::docker_compose_exec( 'ls', 'nginx', 'sh', '', $this->sandbox() );
		$this->assertStringNotContainsString( ' -T ', $this->runner->commands()[0] );
	}

	public function test_docker_compose_with_custom_adds_user_compose_files_in_order() {
		$dir = $this->sandbox();
		chdir( $dir );
		mkdir( SITE_CUSTOM_DOCKER_COMPOSE_DIR );
		touch( SITE_CUSTOM_DOCKER_COMPOSE_DIR . '/b.yml' );
		touch( SITE_CUSTOM_DOCKER_COMPOSE_DIR . '/a.yaml' );
		touch( 'docker-compose-admin-tools.yml' );
		touch( SITE_CUSTOM_DOCKER_COMPOSE );
		$this->set_config( [ 'custom-compose' => null ] );

		$command = EE_DOCKER::docker_compose_with_custom( [ 'docker-compose-admin-tools.yml', 'missing.yml' ] );

		$this->assertSame( 'docker-compose -f docker-compose.yml  -f docker-compose-admin-tools.yml -f user-docker-compose/b.yml -f user-docker-compose/a.yaml -f docker-compose-custom.yml', $command );
	}

	public function test_docker_compose_with_custom_uses_only_the_named_custom_file() {
		$dir = $this->sandbox();
		chdir( $dir );
		mkdir( SITE_CUSTOM_DOCKER_COMPOSE_DIR );
		touch( SITE_CUSTOM_DOCKER_COMPOSE_DIR . '/prod.yml' );
		$this->set_config( [ 'custom-compose' => 'prod.yml' ] );
		$this->assertSame( 'docker-compose -f docker-compose.yml  -f user-docker-compose/prod.yml', EE_DOCKER::docker_compose_with_custom() );

		$this->set_config( [ 'custom-compose' => 'nope.yml' ] );
		$this->assertSame( 'docker-compose -f docker-compose.yml ', EE_DOCKER::docker_compose_with_custom() );
		$this->assertStringContainsString( 'nope.yml does not exist', $this->stderr() );
	}

	public function test_get_services_splits_compose_output() {
		$this->set_config( [ 'custom-compose' => null ] );
		$this->runner->on( '/config --services$/', "nginx\nphp\ndb\n" );
		$dir = $this->sandbox();
		$this->assertSame( [ 'nginx', 'php', 'db' ], EE_DOCKER::get_services( $dir ) );
		$this->assertTrue( EE_DOCKER::service_exists( 'php', $dir ) );
		$this->assertFalse( EE_DOCKER::service_exists( 'redis', $dir ) );
	}

	public function test_mounting_volume_array_uses_host_path_and_skips_linux_only_entries() {
		$volumes = [
			[ 'name' => '/opt/easyengine/sites/a.test/app', 'path_to_symlink' => '/x', 'container_path' => '/var/www' ],
			[ 'name' => 'skipped', 'container_path' => '/y', 'skip_linux' => true ],
		];
		$expected = IS_DARWIN ? [ '/x:/var/www', 'skipped:/y' ] : [ '/opt/easyengine/sites/a.test/app:/var/www' ];
		if ( IS_DARWIN ) {
			$this->markTestSkipped( 'Linux mapping only.' );
		}
		$this->assertSame( $expected, EE_DOCKER::get_mounting_volume_array( $volumes ) );
	}

	public function test_network_helpers_report_the_exit_code() {
		$this->runner->on( '/^docker network inspect ee-missing$/', '', 1 );
		$this->assertTrue( EE_DOCKER::docker_network_exists( 'ee-global-frontend-network' ) );
		$this->assertFalse( EE_DOCKER::docker_network_exists( 'ee-missing' ) );
		$this->assertTrue( EE_DOCKER::create_network( 'examplenet' ) );
		$this->assertSame( 'docker network create examplenet --label=org.label-schema.vendor="EasyEngine" ', $this->runner->commands()[2] );
	}
}

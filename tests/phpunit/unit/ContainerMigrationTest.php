<?php

use EE\Migration\Containers;
use EE\Migration\CustomContainerMigrations;
use EE\Model\Migration;
use EE\Model\Option;
use EE\Tests\TestCase;

/**
 * Image migration (EE\Migration\Containers) and container migration discovery (EE\Migration\CustomContainerMigrations).
 */
class ContainerMigrationTest extends TestCase {

	const DOCKER_PS = 'docker ps --format "{{.Image}}" | grep "^easyengine/" | sort -u';

	/** A fake docker-compose binary at the path `command -v docker-compose` answers with. */
	private function compose_binary( $version, $content = 'old-binary' ) {
		$path = $this->sandbox() . '/docker-compose';
		file_put_contents( $path, $content );
		$this->runner->on( '/^docker-compose version --short$/', "$version\n" );
		$this->runner->on( '/^command -v docker-compose$/', "$path\n" );

		return $path;
	}

	public function test_current_versions_merge_running_containers_over_the_db() {
		Option::set( 'version', '4.13.0' );
		Option::set( 'easyengine/nginx', 'v4.10.0' );
		Option::set( 'easyengine/redis', 'v4.13.0' );
		$this->runner->on( '/^docker ps /', "easyengine/nginx:v4.11.0\neasyengine/cron:v4.11.0\n" );

		$this->assertSame(
			[ 'easyengine/nginx' => 'v4.11.0', 'easyengine/cron' => 'v4.11.0', 'easyengine/redis' => 'v4.13.0' ],
			Containers::get_current_docker_images_versions()
		);
		$this->assertSame( [ self::DOCKER_PS ], $this->runner->commands() );
	}

	public function test_current_versions_fall_back_to_the_db_when_nothing_runs() {
		Option::set( 'easyengine/mariadb', 'v4.9.1' );
		$this->assertSame( [ 'easyengine/mariadb' => 'v4.9.1' ], Containers::get_current_docker_images_versions() );
	}

	/**
	 * MIG-14: with two tags of one image running, the lexicographically last line wins, so a partially migrated nginx (v4.12.0 + v4.13.0) looks up to date.
	 *
	 * @group known-bug
	 * @group MIG-14
	 */
	public function test_current_version_of_a_partially_migrated_image_is_the_oldest_running_tag() {
		// Output after `sort -u`.
		$this->runner->on( '/^docker ps /', "easyengine/nginx:v4.12.0\neasyengine/nginx:v4.13.0\n" );
		$this->assertSame( [ 'easyengine/nginx' => 'v4.12.0' ], Containers::get_current_docker_images_versions() );
	}

	public function test_fresh_install_pulls_every_image_except_the_php_and_newrelic_ones() {
		Containers::start_container_migration();

		$expected = [ self::DOCKER_PS ];
		foreach ( EE\Utils\get_image_versions() as $image => $tag ) {
			if ( ! preg_match( '#^easyengine/(php\d|newrelic-daemon)#', $image ) ) {
				$expected[] = "docker pull $image:$tag";
			}
		}
		$this->assertContains( 'docker pull easyengine/php:' . EE\Utils\get_image_versions()['easyengine/php'], $expected );
		// Nothing was running, so nothing is migrated or recorded.
		$this->assertSame( $expected, $this->runner->commands() );
		$this->assertSame( [], Option::where( 'key', 'like', 'easyengine/%' ) );
	}

	public function test_a_failed_pull_aborts_the_migration() {
		$this->runner->on( '/^docker pull easyengine\/cron:/', '', 1 );
		$this->expectExceptionMessage( 'Unable to pull easyengine/cron. Please check logs for more details.' );
		Containers::start_container_migration();
	}

	public function test_image_version_db_entries_are_updated_and_reverted() {
		Option::set( 'easyengine/nginx', 'v4.10.0' );
		Option::set( 'easyengine/redis', 'v4.12.0' );
		Containers::create_database_entry( [ 'easyengine/nginx' => 'v4.11.0', 'easyengine/redis' => 'v4.13.0' ], [ 'easyengine/nginx' ] );
		$this->assertSame( [ 'v4.11.0', 'v4.12.0' ], [ Option::get( 'easyengine/nginx' ), Option::get( 'easyengine/redis' ) ] );

		Containers::revert_database_entry( [ 'easyengine/nginx' => 'v4.10.0' ], [ 'easyengine/nginx' ] );
		$this->assertSame( 'v4.10.0', Option::get( 'easyengine/nginx' ) );
	}

	public function test_docker_cleanup_prunes_only_easyengine_images_and_networks() {
		Containers::docker_cleanup();
		$this->assertSame(
			[
				'docker image prune -af --filter=label=org.label-schema.vendor="EasyEngine"',
				'docker network prune -f --filter=label=org.label-schema.vendor="EasyEngine"',
			],
			$this->runner->commands()
		);
	}

	public function test_compose_at_or_above_2_27_is_left_alone() {
		$this->compose_binary( '5.5.1' );
		Containers::update_docker_compose();
		$this->assertSame( [], $this->runner->matching( '/curl|mv /' ) );
		$this->assertFileDoesNotExist( EE_BACKUP_DIR . '/docker-compose.backup' );
	}

	public function test_older_compose_is_backed_up_and_replaced_with_2_27_0() {
		$path = $this->compose_binary( '1.29.2' );
		Containers::update_docker_compose();

		$new      = EE_BACKUP_DIR . '/docker-compose';
		$commands = $this->runner->matching( '/curl|^mv /' );
		$this->assertCount( 2, $commands );
		$this->assertMatchesRegularExpression( '#^curl .*https://github\.com/docker/compose/releases/download/v2\.27\.0/docker-compose-\$\(uname -s\)-\$\(uname -m\) -o ' . preg_quote( $new, '#' ) . ' && chmod \+x ' . preg_quote( $new, '#' ) . '$#', $commands[0] );
		$this->assertSame( "mv $new $path", $commands[1] );
		$this->assertSame( 'old-binary', file_get_contents( EE_BACKUP_DIR . '/docker-compose.backup' ) );
		unlink( EE_BACKUP_DIR . '/docker-compose.backup' );
	}

	/**
	 * MIG-10: the compose download has no `--fail`, so an HTTP error page is saved (and then moved over the binary).
	 *
	 * @group known-bug
	 * @group MIG-10
	 */
	public function test_compose_download_fails_on_http_errors() {
		$this->compose_binary( '1.29.2' );
		Containers::update_docker_compose();
		@unlink( EE_BACKUP_DIR . '/docker-compose.backup' );
		$this->assertMatchesRegularExpression( '/^curl (?:.* )?(?:--fail|-[a-zA-Z]*f[a-zA-Z]*) /', $this->runner->matching( '/^curl /' )[0] );
	}

	/**
	 * MIG-10: the download's exit code is ignored, so a failed download is still moved over docker-compose.
	 *
	 * @group known-bug
	 * @group MIG-10
	 */
	public function test_failed_compose_download_does_not_replace_the_binary() {
		$this->compose_binary( '1.29.2' );
		$this->runner->on( '/^curl /', '', 22, 'curl: (22) The requested URL returned error: 404' );
		Containers::update_docker_compose();
		@unlink( EE_BACKUP_DIR . '/docker-compose.backup' );
		$this->assertSame( [], $this->runner->matching( '/^mv /' ) );
	}

	/**
	 * MIG-10: revert_docker_compose() copies without overwrite, and the backup is always older, so nothing is restored.
	 *
	 * @group known-bug
	 * @group MIG-10
	 */
	public function test_revert_restores_the_backed_up_compose_binary() {
		$path = $this->compose_binary( '2.27.0', 'broken-download' );
		@mkdir( EE_BACKUP_DIR, 0755, true );
		file_put_contents( EE_BACKUP_DIR . '/docker-compose.backup', 'old-binary' );
		touch( EE_BACKUP_DIR . '/docker-compose.backup', time() - 3600 );

		Containers::revert_docker_compose();
		unlink( EE_BACKUP_DIR . '/docker-compose.backup' );
		$this->assertSame( 'old-binary', file_get_contents( $path ) );
	}

	public function test_container_migration_path_by_package() {
		$this->assertSame( EE_ROOT . '/migrations/container/20190101000000_easyengine_fix.php', self::call_private( CustomContainerMigrations::class, 'get_migration_path', '20190101000000_easyengine_fix.php' ) );
		$this->assertSame( EE_ROOT . '/vendor/easyengine/site-command/migrations/container/20190101000000_site-command_fix.php', self::call_private( CustomContainerMigrations::class, 'get_migration_path', '20190101000000_site-command_fix.php' ) );
		$this->assertSame( '', self::call_private( CustomContainerMigrations::class, 'get_migration_path', 'README.md' ) );
	}

	public function test_only_container_migrations_recorded_in_the_db_are_skipped() {
		Migration::create( [ 'migration' => 'b.php', 'type' => 'container', 'timestamp' => '2020-01-01 00:00:00' ] );
		Migration::create( [ 'migration' => 'c.php', 'type' => 'db', 'timestamp' => '2020-01-01 00:00:00' ] );
		$this->assertSame( [ 'a.php', 'c.php' ], self::call_private( CustomContainerMigrations::class, 'get_migrations_to_execute', [ 'a.php', 'b.php', 'c.php' ] ) );
	}

	public function test_discovery_finds_package_container_migrations_not_yet_run() {
		$done = '20181119091115_admin-tools-command_update_index.php';
		Migration::create( [ 'migration' => $done, 'type' => 'container', 'timestamp' => '2020-01-01 00:00:00' ] );
		$found = self::call_private( CustomContainerMigrations::class, 'get_all_migrations' );

		$this->assertContains( '20190104010207_admin-tools-command_update_config_with_env.php', $found );
		$this->assertNotContains( $done, $found );
		$this->assertSame( count( glob( EE_VENDOR_DIR . '/easyengine/*/migrations/container/*.php' ) ) - 1, count( $found ) );
		foreach ( $found as $file ) {
			$this->assertFileExists( self::call_private( CustomContainerMigrations::class, 'get_migration_path', $file ) );
		}
	}
}

<?php

namespace EE\Logrotate;

/**
 * Logrotate setup utilities.
 */
class Utils {

	const CONFIG_DIR = '/etc/logrotate.d';
	const SITES_CONFIG_FILE = '/etc/logrotate.d/ee_sites';
	const NGINX_PROXY_CONFIG_FILE = '/etc/logrotate.d/ee_nginx_proxy';

	/**
	 * Configure logrotate for EasyEngine site and nginx-proxy logs.
	 */
	public static function setup_logrotate() {

		try {
			self::setup_logrotate_config();
		} catch ( \Throwable $e ) {
			\EE::warning( 'Unable to setup EasyEngine logrotate config: ' . $e->getMessage() );
		}
	}

	/**
	 * Configure logrotate for EasyEngine site and nginx-proxy logs.
	 */
	private static function setup_logrotate_config() {

		if ( defined( 'IS_DARWIN' ) && IS_DARWIN ) {
			\EE::debug( 'Skipping logrotate setup on macOS.' );
			return;
		}

		if ( ! self::ensure_logrotate_installed() ) {
			return;
		}

		if ( ! is_dir( self::CONFIG_DIR ) && ! @mkdir( self::CONFIG_DIR, 0755, true ) ) {
			\EE::warning( 'Unable to create logrotate config directory: ' . self::CONFIG_DIR );
			return;
		}

		$sites_written = self::write_config( self::SITES_CONFIG_FILE, self::get_sites_config() );
		$proxy_written = self::write_config( self::NGINX_PROXY_CONFIG_FILE, self::get_nginx_proxy_config() );

		if ( $sites_written && $proxy_written ) {
			self::cleanup_legacy_configs();
		}
	}

	/**
	 * Ensure logrotate is available on supported systems.
	 *
	 * @return bool
	 */
	private static function ensure_logrotate_installed() {

		if ( self::command_exists( 'logrotate' ) ) {
			return true;
		}

		if ( ! self::command_exists( 'apt-get' ) ) {
			\EE::warning( 'logrotate is not installed and apt-get is unavailable. Skipping EasyEngine logrotate setup.' );
			return false;
		}

		\EE::log( 'Installing logrotate.' );
		$result = \EE::launch( 'DEBIAN_FRONTEND=noninteractive apt-get install -y logrotate', false, true );

		if ( 0 !== $result->return_code || ! self::command_exists( 'logrotate' ) ) {
			\EE::warning( 'Unable to install logrotate. Skipping EasyEngine logrotate setup.' );
			return false;
		}

		return true;
	}

	/**
	 * Check whether a command is available in PATH.
	 *
	 * @param string $command Command name.
	 * @return bool
	 */
	private static function command_exists( $command ) {

		$result = \EE::launch( 'command -v ' . escapeshellarg( $command ) . ' >/dev/null 2>&1', false, true );

		return 0 === $result->return_code;
	}

	/**
	 * Write a logrotate config if it is missing or stale.
	 *
	 * @param string $file Config file path.
	 * @param string $content Config content.
	 * @return bool
	 */
	private static function write_config( $file, $content ) {

		if ( file_exists( $file ) && $content === @file_get_contents( $file ) ) {
			return true;
		}

		if ( false === @file_put_contents( $file, $content ) ) {
			\EE::warning( 'Unable to write EasyEngine logrotate config: ' . $file );
			return false;
		}

		@chmod( $file, 0644 );

		return true;
	}

	/**
	 * Remove old per-site/proxy configs that duplicate the wildcard configs.
	 */
	private static function cleanup_legacy_configs() {

		$files = glob( self::CONFIG_DIR . '/ee_*' );

		if ( false === $files ) {
			return;
		}

		foreach ( $files as $file ) {
			$basename = basename( $file );

			if ( in_array( $basename, [ 'ee_sites', 'ee_nginx_proxy' ], true ) || ! is_file( $file ) ) {
				continue;
			}

			$contents = @file_get_contents( $file );

			if ( false === $contents || ! self::is_legacy_config( $basename, $contents ) ) {
				continue;
			}

			if ( ! @unlink( $file ) ) {
				\EE::warning( 'Unable to remove legacy EasyEngine logrotate config: ' . $file );
			}
		}
	}

	/**
	 * Check whether a config duplicates EasyEngine log rotation.
	 *
	 * @param string $basename Config file basename.
	 * @param string $contents Config contents.
	 * @return bool
	 */
	private static function is_legacy_config( $basename, $contents ) {

		return self::is_legacy_site_config( $basename, $contents )
			|| self::is_legacy_nginx_proxy_config( $basename, $contents );
	}

	/**
	 * Check whether a config matches old per-site generated configs.
	 *
	 * @param string $basename Config file basename.
	 * @param string $contents Config contents.
	 * @return bool
	 */
	private static function is_legacy_site_config( $basename, $contents ) {

		$site = substr( $basename, 3 );

		if ( ! preg_match( '/^ee_[A-Za-z0-9.-]+$/', $basename ) || false === strpos( $site, '.' ) ) {
			return false;
		}

		foreach ( self::get_legacy_roots() as $root_dir ) {
			$site_path = preg_quote( $root_dir . '/sites/' . $site, '/' );

			if (
				preg_match( '/' . $site_path . '\/logs\/nginx\/\*\.log/', $contents )
				&& preg_match( '/' . $site_path . '\/logs\/php\/\*\.log/', $contents )
				&& false !== strpos( $contents, 'docker inspect -f' )
			) {
				return true;
			}
		}

		return false;
	}

	/**
	 * Check whether a config matches old nginx-proxy generated config.
	 *
	 * @param string $basename Config file basename.
	 * @param string $contents Config contents.
	 * @return bool
	 */
	private static function is_legacy_nginx_proxy_config( $basename, $contents ) {

		if ( 'ee_nginx_proxy_logrotate' !== $basename ) {
			return false;
		}

		foreach ( self::get_legacy_roots() as $root_dir ) {
			$proxy_path = $root_dir . '/services/nginx-proxy/logs/*.log';

			if ( false !== strpos( $contents, $proxy_path ) ) {
				return true;
			}
		}

		return false;
	}

	/**
	 * Return root paths used by current and legacy EE logrotate configs.
	 *
	 * @return array
	 */
	private static function get_legacy_roots() {

		$roots = [ rtrim( EE_ROOT_DIR, '/' ) ];

		if ( '/opt/easyengine' !== $roots[0] ) {
			$roots[] = '/opt/easyengine';
		}

		return $roots;
	}

	/**
	 * Return the site logs config.
	 *
	 * @return string
	 */
	private static function get_sites_config() {

		$root_dir = rtrim( EE_ROOT_DIR, '/' );

		return <<<LOGROTATE
{$root_dir}/sites/*/logs/nginx/*.log
{$root_dir}/sites/*/logs/php/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
    sharedscripts
}
LOGROTATE
		. PHP_EOL;
	}

	/**
	 * Return the nginx-proxy logs config.
	 *
	 * @return string
	 */
	private static function get_nginx_proxy_config() {

		$root_dir = rtrim( EE_ROOT_DIR, '/' );

		return <<<LOGROTATE
{$root_dir}/services/nginx-proxy/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
    sharedscripts
}
LOGROTATE
		. PHP_EOL;
	}
}

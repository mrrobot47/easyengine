<?php

namespace EE\Migration;

use EE;
use Symfony\Component\Filesystem\Filesystem;

/**
 * Upgrade existing global containers to new docker-image
 */
class GlobalContainers {

	/**
	 * Get global containers which has new image update.
	 *
	 * @param $updated_images array of updated docker-images
	 *
	 * @return array
	 */
	public static function get_updated_global_images( $updated_images ) {

		$global_images           = self::get_all_global_images_with_service_name();
		$running_global_services = [];
		foreach ( $global_images as $image => $container_name ) {
			if ( 'running' === \EE_DOCKER::container_status( $container_name ) ) {
				$running_global_services[] = $image;
			}
		}

		return array_intersect( $running_global_services, $updated_images );
	}

	/**
	 * * Restore  backed up docker-compose.yml file.
	 *
	 * @param $source_path string path of backup file.
	 * @param $dest_path   string path of global docker-compose.yml
	 *
	 * @throws \Exception
	 */
	public static function revert_global_containers( $source_path, $dest_path, $updated_images ) {

		$services_to_regenerate = '';
		$all_global_images      = self::get_all_global_images_with_service_name();
		foreach ( $updated_images as $image_name ) {
			$global_container_name  = $all_global_images[ $image_name ];
			$services_to_regenerate .= ltrim( rtrim( $global_container_name, '_1' ), 'services_' ) . ' ';
		}
		if ( empty( trim( $services_to_regenerate ) ) ) {
			return;
		}
		EE::debug( 'Start restoring global docker-compose.yml file from backup' );
		$fs = new Filesystem();
		$fs->copy( $source_path, $dest_path, true );

		chdir( EE_ROOT_DIR . '/services' );

		if ( ! EE::exec( \EE_DOCKER::docker_compose_with_custom() . ' up -d ' . $services_to_regenerate ) ) {
			throw new \Exception( 'Unable to downgrade global containers. Please check logs for more details.' );
		}
		EE::debug( 'Complete restoring global docker-compose.yml file from backup' );
	}

	/**
	 * Stop global container and remove them.
	 *
	 * @param $updated_images array of newly available images.
	 *
	 * @throws \Exception
	 */
	public static function down_global_containers( $updated_images ) {
		EE::debug( 'Start removing global containers' );
		chdir( EE_ROOT_DIR . '/services' );
		$all_global_images = self::get_all_global_images_with_service_name();

		foreach ( $updated_images as $image_name ) {
			$global_container_name = $all_global_images[ $image_name ];
			$global_service_name   = ltrim( $global_container_name, 'services_' );
			$remove_suffix         = explode( '_1', $global_service_name );
			$global_service_name   = empty( $remove_suffix[0] ) ? $global_service_name : $remove_suffix[0];
			EE::debug( "Removing $global_container_name" );

			if ( false !== \EE_DOCKER::container_status( $global_container_name ) ) {
				if ( ! EE::exec( \EE_DOCKER::docker_compose_with_custom() . " stop $global_service_name && ". \EE_DOCKER::docker_compose_with_custom() . " rm -f $global_service_name" ) ) {
					throw new \Exception( "Unable to stop $global_container_name container" );
				}
			}
		}
		EE::debug( 'Complete removing global containers' );
	}

	/**
	 * Upgrade global service container.
	 *
	 * @throws \Exception
	 */
	public static function global_service_up( $service_name ) {
		$global_service_name = ltrim( $service_name, 'services_' );
		$remove_suffix       = explode( '_1', $global_service_name );
		$global_service_name = empty( $remove_suffix[0] ) ? $global_service_name : $remove_suffix[0];
		EE::debug( 'Start ' . $service_name . ' container up' );
		if ( 'global-nginx-proxy' === $global_service_name ) {
			\EE\Service\Utils\nginx_proxy_check();
		} else {
			\EE\Service\Utils\init_global_container( $service_name );
		}
	}

	/**
	 * Remove upgraded global service container.
	 *
	 * @throws \Exception
	 */
	public static function global_service_down( $service_name ) {
		EE::debug( 'Start ' . $service_name . ' container removing' );
		chdir( EE_ROOT_DIR . '/services' );

		if ( ! EE::exec( \EE_DOCKER::docker_compose_with_custom() . " stop $service_name && ". \EE_DOCKER::docker_compose_with_custom() . " rm -f $service_name" ) ) {
			throw new \Exception( sprintf( 'Unable to remove %1$s container', $service_name ) );
		}
		EE::debug( 'Complete ' . $service_name . ' container removing' );
	}


	/**
	 * Get all global images with it's service name.
	 *
	 * @return array
	 */
	public static function get_all_global_images_with_service_name() {

		return [
			'easyengine/nginx-proxy'     => GLOBAL_PROXY_CONTAINER,
			'easyengine/mariadb'         => GLOBAL_DB_CONTAINER,
			'easyengine/redis'           => GLOBAL_REDIS_CONTAINER,
			'easyengine/cron'            => GLOBAL_CRON_CONTAINER,
			'easyengine/newrelic-daemon' => GLOBAL_NEWRELIC_DAEMON_CONTAINER,
		];
	}
}

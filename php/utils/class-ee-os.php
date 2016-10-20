<?php

use Symfony\Component\Filesystem\Filesystem;
use Symfony\Component\Filesystem\Exception\IOExceptionInterface;

class EE_OS {

	public static function ee_platform_codename() {
		$os_codename = EE::exec_cmd_output( "lsb_release -sc" );

		return $os_codename;
	}

	public static function ee_platform_distro() {
		$os_distro = EE::exec_cmd_output( "lsb_release -si" );

		return $os_distro;
	}

	public static function ee_platform_version() {
		$os_version = EE::exec_cmd_output( "lsb_release -sr" );

		return $os_version;
	}

	public static function ee_core_version() {
		$ee_version = EE_VERSION;

		return $ee_version;
	}

	public static function add_swap() {

	}

	public static function get_system_mem_info() {
		$data = explode("\n", file_get_contents("/proc/meminfo"));
		$meminfo = array();
		foreach ($data as $line) {
			list($key, $val) = explode(":", $line);
			$val = explode(' ', trim($val));
			$val = $val[0] * 0.001;
			$meminfo[$key] = trim($val);
		}
		print_r( $meminfo );
		return $meminfo;
	}
}
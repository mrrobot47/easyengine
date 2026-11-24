<?php
// pkg-override.php <vendor-dir> <package> <new-source-dir>: copy the package's autoload from its new composer.json into installed.json/installed.php's view, so dump-autoload picks up added files.
[$_, $vendor, $pkg, $src] = $argv;
$new = json_decode(file_get_contents("$src/composer.json"), true);
$f = "$vendor/composer/installed.json";
$j = json_decode(file_get_contents($f), true);
$list = &$j['packages'];
$hit = 0;
foreach ($list as &$p) {
	if ($p['name'] === $pkg) {
		$p['autoload'] = $new['autoload'] ?? [];
		$hit++;
	}
}
file_put_contents($f, json_encode($j, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
echo "$pkg autoload replaced: $hit\n";
exit($hit === 1 ? 0 : 1);

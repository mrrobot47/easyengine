# Unit tests (PHPUnit)

Fast tests for EE logic: no Docker, no network, no `/opt/easyengine`. They run on PHPUnit 9.6, the only line that supports PHP 7.4 through 8.5 (core already requires it in `require-dev`).

## Run

```bash
composer install
php -d auto_prepend_file=tests/phpunit/prepend.php vendor/bin/phpunit                     # core
php -d auto_prepend_file=tests/phpunit/prepend.php vendor/bin/phpunit --group known-bug   # tests pinning open bugs (expected to fail)
```

`prepend.php` must run before Composer's autoloader: package autoload files otherwise define `EE_ROOT_DIR` as `/opt/easyengine` and create directories there. It roots every EE path in a per-process temp dir and points `EE_CONFIG_PATH` there. PHP deprecations are hidden; set `EE_PHPUNIT_DEPRECATIONS=1` to see them.

## Writing tests

Extend `EE\Tests\TestCase` (`includes/`). Per test it gives you:

- `$this->runner`: a `FakeProcessRunner` behind `EE::launch()`/`EE::exec()` (via `EE::set_process_runner()`). It records commands (`commands()`, `matching( $regex )`) and answers them from rules: `$this->runner->on( '/^docker volume inspect /', '', 1 )`. Unmatched commands succeed with no output. Outside a `TestCase`, any process call throws.
- A fresh SQLite DB at `DB` with the schema the DB migrations create (`fixtures/schema.sql`), `insert_site()`, and `TestDB::rows()/columns()/tables()`.
- `EE::error()` throws `EE\ExitException`: `assert_ee_error( $fn, 'message' )`. Output of `EE::log/warning/error` is in `stdout()`/`stderr()`.
- `set_config( [ 'skip-tty' => true ] )`, `sandbox()` (temp dir), `call_private()`, `get_static()`/`set_static()`, `get_property()`/`set_property()`; config, cwd and sandboxes are restored after each test.
- `assert_shell_safe( function ( $payload ) { ... } )`: calls the code with shell-injection payloads and runs every recorded command in `/bin/sh` without `PATH` to check that none of them reaches the shell (`ShellProbe`).

Tests that pin an open bug from the issue tracker carry `@group known-bug` plus the issue ID (e.g. `@group REL-7`); the default run excludes them. Remove the `known-bug` group in the PR that fixes the bug. To run one issue's tests: `--group SEC-1 --exclude-group none` (the config exclusion otherwise still applies).

## Packages

Package tests live in the package (`tests/phpunit/*Test.php`, `phpunit.xml.dist`) and run inside a core checkout that has the package installed in `vendor/easyengine/<pkg>`, the same way the Behat suites do. The package's `tests/phpunit/bootstrap.php` loads this bootstrap through `EE_ROOT`:

```bash
php -d auto_prepend_file=tests/phpunit/prepend.php vendor/bin/phpunit -c ../site-command/phpunit.xml.dist
```

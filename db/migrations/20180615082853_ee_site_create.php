<?php


use Phinx\Migration\AbstractMigration;

class EeSiteCreate extends AbstractMigration
{
    /**
     * Change Method.
     *
     * Write your reversible migrations using this method.
     *
     * More information on writing migrations is available here:
     * http://docs.phinx.org/en/latest/migrations.html#the-abstractmigration-class
     *
     * The following commands can be used in this method and Phinx will
     * automatically reverse them when rolling back:
     *
     *    createTable
     *    renameTable
     *    addColumn
     *    addCustomColumn
     *    renameColumn
     *    addIndex
     *    addForeignKey
     *
     * Any other distructive changes will result in an error when trying to
     * rollback the migration.
     */
    public function change()
    {
        $sites = $this->table('sites');
        $sites->addColumn('sitename', 'string', ['limit' => 255])
              ->addColumn('site_type', 'string', ['limit' => 255])
              ->addColumn('site_title', 'string', ['limit' => 255])
              ->addColumn('proxy_type', 'string', ['limit' => 255])
              ->addColumn('cache_type', 'string', ['limit' => 255])
              ->addColumn('site_path', 'string', ['limit' => 255])
              ->addColumn('created_on', 'datetime')
              ->addColumn('is_enabled', 'boolean', ['default' => 1])
              ->addColumn('is_ssl', 'boolean', ['default' => 0])
              ->addColumn('storage_fs', 'string', ['limit' => 255])
              ->addColumn('storage_db', 'string', ['limit' => 255])
              ->addColumn('db_name', 'string', ['limit' => 255])
              ->addColumn('db_user', 'string', ['limit' => 255])
              ->addColumn('db_password', 'string', ['limit' => 255])
              ->addColumn('db_host', 'string', ['limit' => 255])
              ->addColumn('wp_user', 'string', ['limit' => 255])
              ->addColumn('wp_pass', 'string', ['limit' => 255])
              ->addColumn('email', 'string', ['limit' => 255])
              ->addColumn('php_version', 'string', ['limit' => 255])
              ->addIndex( ['sitename'], ['unique' => true])
              ->create();
    }
}

<?php


use Phinx\Migration\AbstractMigration;

class UpdateSitesAddColoumnTest extends AbstractMigration
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
        $sites->addColumn('lalalalala', 'string', ['limit' => 255])
              ->save();
    }
}

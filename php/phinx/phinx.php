<?php

return
[
    'paths' => [
        'migrations' => 'db/migrations',
        'seeds' => 'db/seeds'
    ],
    'environments' => [
        'default_migration_table' => 'phinxlog',
        'default_database' => 'development',
        'production' => [
            'adapter' => 'sqlite',
            'host' => 'localhost',
            'name' => 'ee',
            'user' => '',
            'pass' => '',
            'port' => '',
            'charset' => 'utf8',
        ],
    ],
    'version_order' => 'creation'
];
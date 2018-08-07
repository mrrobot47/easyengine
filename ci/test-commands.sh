#!/bin/bash

# called by Travis CI

for repo in "$(find vendor/easyengine -type d -name 'features')"; do
	rsync -a --delete $repo/ features
	sudo ./vendor/bin/behat 
done
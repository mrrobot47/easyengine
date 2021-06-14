#!/bin/bash
# called by GitHub actions

cd $GITHUB_WORKSPACE

set -x

#repos=$(find vendor/easyengine -type d -name 'features')
sub_commands=(
	vendor/easyengine/site-command/features
	vendor/easyengine/site-type-php/features
	vendor/easyengine/site-type-wp/features
)

for command in "${sub_commands[@]}"; do
	IFS='/' read -r -a array <<< "$command"
	rm -rf features/*
	rsync -av --delete $command/ features/ > /dev/null
	for file in features/*.feature; do mv "$file" "${file%.feature}_${array[2]}.feature"; done
	echo "Running tests for $command"
	export COMPOSE_INTERACTIVE_NO_CLI=1
	sudo -E ./vendor/bin/behat
done

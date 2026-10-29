default:
    @just --list

# Validate shell syntax and run shellcheck
check:
    bash -n package.sh scripts/check.sh
    shellcheck package.sh scripts/check.sh

# Build .alfredworkflow package
package:
    ./package.sh

# Local CI verification gate
ci: check package

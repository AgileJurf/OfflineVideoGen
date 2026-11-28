#!/bin/sh
set -eu
# Xcode Cloud resolves pinned Swift packages itself. Models are installed by the app,
# never fetched as an implicit side effect of ordinary build or simulator test actions.
cd "$CI_PRIMARY_REPOSITORY_PATH"
test -f LocalFrames.xcodeproj/project.pbxproj
test -f LocalFrames/Resources/neodragon-manifest.json
test -f LocalFrames.xcodeproj/xcshareddata/xcschemes/LocalFrames.xcscheme
git rev-parse HEAD > LocalFrames/Resources/build-revision.txt
printf '%s\n' 'Local Frames: build and app tests only; real-model and iPhone inference remain separate validation gates.'

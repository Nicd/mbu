# Change Log
All notable changes to this project will be documented in this file.

The format is roughly based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [1.0.1] - 2017-06-06

### Changed

- Reverted _fs_ version back to 2.12.0 because of compilation issues.

## [1.0.0] - 2017-06-03 (Unreleased)

### Changed

- Bumped _fs_ version to 3.4.0.

### Fixed

- Should now work on Windows, uses _cmd.exe_ to run _npm_'s batch scripts.

### Fixed

## [0.3.0] - 2017-04-30

### Added

- This changelog.

### Changed

- Applications returning an error status will now not crash the whole build. The error will be logged into
  the console and execution will resume as normal. Crashing the whole build was a problem
  when watching, because often you may save an intermediate file that will not parse and
  your watch build utility may return an error status.

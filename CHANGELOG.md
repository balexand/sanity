# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Changed
- (BREAKING) Switch HTTP client from `finch` to `req` (https://github.com/balexand/sanity/pull/81). This introduces the following breaking changes:
  - The `headers` field of the `Sanity.Response` now returns a map instead of a list of tuples. See https://hexdocs.pm/req/changelog.html#change-headers-to-be-maps for details.
  - The `:max_attempts` and `:retry_delay` options have been removed from `Sanity.request/2`. `Req` handles retries for us.
  - The `source` field in the `Sanity.Error` exception may now contain a `Req.Response` struct instead of a `Finch.Response`.

## [1.3.0] - 2023-07-19
### Changed
- Refactor and add `Sanity.query_to_query_params/3` (https://github.com/balexand/sanity/pull/73 and https://github.com/balexand/sanity/pull/75)

## [1.2.0] - 2023-07-03
### Added
- `Sanity.list_references/1` (https://github.com/balexand/sanity/pull/72)

## [1.1.2] - 2023-06-23
### Changed
- Fix Elixir 1.15 deprecation warnings (https://github.com/balexand/sanity/pull/71).

## [1.1.1] - 2023-03-11
### Changed
- Relax `nimble_options` version requirement

## [1.1.0] - 2023-01-11
### Changed
- Handle HTML error response (like 414 Request-URI Too Large) (https://github.com/balexand/sanity/pull/69)

## [1.0.0] - 2022-12-13
### Changed
- Configure nimble_options to ensure that `:variables` option for `Sanity.stream/1` is a map with string or atom keys. Requires nimble_options ~> 0.5.
- Bump version to 1.0.0 to indicate strict adherence to semantic versioning from this point on.

## [0.12.1] - 2022-11-18
### Changed
- Update warning log message.

## [0.12.0] - 2022-10-23
### Added
- `Sanity.stream/1`, failed request retry via the `:max_attempts` and `:retry_delay` options, and `%Response{status: _}` field ([#63](https://github.com/balexand/sanity/pull/63)).

### Changed
- Use `2021-10-21` as the default API version.

## [0.11.0] - 2022-07-23
### Changed
- BREAKING - Remove `Sanity.atomize_and_underscore/1` ([#57](https://github.com/balexand/sanity/pull/57))

## [0.10.0] - 2022-07-13
### Changed
- Fix bug in `Sanity.replace_references/2` when reference object doesn't have `_type` field

## [0.9.0] - 2022-07-13
### Added
- `Sanity.replace_references/2` ([#54](https://github.com/balexand/sanity/pull/54))

### Changed
- Increase default HTTP receive timeout to 30 seconds

## [0.8.1] - 2022-03-12
### Changed
- Fix doctest format

## [0.8.0] - 2022-03-12
### Added
- Add `Sanity.atomize_and_underscore/1` ([#48](https://github.com/balexand/sanity/pull/48))

## [0.7.0] - 2022-03-12
### Added
- Add `Sanity.result!/1` function ([#47](https://github.com/balexand/sanity/pull/47))

### Changed
- Run dialyzer on CI and update supported Elixir versions ([#46](https://github.com/balexand/sanity/pull/46))

## [0.6.1] - 2021-12-15
### Changed
- Relax version requirement for `nimble_options` dependency ([#37](https://github.com/balexand/sanity/pull/37))

## [0.6.0] - 2021-05-25
### Changed
- Drop `get_document` and `get_documents` functions ([#22](https://github.com/balexand/sanity/pull/22))
- Update matrix of supported Elixir/Erlang versions ([#21](https://github.com/balexand/sanity/pull/21))

## [0.5.0] - 2021-05-21
### Added
- Support asset uploads ([#20](https://github.com/balexand/sanity/pull/20))

## [0.4.0] - 2021-05-06
### Added
- Support API versions ([#18](https://github.com/balexand/sanity/pull/18))

## [0.3.0] - 2020-12-09
### Added
- Initial Release

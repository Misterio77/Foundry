# Knowledge tools

M3 adds bounded reference lookups without turning the plugin into a generic HTTP
proxy. Gameplay account state is never attached to outbound requests.

## `get_item_prices`

`get_item_prices` accepts 1–8 unique positive item IDs and returns each semantic
name plus RuneLite's current cached market-price estimate. It performs no outbound
request itself. The shared state/sample envelope remains present so callers can
distinguish a live client sample from a disconnected RuneLite process.

RuneLite's upstream price age is not exposed by `ItemManager`; values are therefore
estimates rather than quotes. GE and wealth tools retain their separate freshness
and partiality metadata.

## OSRS Wiki access

`search_osrs_wiki` and `get_osrs_wiki_page` appear only when **Enable OSRS Wiki
access** is enabled in RuneLite MCP settings. RuneLite displays a warning before
enabling it: requests send fixed MediaWiki operation/format parameters plus the
explicit query and result limit, or page title, to `oldschool.runescape.wiki`.
No player name, account state, location, inventory, or other gameplay data is
included. HTTP redirects are never followed; MediaWiki may resolve an in-wiki
page-title redirect within its JSON response.

The exact search query template is
`action=query&list=search&format=json&formatversion=2&srprop=wordcount|timestamp&srlimit=<limit>&srsearch=<encoded-query>`.
The page template is
`action=query&prop=extracts&explaintext=1&redirects=1&format=json&formatversion=2&titles=<encoded-title>`.
Both are GET requests with `Accept: application/json` and the documented project
User-Agent; user values are UTF-8 form-URL-encoded.

`search_osrs_wiki` accepts a 1–128 character query and returns at most ten page
titles with page ID, word count, and Wiki timestamp. `get_osrs_wiki_page` accepts
one 1–128 character title and returns plain text bounded to 1,000–50,000
characters (12,000 by default), with explicit truncation.

## Network behavior

- fixed upstream: `https://oldschool.runescape.wiki/api.php`;
- descriptive project User-Agent and JSON `Accept` header;
- three-second connect timeout, six-second end-to-end response deadline, and no
  HTTP redirects;
- one request per second process-local rate limit;
- one-MiB upstream response limit;
- 64-entry, ten-minute in-memory LRU cache;
- no retries, cookies, authentication, arbitrary URLs, filesystem cache, or
  background requests;
- source attribution and cache-hit status in every successful result.

Wiki I/O runs only on MCP HTTP workers. A concurrent second Wiki request fails
fast rather than occupying another worker; unrelated tools remain available.
Configuration changes affect discovery and enforcement immediately. This stateless
transport emits no `tools/list_changed` notification, so clients that cache tool
lists must refresh discovery after toggling Wiki access. Disabled Wiki tools are
neither advertised nor callable, and plugin shutdown cancels/invalidates in-flight
responses and discards the in-memory cache.

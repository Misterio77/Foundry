---
title: Latest Posts
description: My personal thoughts, rants, and occasional guide
permalink: /blog/index.html
has_gemini: true
---
[reference-link][1]

[1]: https://example.com "Exemplo"
{% assign posts = site.posts | where: "gemini", false | where: "draft", false %}
 <small>[Feed {% include icons/simple-icons/rss.svg %}](../feed.xml)</small>

{% for post in posts %}
## [{{ post.title }} ({{ post.language }})]({{ post.url }})

<small>{{ post.date | date: "%d/%m/%y" }}</small>

{{ post.excerpt }}
{% endfor %}

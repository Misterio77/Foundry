---
title: Latest Posts
description: My personal thoughts, rants, and occasional guide
permalink: /blog/index.html
has_gemini: true
---

{% assign posts = site.posts | where: "gemini", false | where: "draft", false %}
[Feed {% include icons/simple-icons/rss.svg %}](../feed.xml)

{% for post in posts %}
{:.posts}
- ## [{{ post.title }} ({{ post.language }})]({{ post.url }})

  {{ post.date | date: "%d/%m/%y" }}

  {{ post.excerpt }}
{% endfor %}

---
title: Personal notes
description: Personal wiki and digital garden, ordered by tags
permalink: /notes/index.html
has_gemini: true
---
{% assign notes = site.notes | where: "gemini", false | where: "draft", false %}

Not sure where to go? \\
[Start here](_notes/start-here.md)

{% assign tags = site.notes | map: 'tags' | uniq %}
{% for tag in tags %}
{:.posts}
- ## [{% if site.data.tags[tag] %}{{ site.data.tags[tag] }}{% else %}{{ tag }}{% endif %}](#{{ tag }})
  {:.anchor}

  {% assign notes = site.notes | where: "gemini", false %}
  {% for note in notes %}
  {:.posts}
  {% if note.tags contains tag %}
  - ### [{{ note.title }} ({{ note.language }})]({{ note.url }})

    {{ note.last_modified_at | date: "%d/%m/%y" }}
    {% if note.tags.size > 0 %}| {% for tag in note.tags %}[#{{ tag }}](#{{ tag }}) {% endfor %}{% endif %}

    {{ note.excerpt }}
  {% endif %}
  {% endfor %}
{% endfor %}

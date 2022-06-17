---
title: Personal notes
description: Personal wiki and digital garden
permalink: /notes/index.html
has_gemini: true
---
{% assign notes = site.notes | where: "gemini", false | where: "draft", false %}

{% assign tags = site.notes | map: 'tags' | uniq %}
{% for tag in tags %}
## [{% if site.data.tags[tag] %}{{ site.data.tags[tag] }}{% else %}{{ tag }}{% endif %}](#{{ tag }}){:#{{ tag }}}

{% assign notes = site.notes | where: "gemini", false %}
{% for note in notes %}
{% if note.tags contains tag %}
### [{{ note.title }} ({{ note.language }})]({{ note.url }})

<small>
{{ note.last_modified_at | date: "%d/%m/%y" }}
{% if note.tags.size > 0 %}| {% for tag in note.tags %}[#{{ tag }}](#{{ tag }}){% endfor %}{% endif %}
</small>

{{ note.excerpt }}
{% endif %}
{% endfor %}
{% endfor %}

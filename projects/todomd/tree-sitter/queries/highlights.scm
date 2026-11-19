(heading_marker) @punctuation.special
(heading_text) @markup.heading
(bullet) @markup.list
(unchecked) @punctuation.special
(checked) @comment
(comment) @comment

(list) @label.todomd.list
(start) @string.special.todomd.start
(due) @constant.numeric.todomd.due
(priority_low) @attribute.todomd.priority.low
(priority_medium) @attribute.todomd.priority.medium
(priority_high) @attribute.todomd.priority.high
(categories) @type.todomd.categories
(summary) @markup.normal
(quoted_summary) @markup.normal

; Only a trailing identity has meaning; identity-shaped prose stays prose.
((summary (word) @comment.todomd.identity .)
 (#match? @comment.todomd.identity "^<!--t[0-9]+-->$"))
(task (identity) @comment.todomd.identity)

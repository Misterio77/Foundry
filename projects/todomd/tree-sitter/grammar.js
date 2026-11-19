module.exports = grammar({
  name: "todomd",

  extras: () => [],

  rules: {
    document: ($) => seq(
      repeat(choice(seq($._line, $._newline), $._newline)),
      optional($._line),
    ),

    _line: ($) => choice($.heading, $.task, $.comment),
    comment: () => /<!--[^\r\n]*-->/,
    _newline: () => /\r?\n/,
    _space: () => / +/,

    heading: ($) => seq($.heading_marker, $._space, $.heading_text),
    heading_marker: () => /#{1,6}/,
    heading_text: () => /[^\r\n]+/,

    task: ($) => seq(
      optional($._space),
      $.bullet,
      $._space,
      choice($.unchecked, $.checked),
      $._space,
      repeat(seq($._field, $._space)),
      choice(
        $.summary,
        seq($.quoted_summary, optional(seq($._space, $.identity))),
      ),
    ),
    bullet: () => "-",
    unchecked: () => "[ ]",
    checked: () => "[x]",

    _field: ($) => choice(
      $.list,
      $.start,
      $.due,
      $.priority_low,
      $.priority_medium,
      $.priority_high,
      $.categories,
    ),
    list: ($) => seq("@", $._value),
    start: ($) => seq("+", $._value),
    due: ($) => seq("-", $._value),
    priority_low: () => "!",
    priority_medium: () => "!!",
    priority_high: () => "!!!",
    _value: ($) => choice($._quoted_value, /[^ "\r\n]+/),
    _quoted_value: () => /"([^"\r\n]|"")*"/,

    categories: ($) => seq(
      "[",
      optional($._space),
      $.category,
      repeat(seq(",", optional($._space), $.category)),
      optional($._space),
      "]",
    ),
    category: ($) => choice($._quoted_value, /[^ ,\[\]"\r\n]+/),

    // After the first summary word, field-shaped text is ordinary prose.
    summary: ($) => seq(
      alias(/[^!+@\-\[" \r\n][^ \r\n]*/, $.word),
      repeat(seq($._space, $.word)),
    ),
    word: () => /[^ \r\n]+/,
    quoted_summary: ($) => $._quoted_value,
    identity: () => token(prec(1, /<!--t[0-9]+-->/)),
  },
});

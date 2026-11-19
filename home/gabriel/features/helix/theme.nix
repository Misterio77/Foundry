{colorscheme}: let
  c = colorscheme.colors;
in {
  "attributes" = c.orange;
  "comment" = {
    fg = c.on_surface_variant;
    modifiers = ["italic"];
  };
  "constant" = c.orange;
  "constant.character.escape" = c.cyan;
  "constant.numeric" = c.orange;
  "constructor" = c.blue;
  "debug" = c.on_surface_variant;
  "diagnostic" = {
    modifiers = ["underlined"];
  };
  "diagnostic.error" = {
    underline = {
      style = "curl";
    };
  };
  "diagnostic.hint" = {
    underline = {
      style = "curl";
    };
  };
  "diagnostic.info" = {
    underline = {
      style = "curl";
    };
  };
  "diagnostic.warning" = {
    underline = {
      style = "curl";
    };
  };
  "diff.delta" = c.orange;
  "diff.minus" = c.red;
  "diff.plus" = c.green;
  "error" = c.red;
  "function" = c.blue;
  "hint" = c.on_surface_variant;
  "info" = c.blue;
  "keyword" = c.magenta;
  "label" = c.magenta;
  "label.todomd.list" = c.magenta;
  "string.special.todomd.start" = c.cyan;
  "constant.numeric.todomd.due" = c.orange;
  "attribute.todomd.priority.low" = c.yellow;
  "attribute.todomd.priority.medium" = c.orange;
  "attribute.todomd.priority.high" = c.red;
  "type.todomd.categories" = c.blue;
  "comment.todomd.identity" = c.on_surface_variant;
  "markup.bold" = {
    fg = c.yellow;
    modifiers = ["bold"];
  };
  "markup.heading" = c.blue;
  "markup.italic" = {
    fg = c.magenta;
    modifiers = ["italic"];
  };
  "markup.link.text" = c.red;
  "markup.link.url" = {
    fg = c.orange;
    modifiers = ["underlined"];
  };
  "markup.list" = c.red;
  "markup.quote" = c.cyan;
  "markup.raw" = c.green;
  "markup.strikethrough" = {
    modifiers = ["crossed_out"];
  };
  "namespace" = c.magenta;
  "operator" = c.on_surface;
  "special" = c.blue;
  "string" = c.green;
  "type" = c.yellow;
  "ui.background" = {
    bg = c.surface;
  };
  "ui.bufferline" = {
    fg = c.on_primary_container;
    bg = c.primary_container;
  };
  "ui.bufferline.active" = {
    fg = c.surface;
    bg = c.on_surface_variant;
    modifiers = ["bold"];
  };
  "ui.cursor" = {
    fg = c.on_primary_container;
    modifiers = ["reversed"];
  };
  "ui.cursor.insert" = {
    fg = c.yellow;
    modifiers = ["underlined"];
  };
  "ui.cursor.match" = {
    fg = c.yellow;
    modifiers = ["underlined"];
  };
  "ui.cursor.select" = {
    fg = c.yellow;
    modifiers = ["underlined"];
  };
  "ui.cursorline.primary" = {
    fg = c.on_secondary_container;
    bg = c.secondary_container;
  };
  "ui.gutter" = {
    bg = c.surface;
  };
  "ui.help" = {
    fg = c.on_secondary_container;
    bg = c.secondary_container;
  };
  "ui.linenr" = {
    fg = c.on_surface_variant;
    bg = c.surface;
  };
  "ui.linenr.selected" = {
    fg = c.on_primary_container;
    bg = c.secondary_container;
    modifiers = ["bold"];
  };
  "ui.menu" = {
    fg = c.on_surface;
    bg = c.secondary_container;
  };
  "ui.menu.scroll" = {
    fg = c.on_surface_variant;
    bg = c.secondary_container;
  };
  "ui.menu.selected" = {
    fg = c.secondary_container;
    bg = c.on_primary_container;
  };
  "ui.popup" = {
    bg = c.secondary_container;
  };
  "ui.selection" = {
    bg = c.primary_container;
    fg = c.on_primary_container;
  };
  "ui.selection.primary" = {
    bg = c.primary_container;
    fg = c.on_primary_container;
  };
  "ui.statusline" = {
    fg = c.primary_fixed;
    bg = c.on_primary_fixed;
  };
  "ui.statusline.inactive" = {
    bg = c.surface_variant;
    fg = c.on_surface_variant;
  };
  "ui.statusline.insert" = {
    fg = c.surface;
    bg = c.green;
  };
  "ui.statusline.normal" = {
    fg = c.on_primary;
    bg = c.primary;
  };
  "ui.statusline.select" = {
    fg = c.surface;
    bg = c.magenta;
  };
  "ui.text" = c.on_surface;
  "ui.text.focus" = c.on_surface;
  "ui.virtual.inlay-hint" = {
    fg = c.on_surface_variant;
  };
  "ui.virtual.indent-guide" = {
    fg = c.inverse_on_surface;
  };
  "ui.virtual.ruler" = {
    bg = c.secondary_container;
  };
  "ui.virtual.whitespace" = {
    fg = c.secondary_container;
  };
  "ui.window" = {
    bg = c.secondary_container;
  };
  "variable" = c.red;
  "variable.other.member" = c.red;
  "warning" = c.orange;
}

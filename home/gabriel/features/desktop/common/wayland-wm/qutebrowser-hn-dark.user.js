// ==UserScript==
// @name         HN dark
// @namespace    local.gabs/hn-dark
// @version      1
// @description  Dark palette for Hacker News, only when prefers-color-scheme is dark.
// @match        *://news.ycombinator.com/*
// @run-at       document-start
// @noframes
// @grant        none
// ==/UserScript==

(function () {
  const css = `
  @media (prefers-color-scheme: dark) {
    html { color-scheme: dark !important; }
    html, body { background-color: #0e0e10 !important; }
    #hnmain { background-color: #19191d !important; }

    a:link, .c00, .c00 a:link, .admin, .admin td, .commtext { color: #d6d6d6 !important; }
    a:visited, .subtext a:link, .subtext a:visited, .comhead a:link,
    .hnmore a:link, .yclinks a:link, .yclinks a:visited { color: #7f7f7f !important; }

    /* the orange top bar keeps dark text on orange */
    .pagetop a:link, .pagetop a:visited { color: #1a1a1a !important; }
    .topsel a:link, .topsel a:visited { color: #ffffff !important; }

    input, textarea { background-color: #232327 !important; color: #d6d6d6 !important; }
    input[readonly] { background-color: #19191d !important; color: #8a8a8a !important; }
    input[type="submit"] { color: #d6d6d6 !important; }
  }`;

  const style = document.createElement('style');
  style.textContent = css;

  if (document.documentElement) {
    document.documentElement.append(style);
  } else {
    new MutationObserver((_, obs) => {
      if (document.documentElement) {
        obs.disconnect();
        document.documentElement.append(style);
      }
    }).observe(document, { childList: true });
  }
})();

(function () {
  'use strict';

  const ENTITIES = Object.freeze({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;'
  });

  function escapeHTML(value) {
    return String(value == null ? '' : value).replace(/[&<>"']/g, char => ENTITIES[char]);
  }

  window.SirFisherDOM = Object.freeze({ escapeHTML });
})();

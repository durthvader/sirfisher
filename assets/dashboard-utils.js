(function () {
  'use strict';

  function brl(value) {
    const number = Number(value);
    if (value == null || Number.isNaN(number)) return '—';
    const absolute = Math.abs(number);
    if (absolute >= 1e6) return `R$ ${(number / 1e6).toFixed(2).replace('.', ',')} mi`;
    if (absolute >= 1e3) return `R$ ${(number / 1e3).toFixed(1).replace('.', ',')} mil`;
    return `R$ ${number.toFixed(0)}`;
  }

  function brl0(value) {
    const number = Number(value);
    if (value == null || Number.isNaN(number)) return '—';
    const absolute = Math.abs(number);
    if (absolute >= 1e6) return `R$ ${(number / 1e6).toFixed(1).replace('.', ',')} mi`;
    if (absolute >= 1e3) return `R$ ${Math.round(number / 1e3)} mil`;
    return `R$ ${number.toFixed(0)}`;
  }

  function pct(value) {
    const number = Number(value);
    return value == null || Number.isNaN(number)
      ? '—'
      : `${number.toFixed(1).replace('.', ',')}%`;
  }

  function rs(value) {
    return value == null ? '—' : `R$ ${Number(value).toFixed(2).replace('.', ',')}`;
  }

  window.SirFisherFormat = Object.freeze({ brl, brl0, pct, rs });
})();

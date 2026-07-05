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

  // Usa a tendencia de faturamento ja calculada pelo banco como medida de
  // quanto do mes em andamento esta coberto. Em meses fechados, realizado e
  // projetado sao iguais e o fator permanece 1.
  function monthTrend(summaryRows, anoMes) {
    const row = (summaryRows || []).find(item => item.ano_mes === anoMes);
    const actual = row && row.faturamento != null ? Number(row.faturamento) : null;
    const projected = row && row.faturamento_proj != null ? Number(row.faturamento_proj) : null;
    const valid = Number.isFinite(actual) && actual > 0 && Number.isFinite(projected) && projected > 0;
    const factor = valid ? projected / actual : 1;
    const active = valid && projected > actual + 0.5;

    return Object.freeze({
      active,
      actual,
      projected,
      factor: active ? factor : 1,
      value(value) {
        if (value == null || !Number.isFinite(Number(value))) return null;
        return Number(value) * (active ? factor : 1);
      },
      label(closedLabel, trendLabel) {
        return active ? trendLabel : closedLabel;
      }
    });
  }

  window.SirFisherFormat = Object.freeze({ brl, brl0, pct, rs, monthTrend });
})();

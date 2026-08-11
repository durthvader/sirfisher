(function () {
  'use strict';

  const fallback = Object.freeze({ nome: 'Painel', subtitulo: 'Painel de Gestão' });
  let current = fallback;

  function normalized(row) {
    const nome = String(row?.nome || '').trim();
    const subtitulo = String(row?.subtitulo || '').trim();
    return Object.freeze({
      nome: nome || fallback.nome,
      subtitulo: subtitulo || fallback.subtitulo
    });
  }

  function apply() {
    document.querySelectorAll('[data-app-nome], header .brand h1').forEach((element) => {
      element.textContent = current.nome;
    });
    document.querySelectorAll('[data-app-subtitulo]').forEach((element) => {
      element.textContent = current.subtitulo;
    });
    const separator = document.title.indexOf(' · ');
    document.title = current.nome + (separator >= 0 ? document.title.slice(separator) : '');
  }

  async function load() {
    const client = window.SirFisherSupabase;
    if (client) {
      const { data, error } = await client.rpc('app_configuracao_empresa');
      const row = Array.isArray(data) ? data[0] : data;
      if (!error && row) current = normalized(row);
    }
    apply();
    return current;
  }

  const ready = load();
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', apply, { once: true });
  } else {
    apply();
  }

  window.SirFisherApp = Object.freeze({
    ready,
    current: () => current,
    reload: load
  });
})();

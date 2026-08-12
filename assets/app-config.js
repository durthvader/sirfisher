(function () {
  'use strict';

  const fallback = Object.freeze({ nome: 'Painel', subtitulo: 'Painel de Gestão' });
  const CACHE_KEY = 'finance_panel_config_v1';
  const CACHE_TTL_MS = 5 * 60 * 1000;
  const settingsFallback = Object.freeze({
    unidade: 'PRINCIPAL',
    unidadeCodigo: 'PRINCIPAL',
    alerta_cmv_vermelho: 38,
    alerta_pessoal_vermelho: 30,
    meta_proxima_perc: 90,
    meta_atingida_perc: 100,
    concentracao_fornecedor_ambar: 60,
    concentracao_fornecedor_vermelho: 66,
    vazamento_novo_valor: 3000,
    vazamento_aumento_perc: 35,
    vazamento_excesso_valor: 1500,
    vazamento_meses_base: 2,
    caixa_saldo_minimo: 100000,
    caixa_dias_critico: 30,
    caixa_dias_atencao: 60,
    caixa_horizonte_dias: 90,
    conciliacao_tolerancia_valor: 0.01,
    conciliacao_janela_dias: 5,
    estorno_forte_minutos: 60,
    dre_cmv_referencia_min: 28,
    dre_cmv_referencia_max: 35,
    dre_pessoal_referencia_min: 25,
    dre_pessoal_referencia_max: 35,
    dre_prime_cost_referencia_min: 55,
    dre_prime_cost_referencia_max: 65
  });
  let current = fallback;
  let settings = settingsFallback;
  let cachedAt = 0;

  function restoreCache() {
    try {
      const cached = JSON.parse(sessionStorage.getItem(CACHE_KEY) || 'null');
      if (!cached || typeof cached !== 'object') return;
      const nome = String(cached.current?.nome || '').trim();
      const subtitulo = String(cached.current?.subtitulo || '').trim();
      if (nome && subtitulo) current = Object.freeze({ nome, subtitulo });
      if (cached.settings && typeof cached.settings === 'object') {
        settings = Object.freeze(Object.assign({}, settingsFallback, cached.settings));
      }
      cachedAt = Number(cached.savedAt) || 0;
    } catch (_error) {
      // sessionStorage pode estar desabilitado; a configuracao remota segue normal.
    }
  }

  function saveCache() {
    try {
      cachedAt = Date.now();
      sessionStorage.setItem(CACHE_KEY, JSON.stringify({
        savedAt: cachedAt,
        current,
        settings
      }));
    } catch (_error) {
      // Cache e apenas uma otimizacao.
    }
  }

  restoreCache();

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
    document.querySelectorAll('[data-app-unidade]').forEach((element) => {
      element.textContent = settings.unidade;
    });
    const separator = document.title.indexOf(' · ');
    document.title = current.nome + (separator >= 0 ? document.title.slice(separator) : '');
  }

  async function load(force) {
    if (!force && cachedAt && Date.now() - cachedAt < CACHE_TTL_MS) {
      apply();
      return current;
    }
    if (force) {
      cachedAt = 0;
      try { sessionStorage.removeItem(CACHE_KEY); } catch (_error) {}
    }
    const client = window.SirFisherSupabase;
    if (client) {
      const settled = await Promise.allSettled([
        client.rpc('app_configuracao_empresa'),
        client.rpc('app_configuracao_operacional')
      ]);
      const empresa = settled[0].status === 'fulfilled'
        ? settled[0].value
        : { data: null, error: settled[0].reason };
      const operacional = settled[1].status === 'fulfilled'
        ? settled[1].value
        : { data: null, error: settled[1].reason };
      const row = Array.isArray(empresa.data) ? empresa.data[0] : empresa.data;
      if (!empresa.error && row) current = normalized(row);
      const op = Array.isArray(operacional.data) ? operacional.data[0] : operacional.data;
      if (!operacional.error && op) {
        const parametros = op.parametros && typeof op.parametros === 'object' ? op.parametros : {};
        settings = Object.freeze(Object.assign({}, settingsFallback, parametros, {
          unidade: String(op.unidade_nome || settingsFallback.unidade).trim() || settingsFallback.unidade,
          unidadeCodigo: String(op.unidade_codigo || settingsFallback.unidadeCodigo).trim() || settingsFallback.unidadeCodigo
        }));
      }
      if (!empresa.error && row && !operacional.error && op) saveCache();
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
    settings: () => settings,
    number: (key, fallbackValue) => {
      const value = Number(settings[key]);
      return Number.isFinite(value) ? value : fallbackValue;
    },
    reload: () => load(true)
  });
})();

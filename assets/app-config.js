(function () {
  'use strict';

  const fallback = Object.freeze({ nome: 'Painel', subtitulo: 'Painel de Gestão' });
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

  async function load() {
    const client = window.SirFisherSupabase;
    if (client) {
      const [empresa, operacional] = await Promise.all([
        client.rpc('app_configuracao_empresa'),
        client.rpc('app_configuracao_operacional')
      ]);
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
    reload: load
  });
})();

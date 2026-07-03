(function () {
  'use strict';

  const CONTROL_LABELS = Object.freeze({
    anoSel: 'Ano do período',
    mesSel: 'Mês do período',
    yearFilter: 'Ano do planejamento',
    userFilter: 'Buscar usuários',
    novaData: 'Data da venda em espécie',
    novoValor: 'Valor da venda em espécie'
  });

  const CHART_LABELS = Object.freeze({
    dia: 'Gráfico de faturamento diário',
    bars: 'Gráfico de faturamento por canal',
    donut: 'Gráfico de participação por canal',
    diario: 'Gráfico de evolução diária do faturamento',
    dow: 'Gráfico de faturamento por dia da semana',
    hora: 'Gráfico de faturamento por hora',
    contas: 'Gráfico de distribuição dos saldos por conta',
    curva: 'Gráfico de curva de saldo projetado',
    flow: 'Gráfico de fluxo de caixa diário',
    wf: 'Gráfico de composição do resultado',
    marg: 'Gráfico de evolução das margens',
    comp: 'Gráfico de composição das despesas',
    evo: 'Gráfico de evolução das despesas',
    conciliationChart: 'Gráfico de registros por situação da conciliação Stone',
    planningChart: 'Gráfico mensal de meta e faturamento realizado'
  });

  function matchesAndDescendants(root, selector) {
    const items = [];
    if (root.nodeType === Node.ELEMENT_NODE && root.matches(selector)) items.push(root);
    if (root.querySelectorAll) items.push(...root.querySelectorAll(selector));
    return items;
  }

  function contextLabel(control) {
    const row = control.closest('tr, .row');
    if (!row) return '';
    const name = row.querySelector('.nome, .data, td:first-child b, td:first-child');
    return name?.textContent?.trim().replace(/\s+/g, ' ') || '';
  }

  function annotate(root) {
    matchesAndDescendants(root, 'button').forEach(button => {
      if (!button.hasAttribute('type')) button.type = 'button';
    });

    matchesAndDescendants(root, 'select, input').forEach(control => {
      if (control.labels?.length || control.hasAttribute('aria-label') || control.hasAttribute('aria-labelledby')) return;
      const fixed = CONTROL_LABELS[control.id];
      const context = contextLabel(control);
      if (fixed) control.setAttribute('aria-label', fixed);
      else if (control.matches('select.role')) control.setAttribute('aria-label', `Papel de ${context || 'usuário'}`);
      else if (control.matches('select')) control.setAttribute('aria-label', `Categoria de ${context || 'lançamento'}`);
      else if (control.type === 'number') control.setAttribute('aria-label', `Valor de ${context || 'lançamento'}`);
      else control.setAttribute('aria-label', 'Campo de entrada');
    });

    matchesAndDescendants(root, 'canvas').forEach(canvas => {
      canvas.setAttribute('role', 'img');
      canvas.setAttribute('aria-label', CHART_LABELS[canvas.id] || 'Gráfico de indicadores financeiros');
    });

    matchesAndDescendants(root, 'table').forEach(table => {
      table.querySelectorAll('thead th').forEach(cell => cell.setAttribute('scope', 'col'));
      if (!table.hasAttribute('aria-label') && !table.hasAttribute('aria-labelledby')) {
        const panel = table.closest('.card, .panel');
        const heading = panel?.querySelector('h2, h3');
        table.setAttribute('aria-label', heading?.textContent?.trim() || 'Dados financeiros');
      }
    });

    matchesAndDescendants(root, 'svg').forEach(svg => {
      if (!svg.hasAttribute('role') && !svg.hasAttribute('aria-label')) {
        svg.setAttribute('aria-hidden', 'true');
        svg.setAttribute('focusable', 'false');
      }
    });

    matchesAndDescendants(root, '.loading, .state').forEach(status => {
      status.setAttribute('role', 'status');
      status.setAttribute('aria-live', 'polite');
      status.setAttribute('aria-atomic', 'true');
    });
    matchesAndDescendants(root, '.erro, .state.error').forEach(error => {
      error.setAttribute('role', 'alert');
      error.setAttribute('aria-live', 'assertive');
    });
    matchesAndDescendants(root, '.toast').forEach(toast => {
      toast.setAttribute('role', 'status');
      toast.setAttribute('aria-live', 'polite');
      toast.setAttribute('aria-atomic', 'true');
    });

    matchesAndDescendants(root, '.kpi-info').forEach(info => {
      if (info.dataset.a11yReady) return;
      info.dataset.a11yReady = 'true';
      info.setAttribute('role', 'button');
      info.tabIndex = 0;
      info.setAttribute('aria-label', `Explicação do indicador: ${info.dataset.desc || 'mais informações'}`);
      info.addEventListener('keydown', event => {
        if (event.key !== 'Enter' && event.key !== ' ') return;
        event.preventDefault();
        info.click();
      });
    });
  }

  function installSkipLink() {
    const main = document.querySelector('main, [role="main"], .wrap');
    if (!main) return;
    if (!main.id) main.id = 'main-content';
    main.tabIndex = -1;
    const link = document.createElement('a');
    link.className = 'sf-skip-link';
    link.href = `#${main.id}`;
    link.textContent = 'Pular para o conteúdo principal';
    link.addEventListener('click', () => window.setTimeout(() => main.focus(), 0));
    document.body.prepend(link);
  }

  function installNavigationSemantics() {
    document.querySelectorAll('nav').forEach(nav => nav.setAttribute('aria-label', 'Navegação principal'));
    document.querySelectorAll('nav a.active').forEach(link => link.setAttribute('aria-current', 'page'));
  }

  function installLoadHistoryDialog() {
    const dialog = document.getElementById('cargasBox');
    const open = document.getElementById('verCargas');
    const close = document.getElementById('fecharCargas');
    if (!dialog || !open || !close) return;

    dialog.setAttribute('role', 'dialog');
    dialog.setAttribute('aria-modal', 'true');
    dialog.setAttribute('aria-label', 'Histórico de cargas');
    dialog.setAttribute('aria-hidden', 'true');
    open.setAttribute('aria-haspopup', 'dialog');
    open.setAttribute('aria-controls', dialog.id);
    close.setAttribute('role', 'button');
    close.setAttribute('aria-label', 'Fechar histórico de cargas');
    close.tabIndex = 0;

    open.addEventListener('click', () => {
      dialog.setAttribute('aria-hidden', 'false');
      window.setTimeout(() => close.focus(), 0);
    });
    close.addEventListener('click', () => {
      dialog.setAttribute('aria-hidden', 'true');
      open.focus();
    });
    close.addEventListener('keydown', event => {
      if (event.key !== 'Enter' && event.key !== ' ') return;
      event.preventDefault();
      close.click();
    });
    dialog.addEventListener('keydown', event => {
      if (event.key === 'Escape') close.click();
    });
    dialog.addEventListener('click', event => {
      if (event.target !== dialog) return;
      dialog.setAttribute('aria-hidden', 'true');
      open.focus();
    });
  }

  document.addEventListener('DOMContentLoaded', () => {
    installSkipLink();
    installNavigationSemantics();
    installLoadHistoryDialog();
    annotate(document);
    const observer = new MutationObserver(records => {
      records.forEach(record => record.addedNodes.forEach(node => annotate(node)));
    });
    observer.observe(document.body, { childList: true, subtree: true });
  });
})();

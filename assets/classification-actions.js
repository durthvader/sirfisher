(function () {
  'use strict';

  let state = null;
  let undoTimer = null;

  function allowedCategories(categories, nature) {
    if (nature === 'Receita') {
      return categories.filter(item => ['Receita', 'Contabil', 'Ambos'].includes(item.natureza));
    }
    if (nature === 'Despesa') {
      return categories.filter(item => ['Despesa', 'Contabil', 'Ambos'].includes(item.natureza));
    }
    return categories;
  }

  function formatDateTime(value) {
    if (!value) return '';
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return '';
    return date.toLocaleString('pt-BR', {
      day: '2-digit', month: '2-digit', year: 'numeric',
      hour: '2-digit', minute: '2-digit'
    });
  }

  function formatMoney(value) {
    if (value == null) return '';
    return Number(value).toLocaleString('pt-BR', {
      style: 'currency', currency: 'BRL'
    });
  }

  function notify(message, error) {
    if (state && state.notify) state.notify(message, error);
  }

  async function changed() {
    if (state && state.onChanged) await state.onChanged();
    await refresh();
  }

  async function undo(item) {
    const { error } = await state.sb.rpc('desfazer_classificacao', {
      p_tipo: item.tipo,
      p_id: item.id
    });
    if (error) {
      notify('Não foi possível desfazer: ' + error.message, true);
      return false;
    }
    notify('Classificação desfeita.');
    await changed();
    return true;
  }

  function render(items, categories) {
    const target = state.target;
    if (!items.length) {
      target.innerHTML = '<div class="empty">Nenhuma classificação recente.</div>';
      return;
    }

    target.innerHTML = '<div class="classification-list">' + items.map(item => {
      const options = allowedCategories(categories, item.natureza).map(category =>
        '<option value="' + state.escape(category.categoria) + '"' +
        (category.categoria === item.categoria ? ' selected' : '') + '>' +
        state.escape(category.categoria) + ' · ' + state.escape(category.dre_grupo) + '</option>'
      ).join('');
      const meta = [
        item.tipo === 'excecao' ? 'Regra de fornecedor' : 'Transação individual',
        item.data_lancamento ? new Date(item.data_lancamento + 'T00:00:00').toLocaleDateString('pt-BR') : '',
        item.valor == null ? '' : formatMoney(item.valor),
        formatDateTime(item.quando)
      ].filter(Boolean).join(' · ');
      return '<div class="classification-row" data-type="' + state.escape(item.tipo) + '" data-id="' + Number(item.id) + '">' +
        '<div class="classification-info"><strong>' + state.escape(item.titulo || '(sem identificação)') + '</strong>' +
        '<span>' + state.escape(meta) + '</span></div>' +
        '<div class="classification-controls"><select class="field">' + options + '</select>' +
        '<button class="button correct" type="button">Corrigir</button>' +
        '<button class="button danger undo" type="button">Desfazer</button></div></div>';
    }).join('') + '</div>';

    target.querySelectorAll('.classification-row').forEach((row, index) => {
      const item = items[index];
      const select = row.querySelector('select');
      const correctButton = row.querySelector('button.correct');
      const undoButton = row.querySelector('button.undo');

      select.addEventListener('change', () => {
        correctButton.disabled = select.value === item.categoria;
      });
      correctButton.disabled = true;

      correctButton.addEventListener('click', async () => {
        correctButton.disabled = true;
        undoButton.disabled = true;
        const { error } = await state.sb.rpc('corrigir_classificacao', {
          p_tipo: item.tipo,
          p_id: item.id,
          p_categoria: select.value
        });
        if (error) {
          notify('Não foi possível corrigir: ' + error.message, true);
          undoButton.disabled = false;
          correctButton.disabled = false;
          return;
        }
        notify('Classificação corrigida para ' + select.value + '.');
        await changed();
      });

      undoButton.addEventListener('click', async () => {
        correctButton.disabled = true;
        undoButton.disabled = true;
        if (!await undo(item)) {
          correctButton.disabled = select.value === item.categoria;
          undoButton.disabled = false;
        }
      });
    });
  }

  async function refresh() {
    if (!state) return;
    state.target.innerHTML = '<div class="loading">Carregando classificações recentes…</div>';
    let recentQuery = state.sb.from('app_classificacoes_recentes').select('*');
    if (state.filterType) recentQuery = recentQuery.eq('tipo', state.filterType);
    recentQuery = recentQuery.order('quando', { ascending: false }).limit(20);
    const [recentResult, categoryResult] = await Promise.all([
      recentQuery,
      state.sb.from('app_categoria_dre').select('categoria, dre_grupo, natureza').order('categoria')
    ]);
    const error = recentResult.error || categoryResult.error;
    if (error) {
      state.target.innerHTML = '<div class="erro">Não foi possível carregar as classificações recentes: ' + state.escape(error.message) + '</div>';
      return;
    }
    render(recentResult.data || [], categoryResult.data || []);
  }

  function init(options) {
    state = {
      sb: options.sb,
      target: document.getElementById(options.targetId),
      escape: options.escape,
      notify: options.notify,
      onChanged: options.onChanged,
      filterType: options.filterType || null
    };
    refresh();
  }

  function offerUndo(item) {
    if (!state) return;
    let bar = document.getElementById('classificationUndo');
    if (!bar) {
      bar = document.createElement('div');
      bar.id = 'classificationUndo';
      bar.className = 'classification-undo';
      document.body.appendChild(bar);
    }
    clearTimeout(undoTimer);
    bar.innerHTML = '<span>' + state.escape(item.message || 'Classificação salva.') + '</span><button type="button">Desfazer</button>';
    bar.classList.add('show');
    const button = bar.querySelector('button');
    button.addEventListener('click', async () => {
      button.disabled = true;
      if (await undo(item)) bar.classList.remove('show');
      else button.disabled = false;
    });
    undoTimer = setTimeout(() => bar.classList.remove('show'), 8000);
  }

  window.SirFisherClassifications = Object.freeze({ init, refresh, offerUndo });
})();

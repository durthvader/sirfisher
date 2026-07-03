(function () {
  'use strict';

  const DASHBOARD_PAGES = new Set([
    'index.html',
    'vendas.html',
    'caixa.html',
    'dre.html',
    'despesas.html'
  ]);
  const OPERATION_PAGES = new Set([
    'analise_individual.html',
    'classificar_excecoes.html',
    'venda_especie.html'
  ]);
  const NEXT_KEY = 'sirfisher_auth_next';

  function currentPage() {
    const page = window.location.pathname.split('/').pop();
    return page || 'index.html';
  }

  function injectStyles() {
    if (document.getElementById('sirfisher-auth-style')) return;
    const style = document.createElement('style');
    style.id = 'sirfisher-auth-style';
    style.textContent = `
      .sf-auth-card{max-width:430px;margin:52px auto;padding:28px;background:#fff;border:1px solid #e5e7eb;border-radius:16px;box-shadow:0 14px 40px rgba(18,49,63,.10);text-align:center;color:#1f2933;font-family:Roboto,Arial,sans-serif}
      .sf-auth-mark{width:48px;height:48px;margin:0 auto 14px;border-radius:12px;background:#00a6a6;color:#fff;display:flex;align-items:center;justify-content:center;font-size:24px;font-weight:700}
      .sf-auth-card h2{font-size:21px;margin:0 0 8px}.sf-auth-card p{font-size:13px;line-height:1.55;color:#6b7280;margin:0 0 18px}
      .sf-auth-google{width:100%;border:1px solid #d1d5db;border-radius:10px;background:#fff;color:#1f2933;padding:11px 16px;font:600 14px Roboto,Arial,sans-serif;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:10px}
      .sf-auth-google:hover{background:#f7f5ef}.sf-auth-google:disabled{opacity:.55;cursor:wait}.sf-auth-g{font:700 18px Arial;color:#4285f4}
      .sf-auth-error{display:none;margin-top:12px!important;color:#c94c4c!important}.sf-auth-actions{display:flex;gap:9px;justify-content:center;flex-wrap:wrap;margin-top:16px}
      .sf-auth-link{display:inline-flex;align-items:center;text-decoration:none;border-radius:9px;padding:9px 12px;background:#12313f;color:#fff;font-size:12px;font-weight:600}
      .sf-auth-link.secondary{background:#f7f5ef;color:#12313f;border:1px solid #e5e7eb}
      .sf-session{position:fixed;right:12px;bottom:12px;z-index:80;background:#12313f;color:#fff;border:1px solid rgba(255,255,255,.16);border-radius:12px;padding:8px 10px;box-shadow:0 6px 24px rgba(0,0,0,.18);display:flex;align-items:center;gap:8px;font:500 11px Roboto,Arial,sans-serif}
      .sf-session strong{font-weight:700}.sf-session button,.sf-session a{border:0;background:rgba(255,255,255,.12);color:#fff;border-radius:7px;padding:5px 7px;text-decoration:none;font:600 10px Roboto,Arial,sans-serif;cursor:pointer}
      @media(max-width:520px){.sf-auth-card{margin:28px 4px;padding:23px 18px}.sf-session{left:8px;right:8px;bottom:8px;justify-content:center}}
    `;
    document.head.appendChild(style);
  }

  function mainContainer() {
    return document.getElementById('main') || document.getElementById('content') || document.querySelector('.wrap');
  }

  function clearContainer() {
    const target = mainContainer();
    if (target) target.replaceChildren();
    return target;
  }

  function authCard(title, message) {
    const target = clearContainer();
    if (!target) return null;
    const card = document.createElement('section');
    card.className = 'sf-auth-card';
    const mark = document.createElement('div');
    mark.className = 'sf-auth-mark';
    mark.textContent = 'S';
    const heading = document.createElement('h2');
    heading.textContent = title;
    const text = document.createElement('p');
    text.textContent = message;
    card.append(mark, heading, text);
    target.appendChild(card);
    return card;
  }

  function safeNext(value) {
    if (!value) return null;
    const page = value.split(/[?#]/, 1)[0];
    return DASHBOARD_PAGES.has(page) || OPERATION_PAGES.has(page) ? page : null;
  }

  function rememberNext(page) {
    const safe = safeNext(page);
    if (safe && safe !== 'index.html') sessionStorage.setItem(NEXT_KEY, safe);
  }

  function consumeNext(role) {
    const next = safeNext(sessionStorage.getItem(NEXT_KEY));
    sessionStorage.removeItem(NEXT_KEY);
    if (!next) return false;
    const allowed = role === 'gestor' || (role === 'operador' && OPERATION_PAGES.has(next));
    if (!allowed || next === currentPage()) return false;
    window.location.replace(next);
    return true;
  }

  function renderLogin(sb) {
    const card = authCard('Acesso ao painel', 'Entre com uma conta Google previamente autorizada para o Sir Fisher.');
    if (!card) return;
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'sf-auth-google';
    const g = document.createElement('span');
    g.className = 'sf-auth-g';
    g.textContent = 'G';
    const label = document.createElement('span');
    label.textContent = 'Continuar com Google';
    button.append(g, label);
    const error = document.createElement('p');
    error.className = 'sf-auth-error';
    card.append(button, error);

    button.addEventListener('click', async () => {
      button.disabled = true;
      error.style.display = 'none';
      const redirect = new URL('./', window.location.href);
      redirect.search = '';
      redirect.hash = '';
      const { error: oauthError } = await sb.auth.signInWithOAuth({
        provider: 'google',
        options: { redirectTo: redirect.href }
      });
      if (oauthError) {
        error.textContent = 'Não foi possível iniciar o login com Google. Verifique a configuração do provedor.';
        error.style.display = 'block';
        button.disabled = false;
      }
    });
  }

  function renderPending(sb) {
    const card = authCard('Acesso aguardando liberação', 'A conta Google foi autenticada, mas ainda não recebeu um papel no Sir Fisher. Peça a um gestor para liberar seu acesso.');
    if (!card) return;
    const actions = document.createElement('div');
    actions.className = 'sf-auth-actions';
    const logout = document.createElement('button');
    logout.type = 'button';
    logout.className = 'sf-auth-google';
    logout.textContent = 'Sair desta conta';
    logout.addEventListener('click', async () => {
      await sb.auth.signOut();
      window.location.replace('./');
    });
    actions.appendChild(logout);
    card.appendChild(actions);
  }

  function renderDenied(role) {
    const card = authCard('Acesso não permitido', role === 'operador'
      ? 'Seu perfil pode usar as rotinas operacionais, mas não visualizar os dashboards financeiros.'
      : 'Seu perfil não possui acesso a esta página.');
    if (!card) return;
    const home = document.createElement('a');
    home.className = 'sf-auth-link';
    home.href = './';
    home.textContent = 'Voltar ao início';
    const actions = document.createElement('div');
    actions.className = 'sf-auth-actions';
    actions.appendChild(home);
    card.appendChild(actions);
  }

  function renderOperatorHome() {
    const card = authCard('Rotinas operacionais', 'Escolha uma rotina. Indicadores financeiros são restritos ao papel gestor.');
    if (!card) return;
    const actions = document.createElement('div');
    actions.className = 'sf-auth-actions';
    [
      ['Classificar exceções', 'classificar_excecoes.html'],
      ['Análise individual', 'analise_individual.html'],
      ['Venda em espécie', 'venda_especie.html']
    ].forEach(([label, href]) => {
      const link = document.createElement('a');
      link.className = 'sf-auth-link';
      link.href = href;
      link.textContent = label;
      actions.appendChild(link);
    });
    card.appendChild(actions);
  }

  function installSessionBadge(sb, session, role) {
    if (document.getElementById('sf-session')) return;
    const box = document.createElement('div');
    box.className = 'sf-session';
    box.id = 'sf-session';
    const identity = document.createElement('span');
    const name = session.user.user_metadata?.full_name || session.user.email || 'Conta Google';
    identity.textContent = `${name} · `;
    const strong = document.createElement('strong');
    strong.textContent = role;
    identity.appendChild(strong);
    const home = document.createElement('a');
    home.href = './';
    home.textContent = 'Início';
    const logout = document.createElement('button');
    logout.type = 'button';
    logout.textContent = 'Sair';
    logout.addEventListener('click', async () => {
      sessionStorage.removeItem(NEXT_KEY);
      await sb.auth.signOut();
      window.location.replace('./');
    });
    box.append(identity, home, logout);
    document.body.appendChild(box);
  }

  async function requireRole(sb, allowedRoles, options) {
    injectStyles();
    const settings = options || {};
    const { data, error } = await sb.auth.getSession();
    const session = data?.session || null;

    if (error || !session) {
      if (settings.loginPage) {
        renderLogin(sb);
      } else {
        rememberNext(currentPage());
        window.location.replace('./');
      }
      return null;
    }

    const roleResult = await sb.rpc('papel_usuario_atual');
    const role = roleResult.error ? null : roleResult.data;
    if (!role) {
      if (!settings.loginPage) {
        window.location.replace('./');
        return null;
      }
      renderPending(sb);
      return null;
    }

    installSessionBadge(sb, session, role);
    if (settings.loginPage && consumeNext(role)) return null;

    if (!allowedRoles.includes(role)) {
      renderDenied(role);
      return null;
    }

    return { session, role };
  }

  window.SirFisherAuth = {
    requireRole,
    renderOperatorHome
  };
})();

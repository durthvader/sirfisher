(function () {
  'use strict';

  const ADMIN_ONLY_PAGES = new Set([
    'usuarios.html',
    'status.html',
    'permissoes.html'
  ]);
  const CONFIGURABLE_PAGES = new Set([
    'index.html',
    'vendas.html',
    'caixa.html',
    'dre.html',
    'despesas.html',
    'conciliacao.html',
    'planejamento.html',
    'rotinas.html',
    'analise_individual.html',
    'classificar_excecoes.html',
    'venda_especie.html',
    'gerente.html'
  ]);
  const KNOWN_PAGES = new Set([...ADMIN_ONLY_PAGES, ...CONFIGURABLE_PAGES]);
  const NEXT_KEY = 'sirfisher_auth_next';

  let permissionsPromise = null;
  function fetchPermissions(sb) {
    if (!permissionsPromise) {
      permissionsPromise = sb.from('pagina_permissao').select('pagina, papeis').then(({ data, error }) => {
        const map = new Map();
        if (!error) (data || []).forEach(row => map.set(row.pagina, new Set(row.papeis || [])));
        return map;
      });
    }
    return permissionsPromise;
  }

  async function pageAllowsRole(sb, pagina, role) {
    if (role === 'admin') return true;
    if (ADMIN_ONLY_PAGES.has(pagina)) return false;
    const permissions = await fetchPermissions(sb);
    const allowed = permissions.get(pagina);
    return allowed ? allowed.has(role) : false;
  }

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
      header .head-row .brand{margin-right:auto}
      .sf-acct{position:relative;flex-shrink:0}
      .sf-acct.sf-acct-float{position:fixed;top:10px;right:12px;z-index:120}
      .sf-acct-btn{display:inline-flex;align-items:center;gap:7px;border:1px solid rgba(255,255,255,.18);background:rgba(255,255,255,.08);color:#fff;border-radius:999px;padding:4px 10px 4px 4px;font:600 11px Roboto,Arial,sans-serif;line-height:1;cursor:pointer}
      .sf-acct-btn:hover,.sf-acct.open .sf-acct-btn{background:rgba(255,255,255,.16)}
      .sf-acct-av{width:26px;height:26px;border-radius:50%;background:var(--teal,#00a6a6);color:#fff;display:flex;align-items:center;justify-content:center;font:700 10.5px Roboto,Arial,sans-serif;flex-shrink:0}
      .sf-acct-role{text-transform:capitalize;letter-spacing:.2px}
      .sf-acct-caret{display:inline-block;width:0;height:0;border-left:4px solid transparent;border-right:4px solid transparent;border-top:5px solid rgba(255,255,255,.75);transition:transform .15s}
      .sf-acct.open .sf-acct-caret{transform:rotate(180deg)}
      .sf-acct-menu{position:absolute;top:calc(100% + 8px);right:0;z-index:130;min-width:214px;background:#12313f;border:1px solid rgba(255,255,255,.14);border-radius:12px;box-shadow:0 12px 34px rgba(0,0,0,.34);padding:7px;display:none;flex-direction:column;max-height:min(72vh,440px);overflow:auto}
      .sf-acct.open .sf-acct-menu{display:flex}
      .sf-acct-id{padding:7px 10px 9px;border-bottom:1px solid rgba(255,255,255,.1);margin-bottom:5px}
      .sf-acct-id b{display:block;color:#fff;font-size:12.5px;font-weight:700;word-break:break-word}
      .sf-acct-id span{font-size:10.5px;color:#8fb8ba;text-transform:capitalize}
      .sf-acct-menu a,.sf-acct-menu button{display:flex;align-items:center;width:100%;text-align:left;border:0;background:transparent;color:#eaf2f4;border-radius:8px;padding:8px 10px;font:600 12px Roboto,Arial,sans-serif;text-decoration:none;cursor:pointer}
      .sf-acct-menu a:hover,.sf-acct-menu button:hover{background:rgba(255,255,255,.1)}
      .sf-acct-sep{height:1px;background:rgba(255,255,255,.1);margin:5px 2px}
      .sf-acct-out{color:#ffb4b4}.sf-acct-out:hover{background:rgba(201,76,76,.22)}
      @media(max-width:520px){.sf-auth-card{margin:28px 4px;padding:23px 18px}.sf-acct-role{display:none}.sf-acct-btn{padding:4px}}
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
    return KNOWN_PAGES.has(page) ? page : null;
  }

  function rememberNext(page) {
    const safe = safeNext(page);
    if (safe && safe !== 'index.html') sessionStorage.setItem(NEXT_KEY, safe);
  }

  function consumeOAuthError() {
    const query = new URLSearchParams(window.location.search);
    const hash = new URLSearchParams(window.location.hash.replace(/^#/, ''));
    const code = query.get('error_code') || hash.get('error_code');
    const hasError = query.has('error') || hash.has('error');
    if (!hasError) return null;

    window.history.replaceState(null, '', window.location.pathname || './');
    if (code === 'unexpected_failure') {
      return 'O provedor Google respondeu, mas a sessão não foi criada. Verifique Client ID e Client Secret no Supabase.';
    }
    return 'O login com Google não foi concluído. Tente novamente ou peça a um administrador para revisar a configuração.';
  }

  async function consumeNext(sb, role) {
    const next = safeNext(sessionStorage.getItem(NEXT_KEY));
    sessionStorage.removeItem(NEXT_KEY);
    if (!next) return false;
    const allowed = await pageAllowsRole(sb, next, role);
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

    const oauthMessage = consumeOAuthError();
    if (oauthMessage) {
      error.textContent = oauthMessage;
      error.style.display = 'block';
    }

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
    const card = authCard('Acesso aguardando liberação', 'A conta Google foi autenticada, mas ainda não recebeu um papel no Sir Fisher. Peça a um administrador para liberar seu acesso.');
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
    const card = authCard('Acesso não permitido', role === 'gerente'
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

  function acctInitials(name) {
    const parts = String(name || '').trim().split(/\s+/).filter(Boolean);
    if (!parts.length) return '?';
    if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
  }

  // Paginas exclusivas de admin que aparecem no menu de conta. Para adicionar
  // uma nova (ex.: parametros.html) basta incluir uma linha aqui.
  const ADMIN_MENU_LINKS = [
    ['Status', 'status.html'],
    ['Usuários', 'usuarios.html'],
    ['Permissões', 'permissoes.html']
  ];

  function installSessionBadge(sb, session, role) {
    if (document.getElementById('sf-session')) return;
    const name = session.user.user_metadata?.full_name || session.user.email || 'Conta Google';

    const wrap = document.createElement('div');
    wrap.className = 'sf-acct';
    wrap.id = 'sf-session';

    // Gatilho compacto: avatar com iniciais + papel.
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'sf-acct-btn';
    btn.setAttribute('aria-haspopup', 'true');
    btn.setAttribute('aria-expanded', 'false');
    btn.setAttribute('aria-label', `Conta de ${name} (${role})`);
    const av = document.createElement('span');
    av.className = 'sf-acct-av';
    av.textContent = acctInitials(name);
    const roleEl = document.createElement('span');
    roleEl.className = 'sf-acct-role';
    roleEl.textContent = role;
    const caret = document.createElement('span');
    caret.className = 'sf-acct-caret';
    btn.append(av, roleEl, caret);

    // Menu vertical (escala para quantas paginas admin forem precisas).
    const menu = document.createElement('div');
    menu.className = 'sf-acct-menu';
    menu.setAttribute('role', 'menu');

    const id = document.createElement('div');
    id.className = 'sf-acct-id';
    const idName = document.createElement('b');
    idName.textContent = name;
    const idRole = document.createElement('span');
    idRole.textContent = role;
    id.append(idName, idRole);
    menu.appendChild(id);

    if (role === 'admin') {
      ADMIN_MENU_LINKS.forEach(([label, href]) => {
        const link = document.createElement('a');
        link.href = href;
        link.textContent = label;
        link.setAttribute('role', 'menuitem');
        menu.appendChild(link);
      });
      const sep = document.createElement('div');
      sep.className = 'sf-acct-sep';
      menu.appendChild(sep);
    }

    const home = document.createElement('a');
    home.href = './';
    home.textContent = 'Início';
    home.setAttribute('role', 'menuitem');
    menu.appendChild(home);

    const logout = document.createElement('button');
    logout.type = 'button';
    logout.className = 'sf-acct-out';
    logout.textContent = 'Sair';
    logout.setAttribute('role', 'menuitem');
    logout.addEventListener('click', async () => {
      sessionStorage.removeItem(NEXT_KEY);
      await sb.auth.signOut();
      window.location.replace('./');
    });
    menu.appendChild(logout);

    wrap.append(btn, menu);

    const setOpen = (open) => {
      wrap.classList.toggle('open', open);
      btn.setAttribute('aria-expanded', open ? 'true' : 'false');
    };
    btn.addEventListener('click', (event) => {
      event.stopPropagation();
      setOpen(!wrap.classList.contains('open'));
    });
    document.addEventListener('click', (event) => {
      if (!wrap.contains(event.target)) setOpen(false);
    });
    document.addEventListener('keydown', (event) => {
      if (event.key === 'Escape') setOpen(false);
    });

    // Ancora no topo-direito do cabecalho (longe do rodape). Sem cabecalho,
    // cai para um botao flutuante no topo.
    const headRow = document.querySelector('header .head-row');
    if (headRow) {
      headRow.appendChild(wrap);
    } else {
      wrap.classList.add('sf-acct-float');
      document.body.appendChild(wrap);
    }
  }

  async function pruneNav(sb, role) {
    const nav = document.querySelector('nav.tabs');
    if (!nav) return;
    const links = Array.from(nav.querySelectorAll('a[href]'));
    for (const a of links) {
      const href = a.getAttribute('href');
      const page = href === './' ? 'index.html' : href;
      if (!KNOWN_PAGES.has(page)) continue;
      const allowed = await pageAllowsRole(sb, page, role);
      if (!allowed) a.remove();
    }
    if (!nav.querySelector('a')) nav.style.display = 'none';
  }

  async function requireRole(sb, options) {
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
    await pruneNav(sb, role);
    if (settings.loginPage && await consumeNext(sb, role)) return null;

    const allowed = await pageAllowsRole(sb, currentPage(), role);
    if (!allowed) {
      // Na pagina de login, quem nao ve a visao geral vai para o painel
      // operacional em vez de uma tela de acesso negado.
      if (settings.loginPage && await pageAllowsRole(sb, 'gerente.html', role)) {
        window.location.replace('gerente.html');
        return null;
      }
      renderDenied(role);
      return null;
    }

    return { session, role };
  }

  window.SirFisherAuth = {
    requireRole,
    pageAllowsRole
  };
})();

# Acessibilidade

O front-end usa `assets/accessibility.css` e `assets/accessibility.js` como
camada compartilhada de acessibilidade, mantendo a hospedagem estática e sem
adicionar dependências.

## Recursos implementados

- link para pular diretamente ao conteúdo principal;
- foco visível para teclado;
- redução de animações conforme a preferência do sistema;
- nomes acessíveis para filtros, campos dinâmicos e gráficos;
- cabeçalhos e nomes acessíveis para tabelas;
- indicação da página atual na navegação;
- anúncios de carregamento, erro e confirmação para leitores de tela;
- acesso por teclado aos detalhes dos indicadores;
- semântica, foco e fechamento por `Esc` no histórico de cargas;
- ícones decorativos ocultos da árvore de acessibilidade.

O gate `scripts/ci/check_project.py` verifica a presença da camada compartilhada,
o idioma, viewport, título, conteúdo principal e ausência de supressão insegura
do foco em todas as páginas.

## Verificação manual recomendada

Após alterações visuais, percorrer cada fluxo apenas com `Tab`, `Shift+Tab`,
`Enter`, espaço e `Esc`, além de conferir zoom de 200% e larguras móveis. Os
fluxos autenticados devem ser testados com os papéis admin, gestor e operador.

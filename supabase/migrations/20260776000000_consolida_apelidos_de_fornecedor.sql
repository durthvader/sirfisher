-- =====================================================================
-- Consolida os apelidos de fornecedor do de_para
-- =====================================================================
--
-- PROBLEMA
--   O campo de_para.fornecedor e o rotulo que aparece nos relatorios.
--   Como cada chave nova era cadastrada a mao, o mesmo fornecedor acabou
--   gravado sob grafias diferentes -- e o relatorio quebra em varias
--   linhas o que deveria ser uma so.
--
--   Quatro casos distintos, tratados em blocos separados abaixo:
--
--   A) Colisao de caixa/acento: 13 fornecedores com duas ou tres grafias
--      que so diferem em maiuscula ou acento ("UBER"/"Uber"/"UBer",
--      "AMBEV"/"Ambev", "extra"/"Extra", "LAREDO"/"Laredo"...).
--
--   B) Contas do proprio grupo: as chaves de transferencia interna estao
--      sem padrao ("SIR FISHER - Imprensa", "Sir Fisher BB", "Sir.fisher")
--      e tres delas -- justamente as de maior volume -- estao com
--      fornecedor NULL, aparecendo em branco no relatorio:
--        BSINSTITUICAODEPAGAMENTOSA          R$ 392.206,84  (70 lanc.)
--        SIRFISHERPUBCOMERCIODEALIMENTOSLTDA R$  41.535,01  (12 lanc.)
--        35220527HEMILEALEXANDRESILVA        R$  28.100,00  ( 9 lanc.)
--      As tres nasceram da migration 20260767000000, que corrigiu a
--      categoria dessas chaves mas nao preencheu o rotulo.
--
--   C) Mesmo fornecedor sob nomes diferentes -- nao e questao de grafia,
--      e razao social contra nome comercial. O maior deles de longe:
--      "Crbs Sa Cdd Fortaleza" (309 lanc., R$ 457.402,19) e o centro de
--      distribuicao da Ambev; junto com as chaves ja rotuladas "Ambev"
--      passa a somar ~R$ 503 mil numa unica linha de Bebidas.
--
--   D) Fornecedor especifico absorvido no rotulo generico que o usuario
--      ja adota: 32 chaves de posto estao rotuladas "COMBUSTIVEL", mas
--      duas escaparam com o nome do posto. Mesma coisa em estacionamento.
--
-- CRITERIO DO ROTULO CANONICO (bloco A)
--   Inicial maiuscula, conectivo em minuscula ("da", "com"), acento
--   preservado. E a forma que a tela de classificacao ja gera por padrao
--   (`tituloCase` em classificar_excecoes.html), entao consolidar nessa
--   direcao evita a fragmentacao voltar: toda chave nova do mesmo
--   fornecedor -- e elas continuam aparecendo, Uber sozinho tem 26 --
--   nasce ja com a grafia canonica.
--
--   Duas excecoes deliberadas ao `tituloCase` puro, que e ingenuo e
--   capitaliza conectivo: "Daniel da Silva Oliveira" e "Vai com Peixe"
--   ficam com o conectivo em minuscula, como se escreve em portugues.
--
-- CRITERIO DO ROTULO CANONICO (bloco B)
--   Estende a convencao que o proprio usuario ja usava em duas chaves
--   ("SIR FISHER - Imprensa", "SIR FISHER - Praia"): `Sir Fisher - <conta>`.
--   Fica legivel e as contas do grupo passam a agrupar juntas no relatorio.
--
-- SEGURANCA DA MUDANCA
--   `fornecedor` e usado apenas como rotulo, em `fato_financeiro` (coluna
--   de saida) e em `app_classificacoes_recentes`. Nenhum join, filtro,
--   agrupamento ou soma depende dele -- a DRE agrupa por `categoria`.
--   Logo: nenhum valor muda, nenhum lancamento muda de categoria.
--
-- OBJETOS
--   ~ public.de_para (update de fornecedor em 85 linhas; nenhuma linha
--     criada ou removida)
--
-- VERIFICACAO (rodada em transacao revertida contra producao)
--   ~ 85 rotulos alterados; nos fornecedores tocados, 31 rotulos
--     distintos passam a 17
--   ~ nenhuma chave ativa fica sem apelido (eram 3)
--   ~ DRE identica linha a linha nas 62 linhas de (grupo, categoria):
--     mesma contagem e mesma soma antes e depois
--   ~ 2a execucao do arquivo nao altera nada (idempotente)
--
-- RISCO: baixo. Alteracao cosmetica e reversivel. Os quatro updates sao
--   idempotentes (`is distinct from` no where), entao reprocessar as
--   migrations do zero nao gera efeito duplicado.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Bloco A: grafias do mesmo fornecedor que so diferem em caixa/acento
-- ---------------------------------------------------------------------
-- Casa pela forma normalizada, entao pega todas as variantes de uma vez
-- e continua valendo se aparecer uma grafia nova no futuro.
update public.de_para d
set fornecedor = c.canonico,
    atualizado_em = now()
from (values
  ('alho descascado',          'Alho Descascado'),
  ('all mar',                  'All Mar'),
  ('ambev',                    'Ambev'),
  ('asa sul',                  'Asa Sul'),
  ('combustivel',              'Combustível'),
  ('daniel da silva oliveira', 'Daniel da Silva Oliveira'),
  ('estacionamento',           'Estacionamento'),
  ('extra',                    'Extra'),
  ('fardamento',               'Fardamento'),
  ('laredo',                   'Laredo'),
  ('uber',                     'Uber'),
  ('utensilios',               'Utensílios'),
  ('vai com peixe',            'Vai com Peixe')
) as c(norma, canonico)
where d.fornecedor is not null
  and lower(public.unaccent(btrim(d.fornecedor))) = c.norma
  and d.fornecedor is distinct from c.canonico;

-- ---------------------------------------------------------------------
-- Bloco B: contas do grupo -- preenche os NULL e padroniza a grafia
-- ---------------------------------------------------------------------
-- Casa pela chave exata: aqui o alvo e a conta, nao a grafia.
--
-- 35220527HEMILEALEXANDRESILVA e a conta Inter. Ela era registrada no
-- nome da Hemile mas pertencia a empresa -- e o mesmo criterio ja
-- aplicado na 20260767000000, que classificou essa chave como
-- transferencia interna (o CPF da Hemile continua sendo Folha Salarial,
-- em chave separada).
update public.de_para d
set fornecedor = c.rotulo,
    atualizado_em = now()
from (values
  ('35220527HEMILEALEXANDRESILVA',        'Sir Fisher - Inter'),
  ('BSINSTITUICAODEPAGAMENTOSA',          'BS Cash'),
  ('BSCASH',                              'BS Cash'),
  ('SIRFISHERPUBCOMERCIODEALIMENTOSLTDA', 'Sir Fisher - Pub'),
  ('SIRFISHERPUB',                        'Sir Fisher - Pub'),
  ('SIRFISHERBNB',                        'Sir Fisher - BNB'),
  ('SIRFISHERBB',                         'Sir Fisher - BB'),
  ('SIRFISHERIMPRENSA',                   'Sir Fisher - Imprensa'),
  ('SIRFISHERPRAIA',                      'Sir Fisher - Praia'),
  ('BARRASOLSIRFISHER',                   'Sir Fisher - Praia'),
  ('FUNDOPAYSA',                          'Fundopay'),
  -- Estas duas ficam sem o sufixo de conta de proposito: a primeira e a
  -- pessoa juridica, nao uma conta; a segunda vem do texto solto
  -- "SIR FISHER" no extrato, que nao diz qual conta e.
  ('SIRFISHERCOMERCIODEALIMENTOSLTDA',    'Sir Fisher Comércio de Alimentos'),
  ('SIRFISHER',                           'Sir Fisher')
) as c(chave, rotulo)
where d.chave_tipo = 'nome'
  and d.chave_valor = c.chave
  and d.fornecedor is distinct from c.rotulo;

-- ---------------------------------------------------------------------
-- Bloco C: mesmo fornecedor cadastrado sob nomes diferentes
-- ---------------------------------------------------------------------
-- Aqui nao e grafia, e identidade: razao social, nome comercial e
-- abreviacao do mesmo fornecedor viraram linhas separadas no relatorio.
-- A chave original fica intacta em `chave_valor`, entao nada se perde --
-- e so o rotulo que passa a ser um so.
update public.de_para d
set fornecedor = c.rotulo,
    atualizado_em = now()
from (values
  -- CRBS S/A e a distribuidora da Ambev; "CDD Fortaleza" e o centro de
  -- distribuicao direta. Maior fornecedor da base, estava separado da
  -- propria Ambev.
  ('CRBSSACDDFORTALEZA',     'Ambev'),
  ('UBERDOBRASILTECNOLOGIA', 'Uber'),
  ('EXTRAHIPER',             'Extra'),
  -- Seis grafias do mesmo supermercado.
  ('COMETASUPERMER',         'Supermercado Cometa'),
  ('COMETASUPERMERCADO',     'Supermercado Cometa'),
  ('SUPERMERCADOCO',         'Supermercado Cometa'),
  ('SUPERMERCADOCOMETA',     'Supermercado Cometa'),
  ('SUPERMECADOSCO',         'Supermercado Cometa'),
  ('SUPERMECADOSCOMETA',     'Supermercado Cometa')
) as c(chave, rotulo)
where d.chave_tipo = 'nome'
  and d.chave_valor = c.chave
  and d.fornecedor is distinct from c.rotulo;

-- ---------------------------------------------------------------------
-- Bloco D: fornecedor especifico absorvido no rotulo generico
-- ---------------------------------------------------------------------
-- Diferente dos anteriores, este bloco NAO junta o que e igual: junta o
-- que o usuario ja trata igual. Combustivel e estacionamento sao lancados
-- de forma generica (32 chaves de posto rotuladas "COMBUSTIVEL"), e estas
-- tres escaparam com o nome do estabelecimento, virando linha propria.
--
-- E a unica decisao deste arquivo que troca informacao por consistencia:
-- o nome do posto some do rotulo. Continua disponivel em `chave_valor` e
-- no `contraparte_nome` do lancamento, entao basta reverter estas tres
-- linhas se preferir ver posto a posto.
update public.de_para d
set fornecedor = c.rotulo,
    atualizado_em = now()
from (values
  ('POSTOATLANTICO',     'Combustível'),
  ('POSTODOMMANOEL',     'Combustível'),
  ('ESTACIONAMBEMVINDO', 'Estacionamento')
) as c(chave, rotulo)
where d.chave_tipo = 'nome'
  and d.chave_valor = c.chave
  and d.fornecedor is distinct from c.rotulo;

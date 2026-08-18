-- Alinha os dois parametros da rotina de escalas com a escala que esta em uso.
--
-- 1) pre_abertura_min = 20 em todos os dias.
--    A migration anterior semeou 30 e 40 min, mas a decisao operacional ficou em
--    20: a cozinha se organiza enquanto o salao segura o cliente com bebida. A
--    escala gravada faz todo mundo entrar 08:40, e com a janela abrindo 08:20 a
--    pagina acusava "casa aberta e ninguem escalado" num intervalo que nao
--    existe na pratica.
--    So esta coluna e tocada: abertura, fechamento e pos_fechamento sao
--    editaveis pela pagina e nao devem ser sobrescritos por migration.
--
-- 2) capacidade_vendas_hora_pessoa = 4.34.
--    O teto foi calibrado como "a carga do pico atual" — domingo 17h com 3
--    pessoas. O valor 4.18 veio de um calculo externo que interpolava a curva
--    agregada; a view escala_demanda_base desloca cada transacao e chega a
--    13.00 vendas/hora nesse mesmo ponto. Com 4.18 a conta ficava circular:
--    ceil(13.00 / 4.18) = 4 exigia uma quarta pessoa exatamente no momento que
--    definiu a regua. 13.00 / 3 = 4.34 fecha a referencia consigo mesma.

begin;

update public.escala_funcionamento
   set pre_abertura_min = 20
 where pre_abertura_min <> 20;

update public.escala_config
   set valor = 4.34,
       descricao = 'Teto de vendas/hora que uma pessoa atende. Calibrado pelo pico da propria curva: domingo 17h, 13.00 vendas/hora divididas por 3 pessoas.'
 where chave = 'capacidade_vendas_hora_pessoa';

commit;

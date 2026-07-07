-- Padroniza grafias divergentes de conta_bancaria em conta_recorrente_pagamento.
-- "BS"/"bs" -> "BS Cash"; "PRIA"/"pria" -> "Praia". Idempotente: comparar por
-- lower(btrim(...)) e só atualizar quando o valor ainda não é o canônico.

update public.conta_recorrente_pagamento
set conta_bancaria = 'BS Cash'
where conta_bancaria is not null
  and lower(btrim(conta_bancaria)) = 'bs'
  and conta_bancaria is distinct from 'BS Cash';

update public.conta_recorrente_pagamento
set conta_bancaria = 'Praia'
where conta_bancaria is not null
  and lower(btrim(conta_bancaria)) = 'pria'
  and conta_bancaria is distinct from 'Praia';

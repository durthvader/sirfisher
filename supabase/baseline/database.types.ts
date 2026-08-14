export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      ajuste_manual: {
        Row: {
          categoria: string
          criado_em: string
          id: number
          observacao: string | null
          origem: string
          raw_id: number
        }
        Insert: {
          categoria: string
          criado_em?: string
          id?: never
          observacao?: string | null
          origem: string
          raw_id: number
        }
        Update: {
          categoria?: string
          criado_em?: string
          id?: never
          observacao?: string | null
          origem?: string
          raw_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "ajuste_manual_categoria_fkey"
            columns: ["categoria"]
            isOneToOne: false
            referencedRelation: "app_categoria_dre"
            referencedColumns: ["categoria"]
          },
          {
            foreignKeyName: "ajuste_manual_categoria_fkey"
            columns: ["categoria"]
            isOneToOne: false
            referencedRelation: "categoria_dre"
            referencedColumns: ["categoria"]
          },
        ]
      }
      backup_grants_20260629: {
        Row: {
          backup_em: string | null
          grantee: unknown
          privilege_type: string | null
          table_name: unknown
          table_schema: unknown
        }
        Insert: {
          backup_em?: string | null
          grantee?: unknown
          privilege_type?: string | null
          table_name?: unknown
          table_schema?: unknown
        }
        Update: {
          backup_em?: string | null
          grantee?: unknown
          privilege_type?: string | null
          table_name?: unknown
          table_schema?: unknown
        }
        Relationships: []
      }
      backup_policies_20260629: {
        Row: {
          backup_em: string | null
          cmd: string | null
          permissive: string | null
          policyname: unknown
          qual: string | null
          roles: unknown[] | null
          schemaname: unknown
          tablename: unknown
          with_check: string | null
        }
        Insert: {
          backup_em?: string | null
          cmd?: string | null
          permissive?: string | null
          policyname?: unknown
          qual?: string | null
          roles?: unknown[] | null
          schemaname?: unknown
          tablename?: unknown
          with_check?: string | null
        }
        Update: {
          backup_em?: string | null
          cmd?: string | null
          permissive?: string | null
          policyname?: unknown
          qual?: string | null
          roles?: unknown[] | null
          schemaname?: unknown
          tablename?: unknown
          with_check?: string | null
        }
        Relationships: []
      }
      categoria_dre: {
        Row: {
          categoria: string
          dre_grupo: string
          natureza: string | null
        }
        Insert: {
          categoria: string
          dre_grupo: string
          natureza?: string | null
        }
        Update: {
          categoria?: string
          dre_grupo?: string
          natureza?: string | null
        }
        Relationships: []
      }
      conciliacao_contabil_decisao: {
        Row: {
          ajuste_anterior_a: string | null
          ajuste_anterior_b: string | null
          categoria_anterior_a: string | null
          categoria_anterior_b: string | null
          chave_par: string
          contraparte_a: string | null
          contraparte_b: string | null
          data_a: string
          data_b: string
          decidido_em: string
          decidido_por: string
          decisao: string
          desfeito_em: string | null
          desfeito_por: string | null
          id: number
          origem_a: string
          origem_b: string
          raw_id_a: number
          raw_id_b: number
          valor_a: number
          valor_b: number
        }
        Insert: {
          ajuste_anterior_a?: string | null
          ajuste_anterior_b?: string | null
          categoria_anterior_a?: string | null
          categoria_anterior_b?: string | null
          chave_par: string
          contraparte_a?: string | null
          contraparte_b?: string | null
          data_a: string
          data_b: string
          decidido_em?: string
          decidido_por: string
          decisao: string
          desfeito_em?: string | null
          desfeito_por?: string | null
          id?: number
          origem_a: string
          origem_b: string
          raw_id_a: number
          raw_id_b: number
          valor_a: number
          valor_b: number
        }
        Update: {
          ajuste_anterior_a?: string | null
          ajuste_anterior_b?: string | null
          categoria_anterior_a?: string | null
          categoria_anterior_b?: string | null
          chave_par?: string
          contraparte_a?: string | null
          contraparte_b?: string | null
          data_a?: string
          data_b?: string
          decidido_em?: string
          decidido_por?: string
          decisao?: string
          desfeito_em?: string | null
          desfeito_por?: string | null
          id?: number
          origem_a?: string
          origem_b?: string
          raw_id_a?: number
          raw_id_b?: number
          valor_a?: number
          valor_b?: number
        }
        Relationships: []
      }
      conferencia_deposito_ajuste: {
        Row: {
          criado_em: string
          criado_por: string | null
          data: string
          desfeito_em: string | null
          desfeito_por: string | null
          id: number
          motivo: string
          valor: number
        }
        Insert: {
          criado_em?: string
          criado_por?: string | null
          data: string
          desfeito_em?: string | null
          desfeito_por?: string | null
          id?: never
          motivo: string
          valor: number
        }
        Update: {
          criado_em?: string
          criado_por?: string | null
          data?: string
          desfeito_em?: string | null
          desfeito_por?: string | null
          id?: never
          motivo?: string
          valor?: number
        }
        Relationships: []
      }
      configuracao_empresa: {
        Row: {
          atualizado_em: string
          atualizado_por: string | null
          nome: string
          singleton: boolean
          subtitulo: string
        }
        Insert: {
          atualizado_em?: string
          atualizado_por?: string | null
          nome: string
          singleton?: boolean
          subtitulo: string
        }
        Update: {
          atualizado_em?: string
          atualizado_por?: string | null
          nome?: string
          singleton?: boolean
          subtitulo?: string
        }
        Relationships: []
      }
      configuracao_operacional: {
        Row: {
          atualizado_em: string
          atualizado_por: string | null
          conferencia_deposito_desde: string
          conta_deposito_id: number | null
          deposito_descricao_padrao: string
          fuso_horario: string
          singleton: boolean
          unidade_exibicao: string
          unidade_principal_id: number
        }
        Insert: {
          atualizado_em?: string
          atualizado_por?: string | null
          conferencia_deposito_desde?: string
          conta_deposito_id?: number | null
          deposito_descricao_padrao?: string
          fuso_horario?: string
          singleton?: boolean
          unidade_exibicao: string
          unidade_principal_id: number
        }
        Update: {
          atualizado_em?: string
          atualizado_por?: string | null
          conferencia_deposito_desde?: string
          conta_deposito_id?: number | null
          deposito_descricao_padrao?: string
          fuso_horario?: string
          singleton?: boolean
          unidade_exibicao?: string
          unidade_principal_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "configuracao_operacional_conta_deposito_id_fkey"
            columns: ["conta_deposito_id"]
            isOneToOne: false
            referencedRelation: "conta"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "configuracao_operacional_unidade_principal_id_fkey"
            columns: ["unidade_principal_id"]
            isOneToOne: false
            referencedRelation: "unidade"
            referencedColumns: ["id"]
          },
        ]
      }
      conta: {
        Row: {
          ativa: boolean
          banco: string | null
          id: number
          nome: string
          saldo_base: number
          saldo_data_base: string
          saldo_metodo: string
          unidade_id: number | null
        }
        Insert: {
          ativa?: boolean
          banco?: string | null
          id?: never
          nome: string
          saldo_base?: number
          saldo_data_base?: string
          saldo_metodo?: string
          unidade_id?: number | null
        }
        Update: {
          ativa?: boolean
          banco?: string | null
          id?: never
          nome?: string
          saldo_base?: number
          saldo_data_base?: string
          saldo_metodo?: string
          unidade_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "conta_unidade_id_fkey"
            columns: ["unidade_id"]
            isOneToOne: false
            referencedRelation: "unidade"
            referencedColumns: ["id"]
          },
        ]
      }
      conta_recorrente: {
        Row: {
          ativa: boolean
          atualizado_em: string
          atualizado_por: string | null
          categoria: string
          criado_em: string
          criado_por: string | null
          dia_vencimento: number
          id: number
          incluir_totais: boolean
          nome: string
          origem_legado: string | null
          tipo: string
          unidade: string
        }
        Insert: {
          ativa?: boolean
          atualizado_em?: string
          atualizado_por?: string | null
          categoria: string
          criado_em?: string
          criado_por?: string | null
          dia_vencimento: number
          id?: never
          incluir_totais?: boolean
          nome: string
          origem_legado?: string | null
          tipo?: string
          unidade?: string
        }
        Update: {
          ativa?: boolean
          atualizado_em?: string
          atualizado_por?: string | null
          categoria?: string
          criado_em?: string
          criado_por?: string | null
          dia_vencimento?: number
          id?: never
          incluir_totais?: boolean
          nome?: string
          origem_legado?: string | null
          tipo?: string
          unidade?: string
        }
        Relationships: []
      }
      conta_recorrente_pagamento: {
        Row: {
          atualizado_em: string
          atualizado_por: string | null
          competencia: string
          conta_bancaria: string | null
          conta_id: number
          criado_em: string
          criado_por: string | null
          data_pagamento: string | null
          id: number
          observacao: string | null
          origem: string
          situacao: string
          valor: number | null
        }
        Insert: {
          atualizado_em?: string
          atualizado_por?: string | null
          competencia: string
          conta_bancaria?: string | null
          conta_id: number
          criado_em?: string
          criado_por?: string | null
          data_pagamento?: string | null
          id?: never
          observacao?: string | null
          origem?: string
          situacao: string
          valor?: number | null
        }
        Update: {
          atualizado_em?: string
          atualizado_por?: string | null
          competencia?: string
          conta_bancaria?: string | null
          conta_id?: number
          criado_em?: string
          criado_por?: string | null
          data_pagamento?: string | null
          id?: never
          observacao?: string | null
          origem?: string
          situacao?: string
          valor?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "conta_recorrente_pagamento_conta_id_fkey"
            columns: ["conta_id"]
            isOneToOne: false
            referencedRelation: "conta_recorrente"
            referencedColumns: ["id"]
          },
        ]
      }
      de_para: {
        Row: {
          ativo: boolean
          atualizado_em: string
          categoria: string
          chave_tipo: string
          chave_valor: string
          fornecedor: string | null
          id: number
        }
        Insert: {
          ativo?: boolean
          atualizado_em?: string
          categoria: string
          chave_tipo: string
          chave_valor: string
          fornecedor?: string | null
          id?: never
        }
        Update: {
          ativo?: boolean
          atualizado_em?: string
          categoria?: string
          chave_tipo?: string
          chave_valor?: string
          fornecedor?: string | null
          id?: never
        }
        Relationships: [
          {
            foreignKeyName: "fk_depara_categoria"
            columns: ["categoria"]
            isOneToOne: false
            referencedRelation: "app_categoria_dre"
            referencedColumns: ["categoria"]
          },
          {
            foreignKeyName: "fk_depara_categoria"
            columns: ["categoria"]
            isOneToOne: false
            referencedRelation: "categoria_dre"
            referencedColumns: ["categoria"]
          },
        ]
      }
      feriado: {
        Row: {
          data: string
          nome: string
          peso: number | null
          tipo: string
        }
        Insert: {
          data: string
          nome: string
          peso?: number | null
          tipo?: string
        }
        Update: {
          data?: string
          nome?: string
          peso?: number | null
          tipo?: string
        }
        Relationships: []
      }
      fonte_financeira: {
        Row: {
          ativa: boolean
          atualizado_em: string
          atualizado_por: string | null
          chave: string
          considerar_desde: string | null
          conta_id: number | null
          entra_caixa: boolean
          entra_caixa_historico: boolean
          entra_dre: boolean
          entra_faturamento: boolean
          nome: string
          saldo_adaptador: string
        }
        Insert: {
          ativa?: boolean
          atualizado_em?: string
          atualizado_por?: string | null
          chave: string
          considerar_desde?: string | null
          conta_id?: number | null
          entra_caixa?: boolean
          entra_caixa_historico?: boolean
          entra_dre?: boolean
          entra_faturamento?: boolean
          nome: string
          saldo_adaptador?: string
        }
        Update: {
          ativa?: boolean
          atualizado_em?: string
          atualizado_por?: string | null
          chave?: string
          considerar_desde?: string | null
          conta_id?: number | null
          entra_caixa?: boolean
          entra_caixa_historico?: boolean
          entra_dre?: boolean
          entra_faturamento?: boolean
          nome?: string
          saldo_adaptador?: string
        }
        Relationships: [
          {
            foreignKeyName: "fonte_financeira_conta_id_fkey"
            columns: ["conta_id"]
            isOneToOne: false
            referencedRelation: "conta"
            referencedColumns: ["id"]
          },
        ]
      }
      grupo_variavel: {
        Row: {
          grupo: string
          variavel: boolean
        }
        Insert: {
          grupo: string
          variavel?: boolean
        }
        Update: {
          grupo?: string
          variavel?: boolean
        }
        Relationships: []
      }
      log_carga: {
        Row: {
          data_hora: string
          fontes: string | null
          id: number
        }
        Insert: {
          data_hora?: string
          fontes?: string | null
          id?: number
        }
        Update: {
          data_hora?: string
          fontes?: string | null
          id?: number
        }
        Relationships: []
      }
      meta_mensal: {
        Row: {
          mes: string
          meta_bruta: number
          unidade: string
        }
        Insert: {
          mes: string
          meta_bruta: number
          unidade?: string
        }
        Update: {
          mes?: string
          meta_bruta?: number
          unidade?: string
        }
        Relationships: []
      }
      metas: {
        Row: {
          id: number
          mes: string
          orcamento: number | null
          unidade_id: number | null
        }
        Insert: {
          id?: never
          mes: string
          orcamento?: number | null
          unidade_id?: number | null
        }
        Update: {
          id?: never
          mes?: string
          orcamento?: number | null
          unidade_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "metas_unidade_id_fkey"
            columns: ["unidade_id"]
            isOneToOne: false
            referencedRelation: "unidade"
            referencedColumns: ["id"]
          },
        ]
      }
      pagina_permissao: {
        Row: {
          atualizado_em: string
          pagina: string
          papeis: string[]
        }
        Insert: {
          atualizado_em?: string
          pagina: string
          papeis?: string[]
        }
        Update: {
          atualizado_em?: string
          pagina?: string
          papeis?: string[]
        }
        Relationships: []
      }
      parametros: {
        Row: {
          chave: string
          descricao: string | null
          grupo: string
          ordem: number
          unidade_medida: string
          valor: number
          valor_max: number | null
          valor_min: number | null
        }
        Insert: {
          chave: string
          descricao?: string | null
          grupo?: string
          ordem?: number
          unidade_medida?: string
          valor: number
          valor_max?: number | null
          valor_min?: number | null
        }
        Update: {
          chave?: string
          descricao?: string | null
          grupo?: string
          ordem?: number
          unidade_medida?: string
          valor?: number
          valor_max?: number | null
          valor_min?: number | null
        }
        Relationships: []
      }
      perfil_usuario: {
        Row: {
          ativo: boolean
          criado_em: string
          papel: string
          user_id: string
        }
        Insert: {
          ativo?: boolean
          criado_em?: string
          papel: string
          user_id: string
        }
        Update: {
          ativo?: boolean
          criado_em?: string
          papel?: string
          user_id?: string
        }
        Relationships: []
      }
      peso_dia_semana: {
        Row: {
          dia_nome: string
          dow: number
          peso: number
        }
        Insert: {
          dia_nome: string
          dow: number
          peso: number
        }
        Update: {
          dia_nome?: string
          dow?: number
          peso?: number
        }
        Relationships: []
      }
      raw_bb: {
        Row: {
          conta_id: number | null
          data: string | null
          data_raw: string | null
          dedup_hash: string
          detalhes: string | null
          id: number
          importado_em: string
          lancamento: string | null
          n_documento: string | null
          tipo_lancamento: string | null
          valor: number | null
        }
        Insert: {
          conta_id?: number | null
          data?: string | null
          data_raw?: string | null
          dedup_hash: string
          detalhes?: string | null
          id?: never
          importado_em?: string
          lancamento?: string | null
          n_documento?: string | null
          tipo_lancamento?: string | null
          valor?: number | null
        }
        Update: {
          conta_id?: number | null
          data?: string | null
          data_raw?: string | null
          dedup_hash?: string
          detalhes?: string | null
          id?: never
          importado_em?: string
          lancamento?: string | null
          n_documento?: string | null
          tipo_lancamento?: string | null
          valor?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "raw_bb_conta_id_fkey"
            columns: ["conta_id"]
            isOneToOne: false
            referencedRelation: "conta"
            referencedColumns: ["id"]
          },
        ]
      }
      raw_bs_cash: {
        Row: {
          conta_id: number | null
          data_hora: string
          data_raw: string | null
          dcto: string | null
          dedup_hash: string
          favorecido: string | null
          historico: string | null
          id: number
          importado_em: string
          operacao: string | null
          saldo: number | null
          valor: number
        }
        Insert: {
          conta_id?: number | null
          data_hora: string
          data_raw?: string | null
          dcto?: string | null
          dedup_hash: string
          favorecido?: string | null
          historico?: string | null
          id?: never
          importado_em?: string
          operacao?: string | null
          saldo?: number | null
          valor: number
        }
        Update: {
          conta_id?: number | null
          data_hora?: string
          data_raw?: string | null
          dcto?: string | null
          dedup_hash?: string
          favorecido?: string | null
          historico?: string | null
          id?: never
          importado_em?: string
          operacao?: string | null
          saldo?: number | null
          valor?: number
        }
        Relationships: []
      }
      raw_fundopay_vendas: {
        Row: {
          antecipacao: number | null
          bandeira: string | null
          data_confirmacao: string | null
          data_venda: string
          dedup_hash: string
          id: number
          id_venda: string
          importado_em: string
          mdr: number | null
          modalidade: string | null
          n_parcelas: number | null
          situacao: string
          terminal: string | null
          tipo_terminal: string | null
          valor_liquido: number | null
          valor_venda: number
        }
        Insert: {
          antecipacao?: number | null
          bandeira?: string | null
          data_confirmacao?: string | null
          data_venda: string
          dedup_hash: string
          id?: number
          id_venda: string
          importado_em?: string
          mdr?: number | null
          modalidade?: string | null
          n_parcelas?: number | null
          situacao: string
          terminal?: string | null
          tipo_terminal?: string | null
          valor_liquido?: number | null
          valor_venda: number
        }
        Update: {
          antecipacao?: number | null
          bandeira?: string | null
          data_confirmacao?: string | null
          data_venda?: string
          dedup_hash?: string
          id?: number
          id_venda?: string
          importado_em?: string
          mdr?: number | null
          modalidade?: string | null
          n_parcelas?: number | null
          situacao?: string
          terminal?: string | null
          tipo_terminal?: string | null
          valor_liquido?: number | null
          valor_venda?: number
        }
        Relationships: []
      }
      raw_historico: {
        Row: {
          ajuste_manual: string | null
          categoria: string | null
          data_hora: string | null
          data_raw: string | null
          dedup_hash: string
          destino: string | null
          destino_documento: string | null
          destino_instituicao: string | null
          detalhamento: string | null
          dre_grupo: string | null
          empresa: string | null
          fornecedor: string | null
          id: number
          importado_em: string
          movimentacao: string | null
          nosso_numero: string | null
          origem: string | null
          origem_documento: string | null
          origem_instituicao: string | null
          saldo_antes: number | null
          saldo_depois: number | null
          seq: number | null
          situacao: string | null
          tarifa: string | null
          tipo: string | null
          valor: number | null
        }
        Insert: {
          ajuste_manual?: string | null
          categoria?: string | null
          data_hora?: string | null
          data_raw?: string | null
          dedup_hash: string
          destino?: string | null
          destino_documento?: string | null
          destino_instituicao?: string | null
          detalhamento?: string | null
          dre_grupo?: string | null
          empresa?: string | null
          fornecedor?: string | null
          id?: never
          importado_em?: string
          movimentacao?: string | null
          nosso_numero?: string | null
          origem?: string | null
          origem_documento?: string | null
          origem_instituicao?: string | null
          saldo_antes?: number | null
          saldo_depois?: number | null
          seq?: number | null
          situacao?: string | null
          tarifa?: string | null
          tipo?: string | null
          valor?: number | null
        }
        Update: {
          ajuste_manual?: string | null
          categoria?: string | null
          data_hora?: string | null
          data_raw?: string | null
          dedup_hash?: string
          destino?: string | null
          destino_documento?: string | null
          destino_instituicao?: string | null
          detalhamento?: string | null
          dre_grupo?: string | null
          empresa?: string | null
          fornecedor?: string | null
          id?: never
          importado_em?: string
          movimentacao?: string | null
          nosso_numero?: string | null
          origem?: string | null
          origem_documento?: string | null
          origem_instituicao?: string | null
          saldo_antes?: number | null
          saldo_depois?: number | null
          seq?: number | null
          situacao?: string | null
          tarifa?: string | null
          tipo?: string | null
          valor?: number | null
        }
        Relationships: []
      }
      raw_inter: {
        Row: {
          conta_id: number | null
          data: string
          data_raw: string | null
          dedup_hash: string
          descricao: string | null
          historico: string | null
          id: number
          importado_em: string
          saldo: number | null
          valor: number
        }
        Insert: {
          conta_id?: number | null
          data: string
          data_raw?: string | null
          dedup_hash: string
          descricao?: string | null
          historico?: string | null
          id?: number
          importado_em?: string
          saldo?: number | null
          valor: number
        }
        Update: {
          conta_id?: number | null
          data?: string
          data_raw?: string | null
          dedup_hash?: string
          descricao?: string | null
          historico?: string | null
          id?: number
          importado_em?: string
          saldo?: number | null
          valor?: number
        }
        Relationships: [
          {
            foreignKeyName: "raw_inter_conta_id_fkey"
            columns: ["conta_id"]
            isOneToOne: false
            referencedRelation: "conta"
            referencedColumns: ["id"]
          },
        ]
      }
      raw_stone_extrato: {
        Row: {
          conta_id: number | null
          data_hora: string | null
          data_hora_raw: string | null
          dedup_hash: string
          descricao: string | null
          destino: string | null
          destino_agencia: string | null
          destino_conta: string | null
          destino_documento: string | null
          destino_instituicao: string | null
          horario: string | null
          id: number
          importado_em: string
          movimentacao: string | null
          nosso_numero: string | null
          origem: string | null
          origem_agencia: string | null
          origem_carga: string
          origem_conta: string | null
          origem_documento: string | null
          origem_instituicao: string | null
          saldo_antes: number | null
          saldo_depois: number | null
          situacao: string | null
          tarifa: string | null
          tipo: string | null
          valor: number | null
        }
        Insert: {
          conta_id?: number | null
          data_hora?: string | null
          data_hora_raw?: string | null
          dedup_hash: string
          descricao?: string | null
          destino?: string | null
          destino_agencia?: string | null
          destino_conta?: string | null
          destino_documento?: string | null
          destino_instituicao?: string | null
          horario?: string | null
          id?: never
          importado_em?: string
          movimentacao?: string | null
          nosso_numero?: string | null
          origem?: string | null
          origem_agencia?: string | null
          origem_carga?: string
          origem_conta?: string | null
          origem_documento?: string | null
          origem_instituicao?: string | null
          saldo_antes?: number | null
          saldo_depois?: number | null
          situacao?: string | null
          tarifa?: string | null
          tipo?: string | null
          valor?: number | null
        }
        Update: {
          conta_id?: number | null
          data_hora?: string | null
          data_hora_raw?: string | null
          dedup_hash?: string
          descricao?: string | null
          destino?: string | null
          destino_agencia?: string | null
          destino_conta?: string | null
          destino_documento?: string | null
          destino_instituicao?: string | null
          horario?: string | null
          id?: never
          importado_em?: string
          movimentacao?: string | null
          nosso_numero?: string | null
          origem?: string | null
          origem_agencia?: string | null
          origem_carga?: string
          origem_conta?: string | null
          origem_documento?: string | null
          origem_instituicao?: string | null
          saldo_antes?: number | null
          saldo_depois?: number | null
          situacao?: string | null
          tarifa?: string | null
          tipo?: string | null
          valor?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "raw_stone_extrato_conta_id_fkey"
            columns: ["conta_id"]
            isOneToOne: false
            referencedRelation: "conta"
            referencedColumns: ["id"]
          },
        ]
      }
      raw_stone_recebiveis: {
        Row: {
          bandeira: string | null
          categoria: string | null
          conta_id: number | null
          data_ultimo_status: string | null
          data_vencimento: string | null
          data_vencimento_original: string | null
          data_venda: string | null
          desconto_antecipacao: number | null
          desconto_mdr: number | null
          desconto_unificado: number | null
          documento: string | null
          entradas_brutas: number | null
          id: number
          importado_em: string
          n_parcela: number
          produto: string | null
          qtd_parcelas: number | null
          saidas_brutas: number | null
          stone_id: string
          stonecode: string | null
          ultimo_status: string | null
          valor_bruto: number | null
          valor_liquido: number | null
        }
        Insert: {
          bandeira?: string | null
          categoria?: string | null
          conta_id?: number | null
          data_ultimo_status?: string | null
          data_vencimento?: string | null
          data_vencimento_original?: string | null
          data_venda?: string | null
          desconto_antecipacao?: number | null
          desconto_mdr?: number | null
          desconto_unificado?: number | null
          documento?: string | null
          entradas_brutas?: number | null
          id?: never
          importado_em?: string
          n_parcela: number
          produto?: string | null
          qtd_parcelas?: number | null
          saidas_brutas?: number | null
          stone_id: string
          stonecode?: string | null
          ultimo_status?: string | null
          valor_bruto?: number | null
          valor_liquido?: number | null
        }
        Update: {
          bandeira?: string | null
          categoria?: string | null
          conta_id?: number | null
          data_ultimo_status?: string | null
          data_vencimento?: string | null
          data_vencimento_original?: string | null
          data_venda?: string | null
          desconto_antecipacao?: number | null
          desconto_mdr?: number | null
          desconto_unificado?: number | null
          documento?: string | null
          entradas_brutas?: number | null
          id?: never
          importado_em?: string
          n_parcela?: number
          produto?: string | null
          qtd_parcelas?: number | null
          saidas_brutas?: number | null
          stone_id?: string
          stonecode?: string | null
          ultimo_status?: string | null
          valor_bruto?: number | null
          valor_liquido?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "raw_stone_recebiveis_conta_id_fkey"
            columns: ["conta_id"]
            isOneToOne: false
            referencedRelation: "conta"
            referencedColumns: ["id"]
          },
        ]
      }
      raw_stone_vendas: {
        Row: {
          bandeira: string | null
          conta_id: number | null
          data_ultimo_status: string | null
          data_venda: string | null
          desconto_antecipacao: number | null
          desconto_mdr: number | null
          desconto_unificado: number | null
          documento: string | null
          id: number
          importado_em: string
          meio_captura: string | null
          n_cartao: string | null
          n_parcelas: number | null
          n_serie: string | null
          produto: string | null
          stone_id: string
          stonecode: string | null
          ultimo_status: string | null
          valor_bruto: number | null
          valor_liquido: number | null
        }
        Insert: {
          bandeira?: string | null
          conta_id?: number | null
          data_ultimo_status?: string | null
          data_venda?: string | null
          desconto_antecipacao?: number | null
          desconto_mdr?: number | null
          desconto_unificado?: number | null
          documento?: string | null
          id?: never
          importado_em?: string
          meio_captura?: string | null
          n_cartao?: string | null
          n_parcelas?: number | null
          n_serie?: string | null
          produto?: string | null
          stone_id: string
          stonecode?: string | null
          ultimo_status?: string | null
          valor_bruto?: number | null
          valor_liquido?: number | null
        }
        Update: {
          bandeira?: string | null
          conta_id?: number | null
          data_ultimo_status?: string | null
          data_venda?: string | null
          desconto_antecipacao?: number | null
          desconto_mdr?: number | null
          desconto_unificado?: number | null
          documento?: string | null
          id?: never
          importado_em?: string
          meio_captura?: string | null
          n_cartao?: string | null
          n_parcelas?: number | null
          n_serie?: string | null
          produto?: string | null
          stone_id?: string
          stonecode?: string | null
          ultimo_status?: string | null
          valor_bruto?: number | null
          valor_liquido?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "raw_stone_vendas_conta_id_fkey"
            columns: ["conta_id"]
            isOneToOne: false
            referencedRelation: "conta"
            referencedColumns: ["id"]
          },
        ]
      }
      recebimento_regra: {
        Row: {
          dias: number
          forma: string
          percentual: number
          taxa: number
        }
        Insert: {
          dias: number
          forma: string
          percentual: number
          taxa: number
        }
        Update: {
          dias?: number
          forma?: string
          percentual?: number
          taxa?: number
        }
        Relationships: []
      }
      saldo_fechamento_mensal: {
        Row: {
          ano_mes: string
          calculado_em: string
          data_referencia: string | null
          mes: string
          observacao: string | null
          origem: string
          saldo_fim: number
          status: string
          unidade: string
        }
        Insert: {
          ano_mes: string
          calculado_em?: string
          data_referencia?: string | null
          mes: string
          observacao?: string | null
          origem?: string
          saldo_fim: number
          status?: string
          unidade?: string
        }
        Update: {
          ano_mes?: string
          calculado_em?: string
          data_referencia?: string | null
          mes?: string
          observacao?: string | null
          origem?: string
          saldo_fim?: number
          status?: string
          unidade?: string
        }
        Relationships: []
      }
      saldo_inicial: {
        Row: {
          conta: string
          data_base: string
          obs: string | null
          saldo: number
        }
        Insert: {
          conta: string
          data_base: string
          obs?: string | null
          saldo: number
        }
        Update: {
          conta?: string
          data_base?: string
          obs?: string | null
          saldo?: number
        }
        Relationships: []
      }
      stone_conta: {
        Row: {
          ativa: boolean
          atualizado_em: string
          atualizado_por: string | null
          conta_id: number
          descricao: string | null
          entra_faturamento: boolean
          stonecode: string
        }
        Insert: {
          ativa?: boolean
          atualizado_em?: string
          atualizado_por?: string | null
          conta_id: number
          descricao?: string | null
          entra_faturamento?: boolean
          stonecode: string
        }
        Update: {
          ativa?: boolean
          atualizado_em?: string
          atualizado_por?: string | null
          conta_id?: number
          descricao?: string | null
          entra_faturamento?: boolean
          stonecode?: string
        }
        Relationships: [
          {
            foreignKeyName: "stone_conta_conta_id_fkey"
            columns: ["conta_id"]
            isOneToOne: false
            referencedRelation: "conta"
            referencedColumns: ["id"]
          },
        ]
      }
      stone_estabelecimento: {
        Row: {
          criado_em: string
          descricao: string | null
          stonecode: string
          unidade: string
        }
        Insert: {
          criado_em?: string
          descricao?: string | null
          stonecode: string
          unidade: string
        }
        Update: {
          criado_em?: string
          descricao?: string | null
          stonecode?: string
          unidade?: string
        }
        Relationships: []
      }
      unidade: {
        Row: {
          ativa: boolean
          id: number
          nome: string
        }
        Insert: {
          ativa?: boolean
          id?: never
          nome: string
        }
        Update: {
          ativa?: boolean
          id?: never
          nome?: string
        }
        Relationships: []
      }
      venda_especie: {
        Row: {
          cadastrado_por: string | null
          criado_em: string
          data: string
          depositada_em: string | null
          depositada_por: string | null
          id: number
          observacao: string | null
          recolhida_em: string | null
          recolhida_por: string | null
          unidade: string
          valor: number
        }
        Insert: {
          cadastrado_por?: string | null
          criado_em?: string
          data: string
          depositada_em?: string | null
          depositada_por?: string | null
          id?: never
          observacao?: string | null
          recolhida_em?: string | null
          recolhida_por?: string | null
          unidade?: string
          valor: number
        }
        Update: {
          cadastrado_por?: string | null
          criado_em?: string
          data?: string
          depositada_em?: string | null
          depositada_por?: string | null
          id?: never
          observacao?: string | null
          recolhida_em?: string | null
          recolhida_por?: string | null
          unidade?: string
          valor?: number
        }
        Relationships: []
      }
    }
    Views: {
      analise_individual: {
        Row: {
          contraparte_doc: string | null
          contraparte_nome: string | null
          data_caixa: string | null
          descricao: string | null
          destino_instituicao: string | null
          empresa: string | null
          fornecedor: string | null
          movimentacao: string | null
          natureza: string | null
          origem: string | null
          origem_instituicao: string | null
          raw_id: number | null
          tipo: string | null
          transferencia_propria: boolean | null
          unidade: string | null
          valor: number | null
        }
        Relationships: []
      }
      app_analise_individual: {
        Row: {
          contraparte_doc: string | null
          contraparte_nome: string | null
          data_caixa: string | null
          descricao: string | null
          destino_instituicao: string | null
          empresa: string | null
          fornecedor: string | null
          movimentacao: string | null
          natureza: string | null
          origem: string | null
          origem_instituicao: string | null
          raw_id: number | null
          tipo: string | null
          transferencia_propria: boolean | null
          unidade: string | null
          valor: number | null
        }
        Relationships: []
      }
      app_categoria_dre: {
        Row: {
          categoria: string | null
          dre_grupo: string | null
          natureza: string | null
        }
        Insert: {
          categoria?: string | null
          dre_grupo?: string | null
          natureza?: string | null
        }
        Update: {
          categoria?: string | null
          dre_grupo?: string | null
          natureza?: string | null
        }
        Relationships: []
      }
      app_classificacoes_recentes: {
        Row: {
          categoria: string | null
          data_lancamento: string | null
          detalhe: string | null
          id: number | null
          natureza: string | null
          quando: string | null
          tipo: string | null
          titulo: string | null
          valor: number | null
        }
        Relationships: []
      }
      app_conciliacao_contabil: {
        Row: {
          ano_mes: string | null
          atualizado_em: string | null
          categoria: string | null
          contraparte_confere: boolean | null
          contraparte_nome: string | null
          data_caixa: string | null
          data_hora: string | null
          dias_diferenca: number | null
          dre_grupo: string | null
          espera_zerar: boolean | null
          evidencia_reversao: string | null
          fornecedor: string | null
          minutos_intervalo: number | null
          nivel_reversao: string | null
          origem: string | null
          par_categoria: string | null
          par_contraparte: string | null
          par_data: string | null
          par_data_hora: string | null
          par_origem: string | null
          par_raw_id: number | null
          par_valor: number | null
          possui_horario: boolean | null
          qtd_candidatos: number | null
          raw_id: number | null
          status_conciliacao: string | null
          tipo: string | null
          valor: number | null
        }
        Relationships: []
      }
      app_conciliacao_contabil_decisoes: {
        Row: {
          ano_mes: string | null
          ativa: boolean | null
          categoria_anterior_a: string | null
          categoria_anterior_b: string | null
          contraparte_a: string | null
          contraparte_b: string | null
          data_a: string | null
          data_b: string | null
          decidido_em: string | null
          decidido_por_nome: string | null
          decisao: string | null
          desfeito_em: string | null
          desfeito_por_nome: string | null
          id: number | null
          origem_a: string | null
          origem_b: string | null
          raw_id_a: number | null
          raw_id_b: number | null
          valor_a: number | null
          valor_b: number | null
        }
        Insert: {
          ano_mes?: never
          ativa?: never
          categoria_anterior_a?: string | null
          categoria_anterior_b?: string | null
          contraparte_a?: string | null
          contraparte_b?: string | null
          data_a?: string | null
          data_b?: string | null
          decidido_em?: string | null
          decidido_por_nome?: never
          decisao?: string | null
          desfeito_em?: string | null
          desfeito_por_nome?: never
          id?: number | null
          origem_a?: string | null
          origem_b?: string | null
          raw_id_a?: number | null
          raw_id_b?: number | null
          valor_a?: number | null
          valor_b?: number | null
        }
        Update: {
          ano_mes?: never
          ativa?: never
          categoria_anterior_a?: string | null
          categoria_anterior_b?: string | null
          contraparte_a?: string | null
          contraparte_b?: string | null
          data_a?: string | null
          data_b?: string | null
          decidido_em?: string | null
          decidido_por_nome?: never
          decisao?: string | null
          desfeito_em?: string | null
          desfeito_por_nome?: never
          id?: number | null
          origem_a?: string | null
          origem_b?: string | null
          raw_id_a?: number | null
          raw_id_b?: number | null
          valor_a?: number | null
          valor_b?: number | null
        }
        Relationships: []
      }
      app_conciliacao_contabil_resumo_mensal: {
        Row: {
          ano_mes: string | null
          atualizado_em: string | null
          creditos: number | null
          debitos: number | null
          qtd: number | null
          status_conciliacao: string | null
          total: number | null
        }
        Relationships: []
      }
      app_conciliacao_stone: {
        Row: {
          bruto_receb: number | null
          bruto_venda: number | null
          data_venda: string | null
          diferenca_bruto: number | null
          liquido_receb: number | null
          mes_referencia: string | null
          n_parcelas: number | null
          n_venda: number | null
          primeiro_venc: string | null
          produto: string | null
          situacao: string | null
          stone_id: string | null
        }
        Relationships: []
      }
      app_conciliacao_stone_resumo: {
        Row: {
          qtd: number | null
          situacao: string | null
          total_recebivel: number | null
          total_venda: number | null
        }
        Relationships: []
      }
      app_conciliacao_stone_resumo_mensal: {
        Row: {
          ano_mes: string | null
          mes: string | null
          qtd: number | null
          situacao: string | null
          total_recebivel: number | null
          total_venda: number | null
        }
        Relationships: []
      }
      app_conferencia_deposito_ajustes: {
        Row: {
          criado_em: string | null
          criado_por_nome: string | null
          data: string | null
          desfeito_em: string | null
          desfeito_por_nome: string | null
          id: number | null
          motivo: string | null
          valor: number | null
        }
        Insert: {
          criado_em?: string | null
          criado_por_nome?: never
          data?: string | null
          desfeito_em?: string | null
          desfeito_por_nome?: never
          id?: number | null
          motivo?: string | null
          valor?: number | null
        }
        Update: {
          criado_em?: string | null
          criado_por_nome?: never
          data?: string | null
          desfeito_em?: string | null
          desfeito_por_nome?: never
          id?: number | null
          motivo?: string | null
          valor?: number | null
        }
        Relationships: []
      }
      app_conferencia_deposito_especie: {
        Row: {
          ajuste: number | null
          data: string | null
          diferenca: number | null
          extrato: number | null
          marcado: number | null
          marcado_em: string | null
          marcado_por_nome: string | null
          qtd_lancamentos: number | null
          qtd_sangrias: number | null
          status: string | null
        }
        Relationships: []
      }
      app_conferencia_deposito_especie_resumo: {
        Row: {
          ajustes_justificados: number | null
          desde: string | null
          diferenca: number | null
          extrato_ate: string | null
          marcado_depositado: number | null
          pendente_deposito: number | null
          recebido_banco: number | null
          ultimo_deposito: string | null
        }
        Relationships: []
      }
      app_contas_recorrentes_pagamentos: {
        Row: {
          atualizado_em: string | null
          atualizado_por_nome: string | null
          categoria: string | null
          competencia: string | null
          conta_bancaria: string | null
          conta_id: number | null
          data_pagamento: string | null
          id: number | null
          nome: string | null
          observacao: string | null
          origem: string | null
          situacao: string | null
          tipo: string | null
          unidade: string | null
          valor: number | null
        }
        Relationships: [
          {
            foreignKeyName: "conta_recorrente_pagamento_conta_id_fkey"
            columns: ["conta_id"]
            isOneToOne: false
            referencedRelation: "conta_recorrente"
            referencedColumns: ["id"]
          },
        ]
      }
      app_contas_recorrentes_totais: {
        Row: {
          competencia: string | null
          qtd_pagamentos: number | null
          total_pago: number | null
        }
        Relationships: []
      }
      app_excecoes: {
        Row: {
          chave_tipo: string | null
          chave_valor: string | null
          contraparte_doc: string | null
          contraparte_nome: string | null
          data_max: string | null
          data_min: string | null
          destinos_instituicao: string[] | null
          natureza: string | null
          origens_instituicao: string[] | null
          qtd_lancamentos: number | null
          sistemas_origem: string[] | null
          tem_transferencia_propria: boolean | null
          tipos: string[] | null
          total: number | null
        }
        Relationships: []
      }
      app_gerenciador_de_para_historico: {
        Row: {
          acao: string | null
          alterado_em: string | null
          alterado_por_nome: string | null
          ativo_antes: boolean | null
          ativo_depois: boolean | null
          categoria_antes: string | null
          categoria_depois: string | null
          chave_tipo: string | null
          chave_valor: string | null
          desfeita: boolean | null
          desfeito_em: string | null
          desfeito_por_nome: string | null
          eh_estado_atual: boolean | null
          existia_antes: boolean | null
          existia_depois: boolean | null
          fornecedor_antes: string | null
          fornecedor_depois: string | null
          id: number | null
          origem_acao: string | null
          pode_desfazer: boolean | null
          regra_id: number | null
          tem_posterior_ativa: boolean | null
        }
        Relationships: []
      }
      app_gerente_dre_cascata_perc: {
        Row: {
          ano_mes: string | null
          capex_perc: number | null
          cmv_perc: number | null
          contabil_perc: number | null
          em_projecao: boolean | null
          impostos_perc: number | null
          infraestrutura_perc: number | null
          margem_contribuicao_perc: number | null
          marketing_perc: number | null
          mes: string | null
          nao_categorizado_perc: number | null
          nao_operacional_perc: number | null
          pessoal_perc: number | null
          resultado_liquido_perc: number | null
          resultado_liquido_projetado_perc: number | null
          resultado_operacional_perc: number | null
          resultado_operacional_projetado_perc: number | null
        }
        Relationships: []
      }
      app_gerente_gasto_grupo: {
        Row: {
          ano_mes: string | null
          grupo: string | null
          mes: string | null
          participacao_perc: number | null
        }
        Relationships: []
      }
      app_gerente_meta_diaria: {
        Row: {
          dia: string | null
          mes: string | null
          meta_dia: number | null
          venda_dia: number | null
        }
        Relationships: []
      }
      app_gerente_movimento_hora: {
        Row: {
          ano_mes: string | null
          hora: number | null
          qtd: number | null
        }
        Relationships: []
      }
      app_gerente_resumo_mensal: {
        Row: {
          ano: number | null
          ano_mes: string | null
          faturamento: number | null
          faturamento_proj: number | null
          mes: string | null
          meta: number | null
          perc_meta: number | null
          qtd_vendas: number | null
          ticket_medio: number | null
        }
        Relationships: []
      }
      app_gerente_saldo_variacao: {
        Row: {
          ano_mes: string | null
          previsao_bonificacao: number | null
          variacao_perc: number | null
        }
        Relationships: []
      }
      app_gerente_ultima_carga: {
        Row: {
          ultima: string | null
        }
        Relationships: []
      }
      app_mv_despesa_mensal: {
        Row: {
          ano_mes: string | null
          categoria: string | null
          fornecedor: string | null
          grupo: string | null
          lancamentos: number | null
          mes: string | null
          valor: number | null
        }
        Relationships: []
      }
      app_painel_cargas: {
        Row: {
          fontes: string | null
          quando: string | null
        }
        Relationships: []
      }
      app_painel_composicao_despesa: {
        Row: {
          ano_mes: string | null
          grupo: string | null
          mes: string | null
          valor: number | null
        }
        Relationships: []
      }
      app_painel_diario: {
        Row: {
          dia: string | null
          mes: string | null
          meta_dia: number | null
          meta_mes: number | null
          peso_total: number | null
          projecao_fechamento: number | null
          venda_dia: number | null
        }
        Relationships: []
      }
      app_painel_dre_cascata: {
        Row: {
          ano_mes: string | null
          capex: number | null
          cmv: number | null
          cmv_perc: number | null
          contabil: number | null
          impostos: number | null
          infraestrutura: number | null
          margem_contribuicao: number | null
          margem_liq_perc: number | null
          margem_op_perc: number | null
          marketing: number | null
          mc_perc: number | null
          mes: string | null
          nao_categorizado: number | null
          nao_operacional: number | null
          pessoal: number | null
          pessoal_perc: number | null
          receita: number | null
          resultado_liquido: number | null
          resultado_operacional: number | null
        }
        Relationships: []
      }
      app_painel_fluxo_caixa: {
        Row: {
          dia: string | null
          entrada_projetada: number | null
          resultado_dia: number | null
          saida_projetada: number | null
          saldo: number | null
          saldo_projetado: number | null
          saldo_real: number | null
          tipo: string | null
        }
        Relationships: []
      }
      app_painel_margem_contribuicao: {
        Row: {
          ano_mes: string | null
          mc_perc: number | null
          mes: string | null
        }
        Relationships: []
      }
      app_painel_meta_real_mensal: {
        Row: {
          ano: number | null
          ano_mes: string | null
          mes: string | null
          mes_num: number | null
          meta: number | null
          perc_atingido: number | null
          realizado: number | null
        }
        Relationships: []
      }
      app_painel_recebimento_canal: {
        Row: {
          ano_mes: string | null
          canal: string | null
          qtd: number | null
          valor: number | null
        }
        Relationships: []
      }
      app_painel_recebimento_hora: {
        Row: {
          ano_mes: string | null
          hora: number | null
          qtd: number | null
          valor: number | null
        }
        Relationships: []
      }
      app_painel_recebimento_resumo: {
        Row: {
          ano_mes: string | null
          mes: string | null
          qtd_transacoes: number | null
          recebido_total: number | null
          ticket_transacao: number | null
        }
        Relationships: []
      }
      app_painel_resumo_mensal: {
        Row: {
          ano: number | null
          ano_mes: string | null
          cmv: number | null
          cmv_perc: number | null
          despesa: number | null
          faturamento: number | null
          faturamento_proj: number | null
          margem_perc: number | null
          mes: string | null
          meta: number | null
          perc_meta: number | null
          pessoal: number | null
          pessoal_perc: number | null
          qtd_vendas: number | null
          receita: number | null
          resultado: number | null
          saldo_fim: number | null
          saldo_situacao: string | null
          ticket_medio: number | null
        }
        Relationships: []
      }
      app_painel_saldo_atual: {
        Row: {
          data_comp: string | null
          data_ref: string | null
          saldo_atual: number | null
          saldo_comp: number | null
        }
        Relationships: []
      }
      app_painel_saldo_fim_mes: {
        Row: {
          ano_mes: string | null
          mes: string | null
          saldo_fim: number | null
          situacao: string | null
        }
        Relationships: []
      }
      app_painel_saldo_por_conta: {
        Row: {
          conta: string | null
          data_ref: string | null
          saldo: number | null
        }
        Relationships: []
      }
      app_painel_ultima_carga: {
        Row: {
          ultima: string | null
        }
        Relationships: []
      }
      app_projecao_despesa_direta: {
        Row: {
          dia: string | null
          valor: number | null
        }
        Relationships: []
      }
      app_projecao_despesa_fixa: {
        Row: {
          dia: string | null
          valor: number | null
        }
        Relationships: []
      }
      app_recebimento_conhecido: {
        Row: {
          dia: string | null
          valor: number | null
        }
        Relationships: []
      }
      app_recebimento_projetado: {
        Row: {
          dia: string | null
          valor: number | null
        }
        Relationships: []
      }
      app_status_cargas: {
        Row: {
          atraso_dias: number | null
          fonte: string | null
          linhas: number | null
          periodo_fim: string | null
          periodo_inicio: string | null
          situacao: string | null
          ultima_carga: string | null
          ultima_importacao: string | null
        }
        Relationships: []
      }
      app_transacoes_dia: {
        Row: {
          ajuste_atual: string | null
          ajuste_em: string | null
          ajuste_observacao_token: string | null
          categoria: string | null
          classificacao_bloqueada: boolean | null
          classificacao_origem: string | null
          conciliacao_ano_mes: string | null
          conciliacao_decisao_id: number | null
          contraparte_nome: string | null
          data_caixa: string | null
          data_competencia: string | null
          dre_grupo: string | null
          empresa: string | null
          entra_dre: boolean | null
          fornecedor: string | null
          movimentacao: string | null
          natureza: string | null
          origem: string | null
          raw_id: number | null
          status: string | null
          tipo: string | null
          unidade: string | null
          valor: number | null
        }
        Relationships: [
          {
            foreignKeyName: "ajuste_manual_categoria_fkey"
            columns: ["ajuste_atual"]
            isOneToOne: false
            referencedRelation: "app_categoria_dre"
            referencedColumns: ["categoria"]
          },
          {
            foreignKeyName: "ajuste_manual_categoria_fkey"
            columns: ["ajuste_atual"]
            isOneToOne: false
            referencedRelation: "categoria_dre"
            referencedColumns: ["categoria"]
          },
        ]
      }
      app_transacoes_dia_historico: {
        Row: {
          acao: string | null
          ajuste_anterior: string | null
          ajuste_novo: string | null
          alterado_em: string | null
          alterado_por_nome: string | null
          bloqueada_conciliacao: boolean | null
          categoria_final_anterior: string | null
          categoria_final_nova: string | null
          contraparte_nome: string | null
          data_caixa: string | null
          desfeita: boolean | null
          desfeito_em: string | null
          desfeito_por_nome: string | null
          eh_estado_atual: boolean | null
          id: number | null
          origem: string | null
          pode_desfazer: boolean | null
          raw_id: number | null
          tem_posterior_ativa: boolean | null
          valor: number | null
        }
        Relationships: []
      }
      app_usuarios_acesso: {
        Row: {
          ativo: boolean | null
          criado_em: string | null
          email: string | null
          nome: string | null
          papel: string | null
          ultimo_login: string | null
          user_id: string | null
        }
        Relationships: []
      }
      app_venda_especie_controle: {
        Row: {
          cadastrado_por_nome: string | null
          criado_em: string | null
          data: string | null
          depositada_em: string | null
          depositada_por_nome: string | null
          id: number | null
          observacao: string | null
          recolhida_em: string | null
          recolhida_por_nome: string | null
          unidade: string | null
          valor: number | null
        }
        Insert: {
          cadastrado_por_nome?: never
          criado_em?: string | null
          data?: string | null
          depositada_em?: string | null
          depositada_por_nome?: never
          id?: number | null
          observacao?: string | null
          recolhida_em?: string | null
          recolhida_por_nome?: never
          unidade?: string | null
          valor?: number | null
        }
        Update: {
          cadastrado_por_nome?: never
          criado_em?: string | null
          data?: string | null
          depositada_em?: string | null
          depositada_por_nome?: never
          id?: number | null
          observacao?: string | null
          recolhida_em?: string | null
          recolhida_por_nome?: never
          unidade?: string | null
          valor?: number | null
        }
        Relationships: []
      }
      caixa_real_diario: {
        Row: {
          dia: string | null
          resultado_real: number | null
        }
        Relationships: []
      }
      calendario: {
        Row: {
          ano: number | null
          ano_mes: string | null
          dia: string | null
          dow: number | null
          evento: string | null
          mes: string | null
          peso: number | null
          peso_ajustado: number | null
          tipo_dia: string | null
        }
        Relationships: []
      }
      conciliacao_stone: {
        Row: {
          bruto_receb: number | null
          bruto_venda: number | null
          data_venda: string | null
          diferenca_bruto: number | null
          liquido_receb: number | null
          mes_referencia: string | null
          n_parcelas: number | null
          n_venda: number | null
          primeiro_venc: string | null
          produto: string | null
          situacao: string | null
          stone_id: string | null
        }
        Relationships: []
      }
      conciliacao_stone_resumo: {
        Row: {
          qtd: number | null
          situacao: string | null
          total_recebivel: number | null
          total_venda: number | null
        }
        Relationships: []
      }
      conciliacao_stone_resumo_mensal: {
        Row: {
          ano_mes: string | null
          mes: string | null
          qtd: number | null
          situacao: string | null
          total_recebivel: number | null
          total_venda: number | null
        }
        Relationships: []
      }
      corte_caixa: {
        Row: {
          dia: string | null
        }
        Relationships: []
      }
      corte_venda: {
        Row: {
          dia: string | null
        }
        Relationships: []
      }
      dre_mensal: {
        Row: {
          ano: number | null
          ano_mes: string | null
          categoria: string | null
          dre_grupo: string | null
          empresa: string | null
          entra_dre: boolean | null
          mes: string | null
          natureza: string | null
          qtd: number | null
          total: number | null
          unidade: string | null
        }
        Relationships: []
      }
      excecoes: {
        Row: {
          chave_tipo: string | null
          chave_valor: string | null
          contraparte_doc: string | null
          contraparte_nome: string | null
          data_max: string | null
          data_min: string | null
          destinos_instituicao: string[] | null
          natureza: string | null
          origens_instituicao: string[] | null
          qtd_lancamentos: number | null
          sistemas_origem: string[] | null
          tem_transferencia_propria: boolean | null
          tipos: string[] | null
          total: number | null
        }
        Relationships: []
      }
      fato_financeiro: {
        Row: {
          categoria: string | null
          contraparte_doc: string | null
          contraparte_nome: string | null
          data_caixa: string | null
          data_competencia: string | null
          dre_grupo: string | null
          empresa: string | null
          entra_dre: boolean | null
          fornecedor: string | null
          movimentacao: string | null
          natureza: string | null
          origem: string | null
          raw_id: number | null
          status: string | null
          tipo: string | null
          unidade: string | null
          valor: number | null
        }
        Relationships: []
      }
      fluxo_caixa_diario: {
        Row: {
          dia: string | null
          entrada_projetada: number | null
          evento: string | null
          mes: string | null
          resultado_dia: number | null
          resultado_real: number | null
          saida_projetada: number | null
          saldo: number | null
          tipo: string | null
          tipo_dia: string | null
        }
        Relationships: []
      }
      mv_conciliacao_contabil: {
        Row: {
          ano_mes: string | null
          atualizado_em: string | null
          categoria: string | null
          contraparte_confere: boolean | null
          contraparte_nome: string | null
          data_caixa: string | null
          data_hora: string | null
          dias_diferenca: number | null
          dre_grupo: string | null
          espera_zerar: boolean | null
          evidencia_reversao: string | null
          fornecedor: string | null
          minutos_intervalo: number | null
          nivel_reversao: string | null
          origem: string | null
          par_categoria: string | null
          par_contraparte: string | null
          par_data: string | null
          par_data_hora: string | null
          par_origem: string | null
          par_raw_id: number | null
          par_valor: number | null
          possui_horario: boolean | null
          qtd_candidatos: number | null
          raw_id: number | null
          status_conciliacao: string | null
          tipo: string | null
          valor: number | null
        }
        Relationships: []
      }
      mv_despesa_diaria: {
        Row: {
          categoria: string | null
          dia: string | null
          fornecedor: string | null
          grupo: string | null
          lancamentos: number | null
          valor: number | null
        }
        Relationships: []
      }
      mv_despesa_mensal: {
        Row: {
          ano_mes: string | null
          categoria: string | null
          fornecedor: string | null
          grupo: string | null
          lancamentos: number | null
          mes: string | null
          valor: number | null
        }
        Relationships: []
      }
      mv_fluxo_caixa_diario: {
        Row: {
          dia: string | null
          entrada_projetada: number | null
          evento: string | null
          mes: string | null
          resultado_dia: number | null
          resultado_real: number | null
          saida_projetada: number | null
          saldo: number | null
          tipo: string | null
          tipo_dia: string | null
        }
        Relationships: []
      }
      painel_cargas: {
        Row: {
          fontes: string | null
          quando: string | null
        }
        Relationships: []
      }
      painel_colchao_despesa_fixa: {
        Row: {
          colchao: number | null
          contas_abertas: number | null
          dias_restantes: number | null
          ja_realizado: number | null
          media_tipica: number | null
          mes: string | null
          valor_dia: number | null
        }
        Relationships: []
      }
      painel_composicao_despesa: {
        Row: {
          ano_mes: string | null
          grupo: string | null
          mes: string | null
          valor: number | null
        }
        Relationships: []
      }
      painel_diario: {
        Row: {
          dia: string | null
          mes: string | null
          meta_dia: number | null
          meta_mes: number | null
          peso_total: number | null
          projecao_fechamento: number | null
          venda_dia: number | null
        }
        Relationships: []
      }
      painel_dre_cascata: {
        Row: {
          ano_mes: string | null
          capex: number | null
          cmv: number | null
          cmv_perc: number | null
          contabil: number | null
          impostos: number | null
          infraestrutura: number | null
          margem_contribuicao: number | null
          margem_liq_perc: number | null
          margem_op_perc: number | null
          marketing: number | null
          mc_perc: number | null
          mes: string | null
          nao_categorizado: number | null
          nao_operacional: number | null
          pessoal: number | null
          pessoal_perc: number | null
          receita: number | null
          resultado_liquido: number | null
          resultado_operacional: number | null
        }
        Relationships: []
      }
      painel_fluxo_caixa: {
        Row: {
          dia: string | null
          entrada_projetada: number | null
          resultado_dia: number | null
          saida_projetada: number | null
          saldo: number | null
          saldo_projetado: number | null
          saldo_real: number | null
          tipo: string | null
        }
        Relationships: []
      }
      painel_margem_contribuicao: {
        Row: {
          ano_mes: string | null
          mc_perc: number | null
          mes: string | null
        }
        Relationships: []
      }
      painel_meta_real_mensal: {
        Row: {
          ano: number | null
          ano_mes: string | null
          mes: string | null
          mes_num: number | null
          meta: number | null
          perc_atingido: number | null
          realizado: number | null
        }
        Insert: {
          ano?: never
          ano_mes?: never
          mes?: string | null
          mes_num?: never
          meta?: number | null
          perc_atingido?: never
          realizado?: never
        }
        Update: {
          ano?: never
          ano_mes?: never
          mes?: string | null
          mes_num?: never
          meta?: number | null
          perc_atingido?: never
          realizado?: never
        }
        Relationships: []
      }
      painel_recebimento_canal: {
        Row: {
          ano_mes: string | null
          canal: string | null
          qtd: number | null
          valor: number | null
        }
        Relationships: []
      }
      painel_recebimento_hora: {
        Row: {
          ano_mes: string | null
          hora: number | null
          qtd: number | null
          valor: number | null
        }
        Relationships: []
      }
      painel_recebimento_resumo: {
        Row: {
          ano_mes: string | null
          mes: string | null
          qtd_transacoes: number | null
          recebido_total: number | null
          ticket_transacao: number | null
        }
        Relationships: []
      }
      painel_resumo_mensal: {
        Row: {
          ano: number | null
          ano_mes: string | null
          cmv: number | null
          cmv_perc: number | null
          despesa: number | null
          faturamento: number | null
          faturamento_proj: number | null
          margem_perc: number | null
          mes: string | null
          meta: number | null
          perc_meta: number | null
          pessoal: number | null
          pessoal_perc: number | null
          qtd_vendas: number | null
          receita: number | null
          resultado: number | null
          saldo_fim: number | null
          saldo_situacao: string | null
          ticket_medio: number | null
        }
        Relationships: []
      }
      painel_saldo_atual: {
        Row: {
          data_comp: string | null
          data_ref: string | null
          saldo_atual: number | null
          saldo_comp: number | null
        }
        Relationships: []
      }
      painel_saldo_fim_mes: {
        Row: {
          ano_mes: string | null
          mes: string | null
          saldo_fim: number | null
          situacao: string | null
        }
        Insert: {
          ano_mes?: string | null
          mes?: string | null
          saldo_fim?: never
          situacao?: never
        }
        Update: {
          ano_mes?: string | null
          mes?: string | null
          saldo_fim?: never
          situacao?: never
        }
        Relationships: []
      }
      painel_saldo_por_conta: {
        Row: {
          conta: string | null
          data_ref: string | null
          saldo: number | null
        }
        Relationships: []
      }
      painel_ultima_carga: {
        Row: {
          ultima: string | null
        }
        Relationships: []
      }
      peso_mensal: {
        Row: {
          mes: string | null
          peso_total: number | null
        }
        Relationships: []
      }
      projecao_despesa_direta: {
        Row: {
          dia: string | null
          valor: number | null
        }
        Relationships: []
      }
      projecao_despesa_fixa: {
        Row: {
          dia: string | null
          valor: number | null
        }
        Relationships: []
      }
      projecao_venda_diaria: {
        Row: {
          dia: string | null
          mes: string | null
          peso: number | null
          tipo: string | null
          venda: number | null
        }
        Relationships: []
      }
      recebimento_conhecido: {
        Row: {
          dia: string | null
          valor: number | null
        }
        Relationships: []
      }
      recebimento_projetado: {
        Row: {
          dia: string | null
          valor: number | null
        }
        Relationships: []
      }
      recebimento_stone_net: {
        Row: {
          bandeira: string | null
          bruto_net: number | null
          data_venda: string | null
          id: number | null
          produto: string | null
        }
        Relationships: []
      }
      recebimento_transacao_net: {
        Row: {
          bandeira: string | null
          bruto_net: number | null
          data_venda: string | null
          fonte: string | null
          id: number | null
          produto: string | null
        }
        Relationships: []
      }
      saldo_anchor: {
        Row: {
          data_ref: string | null
          dinheiro_pendente: number | null
          saldo_bb: number | null
          saldo_stone: number | null
          saldo_total: number | null
        }
        Relationships: []
      }
      saldo_mensal_calculado: {
        Row: {
          ano_mes: string | null
          mes: string | null
          saldo_fim: number | null
          situacao: string | null
        }
        Relationships: []
      }
      tendencia_mes: {
        Row: {
          dia_ref: string | null
          mes: string | null
          meta: number | null
          meta_por_ponto_peso: number | null
          peso_decorrido: number | null
          peso_total: number | null
          tendencia: number | null
          vendido: number | null
        }
        Relationships: []
      }
      venda_diaria: {
        Row: {
          bruto: number | null
          dia: string | null
          qtd_vendas: number | null
        }
        Relationships: []
      }
    }
    Functions: {
      admin_listar_conta: {
        Args: never
        Returns: {
          ativa: boolean
          banco: string | null
          id: number
          nome: string
          saldo_base: number
          saldo_data_base: string
          saldo_metodo: string
          unidade_id: number | null
        }[]
        SetofOptions: {
          from: "*"
          to: "conta"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      admin_listar_fonte_financeira: {
        Args: never
        Returns: {
          ativa: boolean
          atualizado_em: string
          atualizado_por: string | null
          chave: string
          considerar_desde: string | null
          conta_id: number | null
          entra_caixa: boolean
          entra_caixa_historico: boolean
          entra_dre: boolean
          entra_faturamento: boolean
          nome: string
          saldo_adaptador: string
        }[]
        SetofOptions: {
          from: "*"
          to: "fonte_financeira"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      admin_listar_grupo_variavel: {
        Args: never
        Returns: {
          grupo: string
          variavel: boolean
        }[]
        SetofOptions: {
          from: "*"
          to: "grupo_variavel"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      admin_listar_historico_parametros: {
        Args: { p_limite?: number }
        Returns: {
          alterado_em: string
          alterado_por: string
          chave: string
          valor_anterior: number
          valor_novo: number
        }[]
      }
      admin_listar_meta_mensal: {
        Args: never
        Returns: {
          mes: string
          meta_bruta: number
          unidade: string
        }[]
        SetofOptions: {
          from: "*"
          to: "meta_mensal"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      admin_listar_parametros: {
        Args: never
        Returns: {
          chave: string
          descricao: string | null
          grupo: string
          ordem: number
          unidade_medida: string
          valor: number
          valor_max: number | null
          valor_min: number | null
        }[]
        SetofOptions: {
          from: "*"
          to: "parametros"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      admin_listar_peso_dia_semana: {
        Args: never
        Returns: {
          dia_nome: string
          dow: number
          peso: number
        }[]
        SetofOptions: {
          from: "*"
          to: "peso_dia_semana"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      admin_listar_recebimento_regra: {
        Args: never
        Returns: {
          dias: number
          forma: string
          percentual: number
          taxa: number
        }[]
        SetofOptions: {
          from: "*"
          to: "recebimento_regra"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      admin_listar_saldo_inicial: {
        Args: never
        Returns: {
          conta: string
          data_base: string
          obs: string | null
          saldo: number
        }[]
        SetofOptions: {
          from: "*"
          to: "saldo_inicial"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      admin_listar_stone_conta: {
        Args: never
        Returns: {
          ativa: boolean
          atualizado_em: string
          atualizado_por: string | null
          conta_id: number
          descricao: string | null
          entra_faturamento: boolean
          stonecode: string
        }[]
        SetofOptions: {
          from: "*"
          to: "stone_conta"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      admin_listar_unidade: {
        Args: never
        Returns: {
          ativa: boolean
          id: number
          nome: string
        }[]
        SetofOptions: {
          from: "*"
          to: "unidade"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      admin_obter_configuracao_empresa: {
        Args: never
        Returns: {
          atualizado_em: string
          nome: string
          subtitulo: string
        }[]
      }
      admin_obter_configuracao_operacional: {
        Args: never
        Returns: {
          atualizado_em: string
          conferencia_deposito_desde: string
          conta_deposito_id: number
          deposito_descricao_padrao: string
          fuso_horario: string
          unidade_exibicao: string
          unidade_id: number
          unidade_nome: string
        }[]
      }
      admin_salvar_configuracao_empresa: {
        Args: { p_nome: string; p_subtitulo: string }
        Returns: {
          atualizado_em: string
          nome: string
          subtitulo: string
        }[]
      }
      admin_salvar_configuracao_operacional: {
        Args: {
          p_conferencia_deposito_desde: string
          p_conta_deposito_id: number
          p_deposito_descricao_padrao: string
          p_fuso_horario: string
          p_unidade_exibicao: string
          p_unidade_id: number
        }
        Returns: {
          atualizado_em: string
          atualizado_por: string | null
          conferencia_deposito_desde: string
          conta_deposito_id: number | null
          deposito_descricao_padrao: string
          fuso_horario: string
          singleton: boolean
          unidade_exibicao: string
          unidade_principal_id: number
        }
        SetofOptions: {
          from: "*"
          to: "configuracao_operacional"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      admin_salvar_conta_com_saldo: {
        Args: {
          p_ativa: boolean
          p_banco: string
          p_id: number
          p_nome: string
          p_saldo_base: number
          p_saldo_data_base: string
          p_saldo_metodo: string
          p_unidade_id: number
        }
        Returns: {
          ativa: boolean
          banco: string | null
          id: number
          nome: string
          saldo_base: number
          saldo_data_base: string
          saldo_metodo: string
          unidade_id: number | null
        }
        SetofOptions: {
          from: "*"
          to: "conta"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      admin_salvar_fonte_financeira_com_vigencia: {
        Args: {
          p_ativa: boolean
          p_chave: string
          p_considerar_desde: string
          p_conta_id: number
          p_entra_caixa: boolean
          p_entra_caixa_historico: boolean
          p_entra_dre: boolean
          p_entra_faturamento: boolean
          p_nome: string
          p_saldo_adaptador: string
        }
        Returns: {
          ativa: boolean
          atualizado_em: string
          atualizado_por: string | null
          chave: string
          considerar_desde: string | null
          conta_id: number | null
          entra_caixa: boolean
          entra_caixa_historico: boolean
          entra_dre: boolean
          entra_faturamento: boolean
          nome: string
          saldo_adaptador: string
        }
        SetofOptions: {
          from: "*"
          to: "fonte_financeira"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      admin_salvar_grupo_variavel: {
        Args: { p_grupo: string; p_variavel: boolean }
        Returns: {
          grupo: string
          variavel: boolean
        }
        SetofOptions: {
          from: "*"
          to: "grupo_variavel"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      admin_salvar_meta_mensal: {
        Args: { p_mes: string; p_meta_bruta: number; p_unidade: string }
        Returns: {
          mes: string
          meta_bruta: number
          unidade: string
        }
        SetofOptions: {
          from: "*"
          to: "meta_mensal"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      admin_salvar_parametro: {
        Args: { p_chave: string; p_valor: number }
        Returns: {
          chave: string
          descricao: string | null
          grupo: string
          ordem: number
          unidade_medida: string
          valor: number
          valor_max: number | null
          valor_min: number | null
        }
        SetofOptions: {
          from: "*"
          to: "parametros"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      admin_salvar_peso_dia_semana: {
        Args: { p_dow: number; p_peso: number }
        Returns: {
          dia_nome: string
          dow: number
          peso: number
        }
        SetofOptions: {
          from: "*"
          to: "peso_dia_semana"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      admin_salvar_recebimento_regra: {
        Args: {
          p_dias: number
          p_forma: string
          p_percentual: number
          p_taxa: number
        }
        Returns: {
          dias: number
          forma: string
          percentual: number
          taxa: number
        }
        SetofOptions: {
          from: "*"
          to: "recebimento_regra"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      admin_salvar_saldo_inicial: {
        Args: {
          p_conta: string
          p_data_base: string
          p_obs: string
          p_saldo: number
        }
        Returns: {
          conta: string
          data_base: string
          obs: string | null
          saldo: number
        }
        SetofOptions: {
          from: "*"
          to: "saldo_inicial"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      admin_salvar_stone_conta: {
        Args: {
          p_ativa: boolean
          p_conta_id: number
          p_descricao: string
          p_entra_faturamento: boolean
          p_stonecode: string
        }
        Returns: {
          ativa: boolean
          atualizado_em: string
          atualizado_por: string | null
          conta_id: number
          descricao: string | null
          entra_faturamento: boolean
          stonecode: string
        }
        SetofOptions: {
          from: "*"
          to: "stone_conta"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      admin_salvar_unidade: {
        Args: { p_ativa: boolean; p_id: number; p_nome: string }
        Returns: {
          ativa: boolean
          id: number
          nome: string
        }
        SetofOptions: {
          from: "*"
          to: "unidade"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      alterar_status_sangria: {
        Args: { p_acao: string; p_id: number }
        Returns: undefined
      }
      app_configuracao_empresa: {
        Args: never
        Returns: {
          nome: string
          subtitulo: string
        }[]
      }
      app_configuracao_operacional: {
        Args: never
        Returns: {
          parametros: Json
          unidade_codigo: string
          unidade_nome: string
        }[]
      }
      classificar_excecao: {
        Args: {
          p_categoria: string
          p_chave_tipo: string
          p_chave_valor: string
          p_fornecedor: string
        }
        Returns: number
      }
      classificar_transacao: {
        Args: { p_categoria: string; p_origem: string; p_raw_id: number }
        Returns: number
      }
      consultar_recalculo_saldo: { Args: { p_id: number }; Returns: Json }
      corrigir_classificacao: {
        Args: { p_categoria: string; p_id: number; p_tipo: string }
        Returns: undefined
      }
      decidir_conciliacao_contabil: {
        Args: {
          p_decisao: string
          p_origem_a: string
          p_origem_b: string
          p_raw_id_a: number
          p_raw_id_b: number
        }
        Returns: number
      }
      definir_acesso_usuario: {
        Args: { p_ativo?: boolean; p_papel: string; p_user_id: string }
        Returns: {
          ativo: boolean
          email: string
          papel: string
          user_id: string
        }[]
      }
      definir_permissao_pagina: {
        Args: { p_pagina: string; p_papeis: string[] }
        Returns: {
          pagina: string
          papeis: string[]
        }[]
      }
      desfazer_ajuste_conferencia_deposito: {
        Args: { p_id: number }
        Returns: undefined
      }
      desfazer_classificacao: {
        Args: { p_id: number; p_tipo: string }
        Returns: undefined
      }
      desfazer_classificacao_transacao_dia: {
        Args: { p_historico_id: number }
        Returns: undefined
      }
      desfazer_decisao_conciliacao_contabil: {
        Args: { p_decisao_id: number }
        Returns: undefined
      }
      desfazer_regra_de_para: {
        Args: { p_historico_id: number }
        Returns: number
      }
      excluir_pagamento_recorrente: {
        Args: { p_competencia: string; p_conta_id: number }
        Returns: undefined
      }
      exigir_admin: { Args: never; Returns: undefined }
      importar_csv_stone: {
        Args: { p_dry_run?: boolean; p_fonte: string; p_linhas: Json }
        Returns: Json
      }
      listar_calendario_financeiro: {
        Args: { p_mes: string }
        Returns: {
          despesa_nao_recorrente: number
          despesa_recorrente: number
          despesa_recorrente_nao_conciliada: number
          despesa_recorrente_registrada: number
          despesa_total: number
          dia: string
          dia_semana: number
          faturamento_acumulado: number
          faturamento_dia: number
          meta_acumulada: number
          meta_dia: number
          modo: string
          recebimento_credito: number
          recebimento_debito: number
          recebimento_pix: number
          recebimento_projetado: number
          recebimento_total: number
          saldo_caixa: number
          venda_credito: number
          venda_debito: number
          venda_dinheiro: number
          venda_extras: number
          venda_pix: number
        }[]
      }
      listar_contas_recorrentes: {
        Args: { p_competencia: string }
        Returns: {
          ativa: boolean
          atualizado_em: string
          atualizado_por_nome: string
          categoria: string
          conta_bancaria: string
          conta_id: number
          data_pagamento: string
          dia_vencimento: number
          incluir_totais: boolean
          media_3: number
          nome: string
          observacao: string
          pagamento_id: number
          situacao: string
          tipo: string
          unidade: string
          valor: number
        }[]
      }
      listar_despesas_dia: {
        Args: { p_dia: string }
        Returns: {
          categoria: string
          descricao: string
          valor: number
        }[]
      }
      listar_ranking_fornecedor: {
        Args: { p_ano_mes: string; p_meses_base?: number }
        Returns: {
          dia_corte: number
          fornecedor: string
          grupo: string
          lancamentos: number
          media: number
          meses_base: number
          meses_janela: number
          meses_presente: number
          pessoas: number
          valor: number
        }[]
      }
      listar_regras_de_para: {
        Args: {
          p_busca?: string
          p_categoria?: string
          p_chave_tipo?: string
          p_pagina?: number
          p_status?: string
          p_tamanho_pagina?: number
        }
        Returns: Json
      }
      listar_saldo_contas_dia: {
        Args: { p_dia: string }
        Returns: {
          conta: string
          conta_id: number
          saldo: number
          saldo_total: number
        }[]
      }
      normaliza_nome: { Args: { txt: string }; Returns: string }
      papel_usuario_atual: { Args: never; Returns: string }
      parametro_valor: {
        Args: { p_chave: string; p_padrao: number }
        Returns: number
      }
      prever_alteracao_de_para: {
        Args: {
          p_ativo: boolean
          p_categoria: string
          p_estado_token_esperado: string
          p_fornecedor: string
          p_id: number
        }
        Returns: Json
      }
      recalcular_saldo_fechamento: {
        Args: {
          p_data_max?: string
          p_data_min?: string
          p_meses_abertos?: number
        }
        Returns: {
          fim_recalculo: string
          inicio_recalculo: string
          limite_fechamento: string
          mensagem: string
          meses_processados: number
        }[]
      }
      refresh_painel: { Args: never; Returns: undefined }
      registrar_ajuste_conferencia_deposito: {
        Args: { p_data: string; p_motivo: string; p_valor: number }
        Returns: number
      }
      restaurar_classificacao_transacao_dia: {
        Args: {
          p_ajuste_atual_esperado: string
          p_ajuste_em_esperado: string
          p_ajuste_observacao_token_esperado: string
          p_categoria_atual_esperada: string
          p_origem: string
          p_raw_id: number
        }
        Returns: number
      }
      resumo_corte_caixa: {
        Args: never
        Returns: {
          corte_caixa: string
          dias_apos_corte: number
          resultado_apos_corte: number
          snapshot_saldo: string
        }[]
      }
      salvar_classificacao_transacao_dia: {
        Args: {
          p_ajuste_atual_esperado: string
          p_ajuste_em_esperado: string
          p_ajuste_observacao_token_esperado: string
          p_categoria: string
          p_categoria_atual_esperada: string
          p_origem: string
          p_raw_id: number
        }
        Returns: number
      }
      salvar_conta_recorrente: {
        Args: {
          p_ativa?: boolean
          p_categoria: string
          p_dia_vencimento: number
          p_id: number
          p_incluir_totais?: boolean
          p_nome: string
          p_tipo?: string
          p_unidade?: string
        }
        Returns: number
      }
      salvar_pagamento_recorrente: {
        Args: {
          p_competencia: string
          p_conta_bancaria: string
          p_conta_id: number
          p_data_pagamento: string
          p_observacao?: string
          p_sem_movimento?: boolean
          p_valor: number
        }
        Returns: number
      }
      salvar_regra_de_para: {
        Args: {
          p_ativo: boolean
          p_categoria: string
          p_estado_token_esperado: string
          p_fornecedor: string
          p_id: number
          p_impacto_token_esperado: string
        }
        Returns: Json
      }
      salvar_sangria: {
        Args: { p_data: string; p_unidade: string; p_valor: number }
        Returns: number
      }
      sincronizar_historico_de_para: { Args: never; Returns: number }
      so_digitos: { Args: { txt: string }; Returns: string }
      solicitar_recalculo_saldo: {
        Args: { p_data_max?: string; p_data_min: string }
        Returns: Json
      }
      solicitar_refresh_painel: { Args: never; Returns: string }
      unaccent: { Args: { "": string }; Returns: string }
      unidade_principal_nome: { Args: never; Returns: string }
      usuario_pode_acessar_alguma_pagina: {
        Args: { p_paginas: string[] }
        Returns: boolean
      }
      usuario_pode_acessar_pagina: {
        Args: { p_pagina: string }
        Returns: boolean
      }
      usuario_tem_papel: { Args: { p_papeis: string[] }; Returns: boolean }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const

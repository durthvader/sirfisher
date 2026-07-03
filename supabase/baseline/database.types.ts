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
      conta: {
        Row: {
          ativa: boolean
          banco: string | null
          id: number
          nome: string
          unidade_id: number | null
        }
        Insert: {
          ativa?: boolean
          banco?: string | null
          id?: never
          nome: string
          unidade_id?: number | null
        }
        Update: {
          ativa?: boolean
          banco?: string | null
          id?: never
          nome?: string
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
      parametros: {
        Row: {
          chave: string
          descricao: string | null
          valor: number
        }
        Insert: {
          chave: string
          descricao?: string | null
          valor: number
        }
        Update: {
          chave?: string
          descricao?: string | null
          valor?: number
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
          criado_em: string
          data: string
          id: number
          observacao: string | null
          unidade: string
          valor: number
        }
        Insert: {
          criado_em?: string
          data: string
          id?: never
          observacao?: string | null
          unidade?: string
          valor: number
        }
        Update: {
          criado_em?: string
          data?: string
          id?: never
          observacao?: string | null
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
          empresa: string | null
          fornecedor: string | null
          movimentacao: string | null
          natureza: string | null
          origem: string | null
          raw_id: number | null
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
          empresa: string | null
          fornecedor: string | null
          movimentacao: string | null
          natureza: string | null
          origem: string | null
          raw_id: number | null
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
          natureza: string | null
          qtd_lancamentos: number | null
          total: number | null
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
          n_parcelas: number | null
          n_venda: number | null
          primeiro_venc: string | null
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
          natureza: string | null
          qtd_lancamentos: number | null
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
      painel_dre_executivo: {
        Row: {
          ano: number | null
          ano_mes: string | null
          despesa: number | null
          mes: string | null
          receita: number | null
          resultado: number | null
          unidade: string | null
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
      painel_tendencia_diaria: {
        Row: {
          dia: string | null
          mes: string | null
          meta: number | null
          peso_acum: number | null
          peso_total: number | null
          projecao_fechamento: number | null
          venda_dia: number | null
          vendido_acum: number | null
        }
        Relationships: []
      }
      painel_ultima_carga: {
        Row: {
          ultima: string | null
        }
        Relationships: []
      }
      painel_venda_mes_atual: {
        Row: {
          dia: string | null
          meta_acumulada: number | null
          meta_dia: number | null
          peso: number | null
          projecao_acumulada: number | null
          real_acumulado: number | null
          tipo: string | null
          venda_projetada_dia: number | null
          venda_real_dia: number | null
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
      saldo_anchor: {
        Row: {
          data_ref: string | null
          saldo_bb: number | null
          saldo_stone: number | null
          saldo_total: number | null
        }
        Relationships: []
      }
      saldo_mensal: {
        Row: {
          ano_mes: string | null
          mes: string | null
          saldo_fim: number | null
          situacao: string | null
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
      saldo_stone_atual: {
        Row: {
          conta_id: number | null
          data_ref: string | null
          saldo: number | null
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
      vendas_diaria: {
        Row: {
          bruto: number | null
          dia: string | null
          liquido: number | null
          qtd_vendas: number | null
        }
        Relationships: []
      }
    }
    Functions: {
      normaliza_nome: { Args: { txt: string }; Returns: string }
      papel_usuario_atual: { Args: never; Returns: string }
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
      so_digitos: { Args: { txt: string }; Returns: string }
      unaccent: { Args: { "": string }; Returns: string }
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

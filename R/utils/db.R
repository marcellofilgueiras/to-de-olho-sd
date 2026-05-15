# utils/db.R
# Funções de acesso ao SQLite — Tô de Olho Santos Dumont

DB_PATH <- here::here("data", "tdo_sd.sqlite")

#' Abre conexão com o banco (cria se não existir)
conectar_db <- function() {
  DBI::dbConnect(RSQLite::SQLite(), DB_PATH)
}

#' Inicializa o schema do banco se as tabelas não existirem
inicializar_schema <- function(con) {
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS proposicoes (
      prop_id           TEXT PRIMARY KEY,
      numero            TEXT,
      ano               INTEGER,
      tipo_codigo       TEXT,
      tipo_nome         TEXT,
      pdf_url           TEXT,
      autor_raw         TEXT,
      autor_normalizado TEXT,
      ementa            TEXT,
      destinatario      TEXT,
      tema_principal    TEXT,
      fonte             TEXT,
      coletado_em       TEXT,
      UNIQUE (tipo_codigo, numero, ano)
    );
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS vereadores (
      id                INTEGER PRIMARY KEY,
      nome              TEXT,
      nome_normalizado  TEXT UNIQUE,
      partido_atual     TEXT,
      legislatura       TEXT,
      url_perfil        TEXT,
      foto_url          TEXT
    );
  ")

  DBI::dbExecute(con, "
    CREATE INDEX IF NOT EXISTS idx_prop_autor
      ON proposicoes(autor_normalizado);
  ")

  DBI::dbExecute(con, "
    CREATE INDEX IF NOT EXISTS idx_prop_ano_tipo
      ON proposicoes(ano, tipo_codigo);
  ")

  invisible(con)
}

#' Grava proposições no banco (upsert por prop_id)
gravar_proposicoes <- function(con, df) {
  DBI::dbExecute(con, "
    INSERT OR REPLACE INTO proposicoes
      (prop_id, numero, ano, tipo_codigo, tipo_nome, pdf_url,
       autor_raw, autor_normalizado, ementa, destinatario,
       tema_principal, fonte, coletado_em)
    VALUES
      (:prop_id, :numero, :ano, :tipo_codigo, :tipo_nome, :pdf_url,
       :autor_raw, :autor_normalizado, :ementa, :destinatario,
       :tema_principal, :fonte, :coletado_em)
  ", params = df)
  invisible(nrow(df))
}

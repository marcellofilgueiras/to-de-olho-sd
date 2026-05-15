# R/02_consolidar.R
# Lê os arquivos brutos, normaliza e grava no SQLite.
# Idempotente: INSERT OR REPLACE por prop_id.

library(rvest)
library(dplyr)
library(tidyr)
library(stringi)
library(purrr)
library(yaml)
library(DBI)
library(RSQLite)
library(here)

source(here("R", "utils", "parse.R"))
source(here("R", "utils", "db.R"))

LEGISLATURA_INICIO <- 2025L  # filtrar apenas legislatura atual

con <- conectar_db()
on.exit(DBI::dbDisconnect(con), add = TRUE)
inicializar_schema(con)

# ── 1. Projetos de Lei ────────────────────────────────────────────────────────
arquivo_pls <- here("data", "raw", "projetos_de_lei.html")

if (!file.exists(arquivo_pls)) {
  warning("[02_consolidar] projetos_de_lei.html não encontrado — execute 01_baixar.R primeiro.")
} else {
  message("[02_consolidar] Processando projetos_de_lei.html ...")
  pls <- ler_pls_sd(arquivo_pls)

  pls <- pls |>
    filter(!is.na(numero), !is.na(ano), ano >= LEGISLATURA_INICIO) |>
    mutate(
      prop_id           = prop_id(tipo_codigo, numero, ano),
      autor_normalizado = normalizar_nome(coalesce(autor_raw, "")),
      destinatario      = NA_character_,
      tema_principal    = NA_character_,
      fonte             = "plenario",
      coletado_em       = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    )

  # Desnormalizar co-autoria (ex: "Vereadora X e Vereadora Y")
  pls <- pls |>
    mutate(autores_lista = strsplit(autor_raw, "\\s+[Ee]\\s+|\\s*/\\s*|,\\s*")) |>
    unnest_longer(autores_lista, values_to = "autor_raw_ind") |>
    mutate(
      autor_raw         = trimws(autor_raw_ind),
      autor_normalizado = normalizar_nome(autor_raw),
      prop_id           = prop_id(tipo_codigo, numero, ano)
    ) |>
    select(-autores_lista, -autor_raw_ind)

  df_pls <- pls |>
    select(prop_id, numero, ano, tipo_codigo, tipo_nome, pdf_url,
           autor_raw, autor_normalizado, ementa, destinatario,
           tema_principal, fonte, coletado_em)

  n <- gravar_proposicoes(con, df_pls)
  message(sprintf("[02_consolidar] %d registros de PLs gravados.", n))
}

# ── 2. Requerimentos e Moções (perfis dos vereadores) ─────────────────────────
urls_path        <- here("inst", "dicionarios", "urls_vereadores.yaml")
urls_vereadores  <- yaml::read_yaml(urls_path)

total_reqs <- 0L

for (v in urls_vereadores) {
  slug    <- v$slug
  nome    <- v$nome
  arquivo <- here("data", "raw", sprintf("vereador_%s.html", slug))

  if (!file.exists(arquivo)) {
    warning(sprintf("[02_consolidar] Arquivo não encontrado: %s", basename(arquivo)))
    next
  }

  message(sprintf("[02_consolidar] Processando vereador: %s ...", nome))

  dados <- tryCatch(
    ler_vereador_sd(arquivo, slug),
    error = function(e) {
      warning(sprintf("[02_consolidar] ERRO em %s: %s", slug, e$message))
      NULL
    }
  )

  if (is.null(dados) || nrow(dados) == 0) next

  dados <- dados |>
    filter(is.na(ano) | ano >= LEGISLATURA_INICIO) |>
    mutate(
      autor_raw         = nome,
      autor_normalizado = normalizar_nome(nome),
      tema_principal    = NA_character_,
      coletado_em       = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      numero            = coalesce(numero, paste0("sem-num-", row_number())),
      ano               = coalesce(ano, as.integer(format(Sys.Date(), "%Y"))),
      prop_id           = prop_id(tipo_codigo, numero, ano)
    )

  df_v <- dados |>
    select(prop_id, numero, ano, tipo_codigo, tipo_nome, pdf_url,
           autor_raw, autor_normalizado, ementa, destinatario,
           tema_principal, fonte, coletado_em)

  n <- gravar_proposicoes(con, df_v)
  total_reqs <- total_reqs + n
  message(sprintf("[02_consolidar]   %d registros gravados.", n))
}

message(sprintf("[02_consolidar] Total requerimentos/mocoes: %d", total_reqs))

# ── Verificação rápida ────────────────────────────────────────────────────────
contagem <- DBI::dbGetQuery(con, "
  SELECT ano, tipo_codigo, COUNT(*) AS n
  FROM proposicoes
  GROUP BY ano, tipo_codigo
  ORDER BY ano DESC, n DESC
")

message("\n[02_consolidar] Resumo do banco:")
print(contagem)
message("\n[02_consolidar] Concluido.")

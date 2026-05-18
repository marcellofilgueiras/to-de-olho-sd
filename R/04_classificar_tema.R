# R/04_classificar_tema.R
# Classifica proposições por tema usando dicionário regex.
# Três classificadores independentes:
#   1. classificar_pl()       → tema de Projetos de Lei
#   2. classificar_req_moc()  → detecta Requerimentos que são Moções
#   3. classificar_req_urbano() → subtipos de melhorias urbanas

library(yaml)
library(DBI)
library(RSQLite)
library(dplyr)
library(here)

source(here("R", "utils", "db.R"))

dic <- yaml::read_yaml(here("inst", "dicionarios", "classificacoes_sd.yaml"))

# ── Funções de classificação ─────────────────────────────────────────────────

#' Aplica um dicionário (lista de tema → lista de regex) a um texto.
#' Retorna o primeiro tema cujo padrão bater, ou NA.
classificar_por_dic <- function(texto, dicionario) {
  if (is.na(texto) || nchar(trimws(texto)) == 0) return(NA_character_)
  for (tema in names(dicionario)) {
    padroes <- dicionario[[tema]]
    for (p in padroes) {
      if (grepl(p, texto, ignore.case = TRUE, perl = TRUE)) {
        return(tema)
      }
    }
  }
  NA_character_
}

#' Classifica a ementa de um PL
classificar_pl <- function(ementa) {
  classificar_por_dic(ementa, dic$temas_pl)
}

#' Detecta se um REQ é uma moção (pesar, louvor, repúdio…)
#' Usa ementa + destinatario
classificar_req_moc <- function(ementa, destinatario) {
  texto <- paste(coalesce(ementa, ""), coalesce(destinatario, ""))
  classificar_por_dic(texto, dic$req_moc)
}

#' Classifica o subtipo de melhoria urbana de um REQ
classificar_req_urbano <- function(ementa) {
  classificar_por_dic(ementa, dic$req_urbano)
}

# ── Aplicar ao banco ──────────────────────────────────────────────────────────
con <- conectar_db()
on.exit(DBI::dbDisconnect(con), add = TRUE)

props <- DBI::dbGetQuery(con,
  "SELECT prop_id, tipo_codigo, ementa, destinatario FROM proposicoes"
)

message(sprintf("[04] %d proposições carregadas.", nrow(props)))

props <- props |>
  rowwise() |>
  mutate(
    tema_principal = case_when(
      # PLs: classificar pelo tema
      tipo_codigo %in% c("PL", "PLC", "PR", "PDL") ~
        classificar_pl(ementa),

      # REQs: primeiro checar se é moção, depois se é urbano
      tipo_codigo == "REQ" & !is.na(classificar_req_moc(ementa, destinatario)) ~
        classificar_req_moc(ementa, destinatario),

      tipo_codigo == "REQ" & !is.na(classificar_req_urbano(ementa)) ~
        classificar_req_urbano(ementa),

      TRUE ~ NA_character_
    )
  ) |>
  ungroup()

# ── Gravar resultado no banco ─────────────────────────────────────────────────
DBI::dbExecute(con, "UPDATE proposicoes SET tema_principal = NULL")

for (i in seq_len(nrow(props))) {
  if (!is.na(props$tema_principal[i])) {
    DBI::dbExecute(con,
      "UPDATE proposicoes SET tema_principal = ? WHERE prop_id = ?",
      params = list(props$tema_principal[i], props$prop_id[i])
    )
  }
}

# ── Resumo ────────────────────────────────────────────────────────────────────
resumo <- DBI::dbGetQuery(con, "
  SELECT tipo_codigo, tema_principal, COUNT(*) AS n
  FROM proposicoes
  WHERE tema_principal IS NOT NULL
  GROUP BY tipo_codigo, tema_principal
  ORDER BY tipo_codigo, n DESC
")

n_classif <- sum(!is.na(props$tema_principal))
n_total   <- nrow(props)
pct       <- round(100 * n_classif / n_total, 1)

message(sprintf("\n[04] Classificados: %d / %d (%.1f%%)\n", n_classif, n_total, pct))
print(resumo)
message("\n[04] Concluido.")

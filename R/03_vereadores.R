# R/03_vereadores.R
# Lê o CSV manual de vereadores e popula a tabela no SQLite.
# Idempotente: recria a tabela a cada execução.

library(readr)
library(dplyr)
library(stringi)
library(DBI)
library(RSQLite)
library(here)

source(here("R", "utils", "db.R"))
source(here("R", "utils", "parse.R"))

csv_path <- here("inst", "dicionarios", "vereadores_2025.csv")

if (!file.exists(csv_path)) {
  stop(sprintf("[03_vereadores] Arquivo nao encontrado: %s", csv_path))
}

vereadores <- read_csv(csv_path, show_col_types = FALSE) |>
  mutate(
    nome_normalizado = normalizar_nome(nome),
    legislatura      = "2025-2028"
  )

con <- conectar_db()
on.exit(DBI::dbDisconnect(con), add = TRUE)
inicializar_schema(con)

DBI::dbExecute(con, "DELETE FROM vereadores")
DBI::dbWriteTable(con, "vereadores", vereadores, append = TRUE)

n <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM vereadores")$n
message(sprintf("[03_vereadores] %d vereadores gravados.", n))

# Verificar JOIN com proposicoes
matches <- DBI::dbGetQuery(con, "
  SELECT v.nome, COUNT(p.prop_id) AS n_proposicoes
  FROM vereadores v
  LEFT JOIN proposicoes p ON p.autor_normalizado = v.nome_normalizado
  GROUP BY v.nome
  ORDER BY n_proposicoes DESC
")

message("\n[03_vereadores] Matches vereador <-> proposicoes:")
print(matches)

nao_match <- matches |> dplyr::filter(n_proposicoes == 0)
if (nrow(nao_match) > 0) {
  warning(sprintf(
    "[03_vereadores] %d vereador(es) SEM match: %s",
    nrow(nao_match),
    paste(nao_match$nome, collapse = ", ")
  ))
}

message("\n[03_vereadores] Concluido.")

# R/01_baixar.R
# Baixa a página de PLs e os perfis de cada vereador da Câmara de Santos Dumont.
# Idempotente: sobrescreve arquivos a cada execução.

library(httr2)
library(yaml)
library(here)

source(here("R", "utils", "http.R"))

dir.create(here("data", "raw"), recursive = TRUE, showWarnings = FALSE)

# ── Projetos de Lei (uma única página) ───────────────────────────────────────
destino_pls <- here("data", "raw", "projetos_de_lei.html")
message("[01_baixar] Baixando página de Projetos de Lei...")
baixar_pls(destino_pls)
message(sprintf("[01_baixar] PLs OK — %.1f KB", file.size(destino_pls) / 1e3))

# ── Perfis dos vereadores ─────────────────────────────────────────────────────
urls_path <- here("inst", "dicionarios", "urls_vereadores.yaml")
urls_vereadores <- yaml::read_yaml(urls_path)

for (v in urls_vereadores) {
  slug    <- v$slug
  url     <- v$url_perfil
  destino <- here("data", "raw", sprintf("vereador_%s.html", slug))

  message(sprintf("[01_baixar] Baixando perfil: %s -> %s", slug, url))
  tryCatch(
    baixar_vereador(url, destino),
    error = function(e) warning(sprintf("[01_baixar] ERRO em %s: %s", slug, e$message))
  )
  message(sprintf("[01_baixar] OK — %.1f KB", file.size(destino) / 1e3))
}

message("[01_baixar] Concluido.")

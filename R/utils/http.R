# utils/http.R
# Funções auxiliares de HTTP para o pipeline Tô de Olho — Santos Dumont

CMSD_BASE <- "https://www.camarasd.mg.gov.br"

UA <- paste0(
  "TodeOlhoSD/1.0 ",
  "(projeto civico de transparencia legislativa - Santos Dumont MG) ",
  "- contato: jfemdados@gmail.com"
)

#' Baixa a página de Projetos de Lei (WordPress, HTML completo)
#'
#' @param destino Caminho do arquivo de destino
#' @return Invisível: caminho salvo
baixar_pls <- function(destino) {
  httr2::request(paste0(CMSD_BASE, "/projetos-de-lei/")) |>
    httr2::req_user_agent(UA) |>
    httr2::req_retry(max_tries = 3, backoff = \(x) 2^x) |>
    httr2::req_throttle(rate = 10 / 60) |>
    httr2::req_perform(path = destino)
  invisible(destino)
}

#' Baixa a página de perfil de um vereador
#'
#' @param url_path Caminho relativo (ex: "/vereadores/flavio-faria/")
#' @param destino  Caminho do arquivo de destino
#' @return Invisível: caminho salvo
baixar_vereador <- function(url_path, destino) {
  httr2::request(paste0(CMSD_BASE, url_path)) |>
    httr2::req_user_agent(UA) |>
    httr2::req_retry(max_tries = 3, backoff = \(x) 2^x) |>
    httr2::req_throttle(rate = 10 / 60) |>
    httr2::req_perform(path = destino)
  invisible(destino)
}

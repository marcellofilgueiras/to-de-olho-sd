# utils/parse.R
# Funções de parse do HTML do site WordPress da Câmara de Santos Dumont
#
# Estrutura real da página de PLs:
#   <p>
#     <strong>PROJETO DE LEI Nº 25/2026<br>Autor: Vereadora X<br></strong>
#     "Ementa completa..." – <a href="pdf.pdf">Visualizar</a>
#   </p>
#
# Estrutura real dos perfis de vereadores (requerimentos):
#   <p>
#     <em><strong><a href="pdf.pdf">Requerimento Nº 25.021/2025</a>
#     – Destinatário: Secretaria X. </strong></em>
#     Texto da ementa/descrição.
#   </p>

library(rvest)
library(purrr)
library(stringi)
library(dplyr)

# Mapeamento tipo_nome -> tipo_codigo
TIPO_CODIGOS_SD <- c(
  "PROJETO DE LEI COMPLEMENTAR"    = "PLC",
  "PROJETO DE LEI"                 = "PL",
  "PROJETO DE RESOLUÇÃO"           = "PR",
  "PROJETO DE DECRETO LEGISLATIVO" = "PDL",
  "REQUERIMENTO"                   = "REQ",
  "INDICAÇÃO"                      = "IND"
)

#' Normaliza nome de autor para JOIN com tabela vereadores
#'
#' Remove título (Vereador/a, Dr.), acentos, caixa alta, espaços extras.
normalizar_nome <- function(x) {
  x |>
    gsub("(?i)^(vereador[ae]?s?\\s+|dr\\.?\\s+|dra\\.?\\s+)", "", x = _, perl = TRUE) |>
    stringi::stri_trans_general("Latin-ASCII") |>
    tolower() |>
    trimws() |>
    gsub("\\s+", " ", x = _)
}

#' Gera prop_id único a partir de tipo, número e ano
prop_id <- function(tipo_codigo, numero, ano) {
  paste0(tipo_codigo, "-", gsub("\\.", "", numero), "-", ano)
}

#' Lê a página de Projetos de Lei do WordPress da Câmara de SD
#'
#' Cada PL está em um <p> com um <strong> como cabeçalho e a ementa
#' como texto livre logo após o </strong>, antes do link PDF.
#'
#' @param caminho Caminho do arquivo HTML baixado
#' @return data.frame com as proposições extraídas
ler_pls_sd <- function(caminho) {
  html    <- rvest::read_html(caminho, encoding = "UTF-8")
  content <- html |> rvest::html_element("article, .entry-content, main")
  paras   <- content |> rvest::html_elements("p")

  purrr::map_dfr(paras, function(p) {
    strong <- p |> rvest::html_element("strong")
    if (length(strong) == 0 || is.na(strong)) return(NULL)

    strong_txt <- strong |> rvest::html_text2()

    # Só processar se começar com um tipo de proposição
    if (!grepl("^PROJETO DE (LEI|RESOLU|DECRETO)", strong_txt, ignore.case = FALSE)) {
      return(NULL)
    }

    # Tipo
    tipo_nome <- regmatches(
      strong_txt,
      regexpr("PROJETO DE LEI COMPLEMENTAR|PROJETO DE LEI|PROJETO DE RESOLUÇÃO|PROJETO DE DECRETO LEGISLATIVO",
              strong_txt)
    )
    tipo_nome  <- toupper(trimws(tipo_nome))
    tipo_codigo <- TIPO_CODIGOS_SD[tipo_nome]
    if (is.na(tipo_codigo)) tipo_codigo <- "OUTRO"

    # Número: "Nº 25" ou "N° 25"
    numero <- regmatches(strong_txt, regexpr("N[°º]\\s*(\\d+)", strong_txt, perl = TRUE))
    numero <- trimws(gsub("N[°º]\\s*", "", numero, perl = TRUE))
    if (length(numero) == 0 || numero == "") return(NULL)

    # Ano: "/2025" ou "/2026"
    ano_m <- regmatches(strong_txt, regexpr("/(\\d{4})", strong_txt, perl = TRUE))
    ano   <- as.integer(gsub("/", "", ano_m))
    if (length(ano) == 0 || is.na(ano)) return(NULL)

    # Autor: linha "Autor:" ou "Autora:" ou "Autor(a):" ou "Autores:"
    autor_m <- regmatches(
      strong_txt,
      regexpr("(?i)Autor(?:a|es|\\(a\\))?:\\s*(.+)", strong_txt, perl = TRUE)
    )
    autor_raw <- trimws(gsub("(?i)Autor(?:a|es|\\(a\\))?:\\s*", "", autor_m, perl = TRUE))
    if (length(autor_raw) == 0 || autor_raw == "") autor_raw <- NA_character_

    # Ementa: nós de texto do <p> que NÃO estão dentro do <strong>
    txt_nodes <- xml2::xml_find_all(p, ".//text()[not(ancestor::strong)]")
    ementa_raw <- paste(xml2::xml_text(txt_nodes), collapse = "")
    ementa <- trimws(gsub("\\s*[–-]\\s*Visualizar\\s*$", "", ementa_raw, perl = TRUE))
    ementa <- gsub('“|”|^"|"$', "", ementa)   # remover aspas tipográficas e retas
    ementa <- trimws(ementa)
    if (nchar(ementa) < 5) ementa <- NA_character_

    # PDF
    pdf_url <- p |> rvest::html_element("a") |> rvest::html_attr("href")
    if (length(pdf_url) == 0) pdf_url <- NA_character_

    data.frame(
      numero = numero, ano = ano, tipo_codigo = tipo_codigo, tipo_nome = tipo_nome,
      autor_raw = autor_raw, ementa = ementa, pdf_url = pdf_url,
      stringsAsFactors = FALSE
    )
  })
}

#' Lê a página de perfil de um vereador (requerimentos)
#'
#' Cada requerimento está em um <p> com o formato:
#'   <em><strong><a>Requerimento Nº NN.NNN/YYYY</a> – Destinatário: X.</strong></em> Ementa.
#'
#' @param caminho  Caminho do arquivo HTML
#' @param slug     Slug do vereador (para a coluna fonte)
#' @return data.frame com os requerimentos extraídos
ler_vereador_sd <- function(caminho, slug) {
  html    <- rvest::read_html(caminho, encoding = "UTF-8")
  content <- html |> rvest::html_element("article, .entry-content, main")
  paras   <- content |> rvest::html_elements("p")

  reqs <- purrr::map_dfr(paras, function(p) {
    p_txt <- p |> rvest::html_text2()

    # Só processar parágrafos que contêm "Requerimento Nº"
    if (!grepl("Requerimento\\s+N[°º]", p_txt, ignore.case = TRUE)) return(NULL)

    # Número e ano — estão no texto do <a> ou no texto do parágrafo
    num_m <- regmatches(p_txt, regexpr("([0-9]+\\.?[0-9]*)\\s*/\\s*(\\d{4})", p_txt, perl = TRUE))
    if (length(num_m) == 0) return(NULL)

    numero <- gsub("\\s*/\\s*\\d{4}", "", num_m, perl = TRUE)
    ano    <- as.integer(regmatches(num_m, regexpr("\\d{4}$", num_m, perl = TRUE)))

    # Destinatário — entre "Destinatário:" e o próximo ponto final
    dest_m <- regmatches(p_txt, regexpr("(?i)Destinat[aá]rio:\\s*([^.]+)", p_txt, perl = TRUE))
    dest   <- trimws(gsub("(?i)Destinat[aá]rio:\\s*", "", dest_m, perl = TRUE))
    if (length(dest) == 0) dest <- NA_character_

    # Ementa — texto após o bloco <em><strong>...</strong></em>
    # O bloco <em> contém o número + destinatário; a ementa vem depois
    em_node  <- p |> rvest::html_element("em")
    em_txt   <- if (!is.na(em_node)) rvest::html_text2(em_node) else ""
    ementa   <- trimws(sub(paste0("^\\Q", em_txt, "\\E\\s*"), "", p_txt, perl = TRUE))
    if (length(ementa) == 0 || nchar(ementa) < 5) ementa <- NA_character_

    # PDF URL
    pdf_url <- p |> rvest::html_element("a") |> rvest::html_attr("href")
    if (length(pdf_url) == 0) pdf_url <- NA_character_

    data.frame(
      numero = numero, ano = ano,
      tipo_codigo = "REQ", tipo_nome = "Requerimento",
      autor_raw = NA_character_, ementa = ementa,
      destinatario = dest, pdf_url = pdf_url,
      stringsAsFactors = FALSE
    )
  })

  if (nrow(reqs) > 0) reqs$fonte <- slug
  reqs
}

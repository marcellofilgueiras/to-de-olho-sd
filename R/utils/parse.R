# utils/parse.R
# Funções de parse do HTML do site WordPress da Câmara de Santos Dumont

#' Normaliza nome de autor para JOIN com tabela vereadores
#'
#' Remove acentos, converte para minúsculas, remove título (Vereador/a).
#'
#' @param x Vetor de caracteres
#' @return Vetor normalizado
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

# Mapeamento tipo_nome -> tipo_codigo
TIPO_CODIGOS_SD <- c(
  "PROJETO DE LEI COMPLEMENTAR"    = "PLC",
  "PROJETO DE LEI"                 = "PL",
  "PROJETO DE RESOLUÇÃO"           = "PR",
  "PROJETO DE DECRETO LEGISLATIVO" = "PDL",
  "REQUERIMENTO"                   = "REQ",
  "MOÇÃO"                          = "MOC",
  "MOÇÃO DE LOUVOR"                = "MOC",
  "MOÇÃO DE PESAR"                 = "MOC",
  "MOÇÃO DE PESAR COLETIVA"        = "MOC",
  "MOÇÃO DE PARABENIZAÇÃO"         = "MOC",
  "INDICAÇÃO"                      = "IND"
)

#' Lê a página de Projetos de Lei do WordPress da Câmara de SD
#'
#' O site serve uma página WordPress com entradas no formato:
#'   <strong>PROJETO DE LEI Nº NN/YYYY<br>Autor: Nome<br></strong>
#'   "Ementa..." – <a href="pdf_url">Visualizar</a>
#'
#' @param caminho Caminho do arquivo HTML baixado
#' @return data.frame com proposições extraídas
ler_pls_sd <- function(caminho) {
  html <- rvest::read_html(caminho, encoding = "UTF-8")

  # Extrair conteúdo principal
  content <- html |>
    rvest::html_element("article, .entry-content, main, .page-content")

  if (is.null(content) || length(content) == 0) {
    content <- html
  }

  # Pegar todos os blocos <strong> — cada um é um projeto
  strong_nodes <- content |> rvest::html_elements("strong")

  resultados <- purrr::map_dfr(strong_nodes, function(node) {
    texto_strong <- node |> rvest::html_text2()

    # Verificar se é um cabeçalho de proposição
    m_tipo <- regmatches(
      texto_strong,
      regexpr(
        "^(PROJETO DE LEI COMPLEMENTAR|PROJETO DE LEI|PROJETO DE RESOLUÇÃO|PROJETO DE DECRETO LEGISLATIVO)\\s+N[Oº][°\\s]*(\\d+)/(\\d{4})",
        texto_strong, perl = TRUE, ignore.case = FALSE
      )
    )

    if (length(m_tipo) == 0 || m_tipo == "") return(NULL)

    # Extrair tipo
    tipo_nome <- regmatches(
      texto_strong,
      regexpr("PROJETO DE LEI COMPLEMENTAR|PROJETO DE LEI|PROJETO DE RESOLUÇÃO|PROJETO DE DECRETO LEGISLATIVO",
              texto_strong)
    )
    tipo_nome <- toupper(trimws(tipo_nome))
    tipo_codigo <- TIPO_CODIGOS_SD[tipo_nome]
    if (is.na(tipo_codigo)) tipo_codigo <- "OUTRO"

    # Extrair número
    numero <- regmatches(
      texto_strong,
      regexpr("N[Oº][°\\s]*(\\d+)/", texto_strong, perl = TRUE)
    )
    numero <- gsub("N[Oº][°\\s]*([0-9]+)/", "\\1", numero, perl = TRUE)

    # Extrair ano
    ano <- regmatches(
      texto_strong,
      regexpr("/(\\d{4})", texto_strong, perl = TRUE)
    )
    ano <- as.integer(gsub("/", "", ano))

    # Extrair autor (linha "Autor: ..." ou "Autores: ...")
    autor_raw <- regmatches(
      texto_strong,
      regexpr("(?i)Autores?:\\s*([^\\n]+)", texto_strong, perl = TRUE)
    )
    autor_raw <- gsub("(?i)Autores?:\\s*", "", autor_raw, perl = TRUE)
    autor_raw <- trimws(autor_raw)
    if (length(autor_raw) == 0 || autor_raw == "") autor_raw <- NA_character_

    # Tentar pegar o próximo nó para extrair ementa e PDF
    # rvest não tem sibling direto fácil; vamos extrair do pai
    pai <- node |> rvest::html_element(xpath = "..")
    texto_pai <- pai |> rvest::html_text2()

    # Ementa: texto entre aspas no parágrafo após o strong
    ementa <- regmatches(
      texto_pai,
      regexpr('"([^"]+)"', texto_pai, perl = TRUE)
    )
    ementa <- gsub('^"|"$', "", ementa)
    ementa <- trimws(ementa)
    if (length(ementa) == 0 || ementa == "") ementa <- NA_character_

    # PDF URL: link do pai
    pdf_url <- pai |>
      rvest::html_element("a") |>
      rvest::html_attr("href")
    if (length(pdf_url) == 0) pdf_url <- NA_character_

    data.frame(
      numero      = numero,
      ano         = ano,
      tipo_codigo = tipo_codigo,
      tipo_nome   = tipo_nome,
      autor_raw   = autor_raw,
      ementa      = ementa,
      pdf_url     = pdf_url,
      stringsAsFactors = FALSE
    )
  })

  resultados
}

#' Lê a página de perfil de um vereador (requerimentos e moções)
#'
#' @param caminho  Caminho do arquivo HTML
#' @param slug     Identificador do vereador (para a coluna fonte)
#' @return data.frame com requerimentos e moções extraídos
ler_vereador_sd <- function(caminho, slug) {
  html <- rvest::read_html(caminho, encoding = "UTF-8")

  content <- html |>
    rvest::html_element("article, .entry-content, main, .page-content")
  if (is.null(content) || length(content) == 0) content <- html

  texto_completo <- content |> rvest::html_text2()
  links_pdf <- content |>
    rvest::html_elements("a") |>
    rvest::html_attr("href")
  links_pdf <- links_pdf[grepl("\\.pdf$", links_pdf, ignore.case = TRUE)]

  # ── Requerimentos ───────────────────────────────────────────────────────────
  # Formato: "Requerimento Nº 25.021/2025 – Destinatário: Nome. Ementa texto."
  req_matches <- gregexpr(
    "Requerimento\\s+N[Oº]\\s*([0-9]+\\.?[0-9]*)/(\\d{4})\\s*[–-]\\s*Destinat[aá]rio:\\s*([^.\\n]+)\\.?([^\\n]*)",
    texto_completo, perl = TRUE, ignore.case = TRUE
  )
  req_textos <- regmatches(texto_completo, req_matches)[[1]]

  reqs <- purrr::map_dfr(req_textos, function(txt) {
    numero <- regmatches(txt, regexpr("[0-9]+\\.?[0-9]*/", txt, perl = TRUE))
    numero <- gsub("/", "", numero)
    ano    <- as.integer(regmatches(txt, regexpr("/(\\d{4})", txt, perl = TRUE)) |> gsub("/", "", x = _))
    dest   <- regmatches(txt, regexpr("(?i)Destinat[aá]rio:\\s*([^.\\n]+)", txt, perl = TRUE))
    dest   <- gsub("(?i)Destinat[aá]rio:\\s*", "", dest, perl = TRUE)
    dest   <- trimws(dest)

    # Ementa: texto após o destinatário
    ementa <- sub(".*Destinat[aá]rio:[^.]+\\.?\\s*", "", txt, perl = TRUE)
    ementa <- trimws(ementa)
    if (nchar(ementa) < 5) ementa <- NA_character_

    data.frame(
      numero      = numero,
      ano         = ano,
      tipo_codigo = "REQ",
      tipo_nome   = "Requerimento",
      autor_raw   = NA_character_,  # preenchido em 02_consolidar pelo slug
      ementa      = ementa,
      destinatario = dest,
      pdf_url     = NA_character_,
      stringsAsFactors = FALSE
    )
  })

  # ── Moções ──────────────────────────────────────────────────────────────────
  # Formato: "MOÇÃO DE LOUVOR\nDESTINATÁRIO: Nome"
  moc_matches <- gregexpr(
    "MOÇ[AÃ]O\\s+DE\\s+(LOUVOR|PESAR\\s+COLETIVA|PESAR|PARABENIZA[ÇC][AÃ]O)[\\s\\S]{0,200}?DESTINAT[AÁ]RIO:\\s*([^\\n]+)",
    texto_completo, perl = TRUE, ignore.case = TRUE
  )
  moc_textos <- regmatches(texto_completo, moc_matches)[[1]]

  mocs <- purrr::map_dfr(moc_textos, function(txt) {
    subtipo <- regmatches(txt, regexpr("(?i)(LOUVOR|PESAR COLETIVA|PESAR|PARABENIZA[ÇC][AÃ]O)", txt, perl = TRUE))
    dest    <- regmatches(txt, regexpr("(?i)DESTINAT[AÁ]RIO:\\s*([^\\n]+)", txt, perl = TRUE))
    dest    <- gsub("(?i)DESTINAT[AÁ]RIO:\\s*", "", dest, perl = TRUE)
    dest    <- trimws(dest)

    data.frame(
      numero       = NA_character_,
      ano          = NA_integer_,
      tipo_codigo  = "MOC",
      tipo_nome    = paste0("Moção de ", tools::toTitleCase(tolower(subtipo))),
      autor_raw    = NA_character_,
      ementa       = NA_character_,
      destinatario = dest,
      pdf_url      = NA_character_,
      stringsAsFactors = FALSE
    )
  })

  resultado <- dplyr::bind_rows(reqs, mocs)
  resultado$fonte <- slug
  resultado
}

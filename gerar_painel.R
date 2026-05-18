library(DBI); library(RSQLite); library(DT); library(htmlwidgets); library(dplyr)

con <- dbConnect(SQLite(), "data/tdo_sd.sqlite")

props <- dbGetQuery(con, "
  SELECT
    p.tipo_codigo   AS Tipo,
    p.numero        AS Numero,
    p.ano           AS Ano,
    p.autor_raw     AS Autor,
    p.ementa        AS Ementa,
    p.destinatario  AS Destinatario,
    p.pdf_url       AS PDF
  FROM proposicoes p
  ORDER BY ano DESC, tipo_codigo, CAST(numero AS INTEGER) DESC
")

dbDisconnect(con)

# Adicionar coluna de link clicável para o PDF
props <- props |>
  mutate(
    PDF = ifelse(
      !is.na(PDF) & PDF != "",
      paste0('<a href="', PDF, '" target="_blank">📄 Ver</a>'),
      ""
    )
  )

tabela <- datatable(
  props,
  escape    = FALSE,       # permite HTML na coluna PDF
  rownames  = FALSE,
  filter    = "top",       # filtros por coluna no topo
  extensions = "Buttons",
  options   = list(
    pageLength = 25,
    dom        = "Bfrtip",
    buttons    = list("csv", "excel"),
    language   = list(
      url = "//cdn.datatables.net/plug-ins/1.13.6/i18n/pt-BR.json"
    ),
    columnDefs = list(
      list(width = "40%", targets = 4),  # Ementa mais larga
      list(width = "25%", targets = 5)   # Destinatário
    )
  ),
  caption = htmltools::tags$caption(
    style = "caption-side: top; text-align: left; font-size: 1.2em; font-weight: bold; padding: 8px 0;",
    "Tô de Olho — Câmara Municipal de Santos Dumont (MG) | Legislatura 2025-2028"
  )
)

saveWidget(tabela, "painel.html", selfcontained = FALSE,
           title = "Tô de Olho Santos Dumont")

cat("Painel gerado: painel.html\n")
cat(sprintf("Total de registros: %d\n", nrow(props)))

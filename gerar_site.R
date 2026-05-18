library(DBI); library(RSQLite); library(dplyr); library(jsonlite)
library(DT);  library(htmlwidgets)

con <- dbConnect(SQLite(), "data/tdo_sd.sqlite")

# ── Dados ─────────────────────────────────────────────────────────────────────
total  <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM proposicoes")$n
n_pl   <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM proposicoes WHERE tipo_codigo IN ('PL','PLC','PR','PDL')")$n
n_req  <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM proposicoes WHERE tipo_codigo='REQ'")$n
n_ver  <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM vereadores")$n

ranking <- dbGetQuery(con, "
  SELECT v.nome, v.partido_atual AS partido,
         COUNT(p.prop_id) AS total,
         SUM(CASE WHEN p.tipo_codigo IN ('PL','PLC','PR','PDL') THEN 1 ELSE 0 END) AS pls,
         SUM(CASE WHEN p.tipo_codigo = 'REQ' THEN 1 ELSE 0 END) AS reqs
  FROM vereadores v
  LEFT JOIN proposicoes p ON p.autor_normalizado = v.nome_normalizado
  GROUP BY v.nome ORDER BY total DESC")

temas_pl <- dbGetQuery(con, "
  SELECT tema_principal AS tema, COUNT(*) AS n FROM proposicoes
  WHERE tipo_codigo IN ('PL','PLC','PR','PDL') AND tema_principal IS NOT NULL
  GROUP BY tema ORDER BY n DESC")

req_urb <- dbGetQuery(con, "
  SELECT tema_principal AS tema, COUNT(*) AS n FROM proposicoes
  WHERE tipo_codigo='REQ' AND tema_principal NOT LIKE 'moc_%'
  AND tema_principal != 'audiencia_publica' AND tema_principal IS NOT NULL
  GROUP BY tema ORDER BY n DESC")

req_moc <- dbGetQuery(con, "
  SELECT tema_principal AS tema, COUNT(*) AS n FROM proposicoes
  WHERE tipo_codigo='REQ'
  AND (tema_principal LIKE 'moc_%' OR tema_principal = 'audiencia_publica')
  AND tema_principal IS NOT NULL
  GROUP BY tema ORDER BY n DESC")

tabela <- dbGetQuery(con, "
  SELECT tipo_codigo AS Tipo, numero AS [Nº], ano AS Ano,
         autor_raw AS Autor, ementa AS Ementa,
         destinatario AS [Destinatário], tema_principal AS Tema, pdf_url AS PDF
  FROM proposicoes ORDER BY ano DESC, tipo_codigo, CAST(numero AS INTEGER) DESC")
dbDisconnect(con)

tabela <- tabela |> mutate(
  PDF = ifelse(!is.na(PDF) & PDF != "",
    paste0('<a href="', PDF, '" target="_blank">&#128196;</a>'), ""))

# ── Labels ────────────────────────────────────────────────────────────────────
lbl <- c(
  saude="Saúde", educacao="Educação", meio_ambiente="Meio Ambiente",
  mobilidade="Mobilidade", seguranca="Segurança", animais="Animais",
  assistencia_social="Assist. Social", mulher_genero="Mulher/Gênero",
  pcd_acessibilidade="PCD/Acessib.", terceira_idade="Terceira Idade",
  cultura_lazer="Cultura/Lazer", homenagem_denominacao="Homenagem",
  desenvolvimento_economico="Desenv. Econômico", gestao_publica="Gestão Pública",
  quilombola_racial="Quilombola/Racial",
  capina_limpeza="Capina/Limpeza", pavimentacao="Pavimentação",
  iluminacao="Iluminação", drenagem_bueiros="Drenagem/Bueiros",
  calcada_acesso="Calçada/Acesso", mobilidade_transito="Mobilidade/Trânsito",
  infraestrutura_obras="Infraestrutura", areas_verdes_pracas="Áreas Verdes",
  moc_pesar="Moção de Pesar", moc_louvor="Moção de Louvor",
  moc_repudio="Moção de Repúdio", moc_parabenizacao="Parabenização",
  audiencia_publica="Audiência Pública")

temas_pl$label  <- coalesce(lbl[temas_pl$tema],  temas_pl$tema)
req_urb$label   <- coalesce(lbl[req_urb$tema],   req_urb$tema)
req_moc$label   <- coalesce(lbl[req_moc$tema],   req_moc$tema)

# ── Tabela DT separada ────────────────────────────────────────────────────────
dir.create("site", showWarnings=FALSE)
dt <- datatable(tabela, escape=FALSE, rownames=FALSE, filter="top",
  extensions="Buttons",
  options=list(pageLength=20, dom="Bfrtip",
    buttons=list("csv","excel"),
    language=list(url="//cdn.datatables.net/plug-ins/1.13.6/i18n/pt-BR.json"),
    columnDefs=list(list(width="35%", targets=4))))
saveWidget(dt, "site/tabela.html", selfcontained=FALSE,
           title="Tô de Olho SD — Tabela")

# ── Linhas do ranking ─────────────────────────────────────────────────────────
mx <- max(ranking$total)
rank_rows <- paste(sapply(seq_len(nrow(ranking)), function(i) {
  r   <- ranking[i,]
  pct <- round(100 * r$total / mx)
  ptd <- if (is.na(r$partido)) "—" else r$partido
  paste0(
    '<tr><td style="color:#888;font-size:.8rem">', i, '</td>',
    '<td><strong>', r$nome, '</strong></td>',
    '<td><span class="badge">', ptd, '</span></td>',
    '<td class="n">', r$pls, '</td>',
    '<td>', r$reqs, '</td>',
    '<td class="n">', r$total, '</td>',
    '<td><div class="bar-bg"><div class="bar-fill" style="width:', pct, '%"></div></div></td></tr>'
  )
}), collapse="\n")

# ── JSON ──────────────────────────────────────────────────────────────────────
jRankNomes <- toJSON(ranking$nome,        auto_unbox=FALSE)
jRankPLs   <- toJSON(ranking$pls,         auto_unbox=FALSE)
jRankReqs  <- toJSON(ranking$reqs,        auto_unbox=FALSE)
jPlLbl     <- toJSON(temas_pl$label,      auto_unbox=FALSE)
jPlVal     <- toJSON(temas_pl$n,          auto_unbox=FALSE)
jUrbLbl    <- toJSON(req_urb$label,       auto_unbox=FALSE)
jUrbVal    <- toJSON(req_urb$n,           auto_unbox=FALSE)
jMocLbl    <- toJSON(req_moc$label,       auto_unbox=FALSE)
jMocVal    <- toJSON(req_moc$n,           auto_unbox=FALSE)

# ── HTML (sem sprintf — usa paste0 com substituição) ─────────────────────────
html <- readLines(here::here("inst", "site_template.html"), encoding="UTF-8")
html <- paste(html, collapse="\n")

html <- gsub("{{TOTAL}}",      total,      html, fixed=TRUE)
html <- gsub("{{N_PL}}",       n_pl,       html, fixed=TRUE)
html <- gsub("{{N_REQ}}",      n_req,      html, fixed=TRUE)
html <- gsub("{{N_VER}}",      n_ver,      html, fixed=TRUE)
html <- gsub("{{RANK_ROWS}}",  rank_rows,  html, fixed=TRUE)
html <- gsub("{{J_RANK_NOMES}}",jRankNomes,html, fixed=TRUE)
html <- gsub("{{J_RANK_PLS}}",  jRankPLs,  html, fixed=TRUE)
html <- gsub("{{J_RANK_REQS}}", jRankReqs, html, fixed=TRUE)
html <- gsub("{{J_PL_LBL}}",    jPlLbl,    html, fixed=TRUE)
html <- gsub("{{J_PL_VAL}}",    jPlVal,    html, fixed=TRUE)
html <- gsub("{{J_URB_LBL}}",   jUrbLbl,   html, fixed=TRUE)
html <- gsub("{{J_URB_VAL}}",   jUrbVal,   html, fixed=TRUE)
html <- gsub("{{J_MOC_LBL}}",   jMocLbl,   html, fixed=TRUE)
html <- gsub("{{J_MOC_VAL}}",   jMocVal,   html, fixed=TRUE)

writeLines(html, "site/index.html", useBytes=FALSE)
cat(sprintf("Site gerado: site/index.html (%d proposicoes)\n", total))

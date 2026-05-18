library(DBI); library(RSQLite); library(dplyr)
con <- dbConnect(SQLite(), "data/tdo_sd.sqlite")

cat("=== AMOSTRA PLs — ementas ===\n")
dbGetQuery(con, "SELECT autor_raw, ementa FROM proposicoes
  WHERE tipo_codigo IN ('PL','PLC') AND ementa IS NOT NULL
  ORDER BY RANDOM() LIMIT 20") |> print()

cat("\n=== REQs direcionados ao PLENARIO (possiveis mocoes) ===\n")
dbGetQuery(con, "SELECT autor_raw, destinatario, substr(ementa,1,120) AS ementa
  FROM proposicoes WHERE tipo_codigo='REQ'
  AND (destinatario LIKE '%Plen%' OR ementa LIKE '%Mo%o%')
  LIMIT 20") |> print()

cat("\n=== REQs — amostra de ementas URBANAS ===\n")
dbGetQuery(con, "SELECT autor_raw, substr(ementa,1,100) AS ementa
  FROM proposicoes WHERE tipo_codigo='REQ'
  AND (ementa LIKE '%asfalto%' OR ementa LIKE '%capina%'
    OR ementa LIKE '%poda%' OR ementa LIKE '%ilumina%'
    OR ementa LIKE '%bueiro%' OR ementa LIKE '%calcada%'
    OR ementa LIKE '%calçada%' OR ementa LIKE '%paviment%')
  LIMIT 20") |> print()

cat("\n=== TODOS DESTINOS DISTINTOS dos REQs (top 30) ===\n")
dbGetQuery(con, "SELECT destinatario, COUNT(*) AS n FROM proposicoes
  WHERE tipo_codigo='REQ' GROUP BY destinatario ORDER BY n DESC LIMIT 30") |> print()

dbDisconnect(con)

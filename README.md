# Tô de Olho — Câmara Municipal de Santos Dumont

**JF em Dados** | Observatório cívico voluntário · [github.com/jfemdados](https://github.com/jfemdados)

> Acompanhe o que o vereador que você elegeu anda fazendo.

## O que é

O **Tô de Olho Santos Dumont** é um painel de transparência legislativa da Câmara Municipal de Santos Dumont (MG), cidade natal do fundador do projeto. Coleta e organiza automaticamente os dados do [site oficial da Câmara](https://www.camarasd.mg.gov.br) e os apresenta de forma simples, por vereador.

Cobertura: **legislatura 2025–2028** (vereadores eleitos em outubro de 2024).

## O que você encontra

- Projetos de Lei de cada vereador
- Requerimentos encaminhados ao Executivo
- Moções de Louvor e Pesar
- Classificação temática descritiva (sem julgamento de valor)
- Link direto para o PDF oficial na Câmara

## Princípios

- **Descritivo, não avaliativo.** A ferramenta organiza; o cidadão julga.
- **Transparência radical.** Todo dado tem link para a fonte oficial.
- **Reprodutível.** Qualquer pessoa pode rodar o pipeline e chegar ao mesmo resultado.

## Fonte dos dados

Os dados vêm exclusivamente do site oficial da Câmara Municipal de Santos Dumont.

- URL base: `https://www.camarasd.mg.gov.br`
- PLs: página única `/projetos-de-lei/`
- Requerimentos/Moções: perfis individuais de cada vereador
- Atualização: toda segunda-feira às 06h (BRT), via GitHub Actions
- Formato bruto: HTML WordPress

## Diferenças em relação ao projeto de JF

| Aspecto | JF (SAL) | Santos Dumont |
|---|---|---|
| Fonte dos dados | API SAL (tabela estruturada) | WordPress (HTML não-estruturado) |
| Situação/status | Sim (em tramitação, aprovado...) | Não disponível no site |
| ID interno | `sal_id` (numérico) | `prop_id` (composto: tipo-numero-ano) |
| Requerimentos | Página centralizada | Perfil individual de cada vereador |
| Vereadores | 23 | 13 |

## Como rodar localmente

```r
# 1. Clonar o repositório
# git clone https://github.com/jfemdados/to-de-olho-sd

# 2. Restaurar dependências (requer renv instalado)
renv::restore()

# 3. Executar o pipeline completo
source("R/01_baixar.R")
source("R/02_consolidar.R")
source("R/03_vereadores.R")
```

## Estrutura

```
to-de-olho-sd/
├── .github/workflows/coleta.yml   # automação semanal
├── R/
│   ├── 01_baixar.R                # download do site
│   ├── 02_consolidar.R            # parse HTML → SQLite
│   ├── 03_vereadores.R            # popula tabela de vereadores
│   ├── 04_classificar_tema.R      # classificação temática (Sprint 2)
│   ├── 05_exportar.R              # CSVs para Flourish (Sprint 2/3)
│   └── utils/
│       ├── db.R                   # SQLite helpers
│       ├── http.R                 # download helpers
│       └── parse.R                # parse HTML WordPress
├── data/
│   ├── raw/                       # HTMLs brutos (.gitignore)
│   ├── tdo_sd.sqlite              # banco principal
│   └── snapshots/                 # parquets versionados
└── inst/dicionarios/
    ├── temas.yaml                 # regex por tema
    ├── urls_vereadores.yaml       # slug → URL dos perfis
    └── vereadores_2025.csv        # 13 vereadores (manual)
```

## Status

🟡 Em desenvolvimento — Sprint 1 (coleta e banco de dados)

## Vereadores (legislatura 2025-2028)

| Nome | Partido |
|---|---|
| Alyne do Nascimento | DC |
| Altamir Moisés de Carvalho | Podemos |
| Dorival Marcos de Oliveira | PT |
| Everaldo Barbosa | MDB |
| Flávio Faria | PRD |
| Flávia Letícia | PT |
| Luciano Gomes | PSB |
| Maria da Enfermagem | PSB |
| Sandra Cabral | PSB |
| José Abud | Republicanos |
| Josiane Lopes | MDB |
| Valmir Teteco | PSD |
| Thailândia Leite | Podemos |

## Nota metodológica

Este projeto não avalia o mérito das proposições legislativas. Categorias como "requerimento de serviço urbano" ou "moção de louvor" são descritivas. A interpretação é do cidadão.

---

*JF em Dados é um projeto voluntário sem fins lucrativos. Santos Dumont é minha cidade natal — fiscalizar é um ato de amor.*

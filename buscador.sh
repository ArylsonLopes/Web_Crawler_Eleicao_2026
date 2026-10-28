#!/usr/bin/env bash
set -Eeuo pipefail

readonly DEFAULT_BASE_URL="https://resultados.tse.jus.br/oficial"
readonly -a CARGOS=(6 7 5 3 1)

BASE_URL="${TSE_RESULTS_BASE_URL:-$DEFAULT_BASE_URL}"
YEAR="${TSE_RESULTS_YEAR:-2026}"
UF="${TSE_RESULTS_UF:-ma}"
MUNICIPIO="${TSE_RESULTS_MUNICIPALITY:-todos}"   # "todos" ou códigos TSE de 5 dígitos separados por vírgula
LIMIT="${TSE_RESULTS_LIMIT:-20}"
FEDERAL_ELECTION="${TSE_RESULTS_FEDERAL_ELECTION:-6257}"
STATE_ELECTION="${TSE_RESULTS_STATE_ELECTION:-6259}"
COLOR_MODE="${TSE_RESULTS_COLOR:-auto}"

die() { printf 'Erro: %s\n' "$*" >&2; exit 1; }
warn() { printf 'Aviso: %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Uso: buscador.sh [opções]

Opções:
  -m, --municipio CODIGOS "todos" (padrão) ou códigos TSE de 5 dígitos separados por vírgula
  -u, --uf UF             Sigla da UF (padrão: ma)
  -l, --limite N          Candidatos por cargo (padrão: 20)
  -h, --help              Mostra esta ajuda

Variáveis de ambiente (opcionais): TSE_RESULTS_BASE_URL, TSE_RESULTS_YEAR,
TSE_RESULTS_UF, TSE_RESULTS_MUNICIPALITY, TSE_RESULTS_LIMIT, TSE_RESULTS_COLOR,
TSE_RESULTS_FEDERAL_ELECTION, TSE_RESULTS_STATE_ELECTION
EOF
}

while (( $# )); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -m|--municipio) [[ $# -ge 2 ]] || die "$1 exige um valor"; MUNICIPIO="$2"; shift 2 ;;
    -u|--uf)        [[ $# -ge 2 ]] || die "$1 exige um valor"; UF="$2"; shift 2 ;;
    -l|--limite)    [[ $# -ge 2 ]] || die "$1 exige um valor"; LIMIT="$2"; shift 2 ;;
    *) die "opção desconhecida: $1 (use --help)" ;;
  esac
done

command -v curl >/dev/null || die "curl não encontrado (instale com: sudo apt install curl)"
command -v jq >/dev/null || die "jq não encontrado (instale com: sudo apt install jq)"
[[ "$UF" =~ ^[[:alpha:]]{2}$ ]] || die "TSE_RESULTS_UF deve conter duas letras"
[[ "$MUNICIPIO" == todos || "$MUNICIPIO" =~ ^[0-9]{5}(,[0-9]{5})*$ ]] \
  || die "município deve ser 'todos' ou códigos de 5 dígitos separados por vírgula"
[[ "$YEAR" =~ ^[0-9]{4}$ ]] || die "TSE_RESULTS_YEAR deve conter quatro dígitos"
[[ "$LIMIT" =~ ^[1-9][0-9]*$ ]] || die "TSE_RESULTS_LIMIT deve ser um inteiro positivo"
[[ "$FEDERAL_ELECTION" =~ ^[0-9]+$ && "$STATE_ELECTION" =~ ^[0-9]+$ ]] || die "códigos de eleição devem ser numéricos"
[[ "$COLOR_MODE" =~ ^(auto|always|never)$ ]] || die "TSE_RESULTS_COLOR deve ser auto, always ou never"

UF="${UF,,}"
BASE_URL="${BASE_URL%/}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

use_color=false
if [[ "$COLOR_MODE" == always ]] || { [[ "$COLOR_MODE" == auto && -t 1 && "${TERM:-dumb}" != dumb ]] && [[ ! -v NO_COLOR ]]; }; then
  use_color=true
fi

print_rule() {
  local name_width="$1" number_width="$2" votes_width="$3"
  printf '+-%*s-+-%*s-+-%*s-+\n' "$name_width" '' "$number_width" '' "$votes_width" '' | tr ' ' '-'
}

print_table() {
  local -n table_rows="$1"
  local name_width=${#name_header} number_width=${#number_header} votes_width=${#votes_header}
  local row name number votes

  for row in "${table_rows[@]}"; do
    IFS=$'\t' read -r name number votes <<<"$row"
    (( ${#name} > name_width )) && name_width=${#name}
    (( ${#number} > number_width )) && number_width=${#number}
    (( ${#votes} > votes_width )) && votes_width=${#votes}
  done

  print_rule "$name_width" "$number_width" "$votes_width"
  printf '| %-*s | %*s | %*s |\n' "$name_width" "$name_header" "$number_width" "$number_header" "$votes_width" "$votes_header"
  print_rule "$name_width" "$number_width" "$votes_width"
  for row in "${table_rows[@]}"; do
    IFS=$'\t' read -r name number votes <<<"$row"
    if $use_color; then
      printf '| \033[36m%-*s\033[0m | %*s | \033[32m%*s\033[0m |\n' "$name_width" "$name" "$number_width" "$number" "$votes_width" "$votes"
    else
      printf '| %-*s | %*s | %*s |\n' "$name_width" "$name" "$number_width" "$number" "$votes_width" "$votes"
    fi
  done
  print_rule "$name_width" "$number_width" "$votes_width"
}

readonly name_header="NOME" number_header="NÚMERO" votes_header="VOTOS"

election_for_cargo() {
  case "$1" in
    1) printf '%s' "$FEDERAL_ELECTION" ;;
    3|5|6|7) printf '%s' "$STATE_ELECTION" ;;
    *) die "cargo não suportado: $1" ;;
  esac
}

fetch() {
  local url="$1" dest="$2"
  curl --fail --silent --show-error --location \
    --retry 3 --retry-all-errors --connect-timeout 10 --max-time 30 \
    --output "$dest" "$url"
}

# Imprime "codigo<TAB>nome" para cada município a consultar.
list_municipios() {
  if [[ "$MUNICIPIO" != todos ]]; then
    tr ',' '\n' <<<"$MUNICIPIO" | awk '{ print $1 "\tmunicípio " $1 }'
    return 0
  fi

  local election_padded url file="$tmp_dir/municipios.json"
  printf -v election_padded '%06d' "$((10#$STATE_ELECTION))"
  url="$BASE_URL/ele$YEAR/$STATE_ELECTION/config/mun-e${election_padded}-cm.json"
  fetch "$url" "$file" \
    || die "não foi possível obter a lista de municípios ($url). Use --municipio com códigos específicos."

  jq -r --arg uf "$UF" '
    .abr[]
    | select(((.cd // .cdabr // "") | ascii_downcase) == $uf)
    | .mu[]
    | [(.cd | tostring), .nm] | @tsv
  ' "$file" | sort -t$'\t' -k2,2 \
    || die "resposta inválida na lista de municípios"
}

# Exibe a tabela de um cargo em um município.
show_cargo() {
  local mun="$1" cargo="$2" election
  local file cargo_padded election_padded url cargo_name rows_file
  local -a rows

  election="$(election_for_cargo "$cargo")"
  file="$tmp_dir/cargo-$mun-$cargo.json"
  printf -v cargo_padded '%04d' "$cargo"
  printf -v election_padded '%06d' "$election"
  url="$BASE_URL/ele$YEAR/$election/dados/$UF/${UF}${mun}-c${cargo_padded}-e${election_padded}-u.json"

  fetch "$url" "$file" || die "falha ao consultar o cargo $cargo em $mun"
  jq -e '.carg | type == "array"' "$file" >/dev/null || die "resposta inválida para o cargo $cargo em $mun"

  cargo_name="$(jq -r --arg cargo "$cargo" '.carg[] | select(.cd == $cargo) | .nmn' "$file" | head -n 1)"
  [[ -n "$cargo_name" ]] || die "cargo $cargo ausente na resposta de $mun"
  printf '\n  %s (cargo %s)\n' "$cargo_name" "$cargo"
  rows_file="$tmp_dir/cargo-$mun-$cargo.tsv"
  jq -r --arg cargo "$cargo" --argjson limit "$LIMIT" '
    [
      .carg[] | select(.cd == $cargo)
      | .. | objects | .cand? // empty | .[]
      | select((.nmu // "") != "" and (.n // "") != "")
      | { nome: (.nmu | gsub("[[:cntrl:]]"; " ")), numero: .n, votos: ((.vap // "0") | tonumber) }
    ]
    | unique_by(.numero)
    | sort_by([-.votos, (.nome | ascii_downcase), .numero])
    | .[:$limit][]
    | [.nome, .numero, (.votos | tostring)] | @tsv
  ' "$file" >"$rows_file"
  mapfile -t rows <"$rows_file"
  print_table rows
}

mapfile -t municipios < <(list_municipios)
(( ${#municipios[@]} > 0 )) || die "nenhum município encontrado para a UF '$UF'"

for linha in "${municipios[@]}"; do
  IFS=$'\t' read -r mun_cod mun_nome <<<"$linha"
  printf '\n### %s (%s)\n' "$mun_nome" "$mun_cod"
  for cargo in "${CARGOS[@]}"; do
    show_cargo "$mun_cod" "$cargo"
  done
done

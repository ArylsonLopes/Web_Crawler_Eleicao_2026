#!/usr/bin/env bash
set -Eeuo pipefail

readonly DEFAULT_BASE_URL="https://resultados.tse.jus.br/oficial"
readonly -a CARGOS=(6 7 5 3 1)

BASE_URL="${TSE_RESULTS_BASE_URL:-$DEFAULT_BASE_URL}"
YEAR="${TSE_RESULTS_YEAR:-2026}"
UF="${TSE_RESULTS_UF:-ma}"
MUNICIPIO="${TSE_RESULTS_MUNICIPALITY:-todos}"   # "todos" ou códigos TSE de 5 dígitos separados por vírgula
LIMIT="${TSE_RESULTS_LIMIT:-20}"
TURNO="${TSE_RESULTS_TURN:-1}"                   # 1, 2 ou ambos
ONLY_ELECTED=false

# Códigos de eleição do TSE (diferentes para cada turno).
FEDERAL_ELECTION_1T="${TSE_RESULTS_FEDERAL_ELECTION:-6257}"
STATE_ELECTION_1T="${TSE_RESULTS_STATE_ELECTION:-6259}"
FEDERAL_ELECTION_2T="${TSE_RESULTS_FEDERAL_ELECTION_2T:-}"
STATE_ELECTION_2T="${TSE_RESULTS_STATE_ELECTION_2T:-}"
COLOR_MODE="${TSE_RESULTS_COLOR:-auto}"

die() { printf 'Erro: %s\n' "$*" >&2; exit 1; }
warn() { printf 'Aviso: %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Uso: buscador.sh [opções]

Opções:
  -m, --municipio CODIGOS "todos" (padrão) ou códigos TSE de 5 dígitos separados por vírgula
  -u, --uf UF             Sigla da UF (padrão: ma)
  -t, --turno 1|2|ambos   Turno a exibir (padrão: 1)
  -l, --limite N          Candidatos por cargo (padrão: 20; eleitos sempre aparecem)
  -e, --so-eleitos        Mostra somente candidatos eleitos
  -h, --help              Mostra esta ajuda

Variáveis de ambiente (opcionais): TSE_RESULTS_BASE_URL, TSE_RESULTS_YEAR,
TSE_RESULTS_UF, TSE_RESULTS_MUNICIPALITY, TSE_RESULTS_LIMIT, TSE_RESULTS_COLOR,
TSE_RESULTS_TURN, TSE_RESULTS_FEDERAL_ELECTION, TSE_RESULTS_STATE_ELECTION,
TSE_RESULTS_FEDERAL_ELECTION_2T, TSE_RESULTS_STATE_ELECTION_2T

O 2º turno só existe para presidente e governador, e exige os códigos de
eleição do 2º turno (variáveis *_2T) divulgados pelo TSE.
EOF
}

while (( $# )); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -m|--municipio) [[ $# -ge 2 ]] || die "$1 exige um valor"; MUNICIPIO="$2"; shift 2 ;;
    -u|--uf)        [[ $# -ge 2 ]] || die "$1 exige um valor"; UF="$2"; shift 2 ;;
    -t|--turno)     [[ $# -ge 2 ]] || die "$1 exige um valor"; TURNO="$2"; shift 2 ;;
    -e|--so-eleitos) ONLY_ELECTED=true; shift ;;
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
[[ "$TURNO" =~ ^(1|2|ambos)$ ]] || die "turno deve ser 1, 2 ou ambos"
for code in "$FEDERAL_ELECTION_1T" "$STATE_ELECTION_1T" "$FEDERAL_ELECTION_2T" "$STATE_ELECTION_2T"; do
  [[ -z "$code" || "$code" =~ ^[0-9]+$ ]] || die "códigos de eleição devem ser numéricos (recebido: '$code')"
done
[[ "$COLOR_MODE" =~ ^(auto|always|never)$ ]] || die "TSE_RESULTS_COLOR deve ser auto, always ou never"

UF="${UF,,}"
BASE_URL="${BASE_URL%/}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

ok_count=0
fail_count=0

use_color=false
if [[ "$COLOR_MODE" == always ]] || { [[ "$COLOR_MODE" == auto && -t 1 && "${TERM:-dumb}" != dumb ]] && [[ ! -v NO_COLOR ]]; }; then
  use_color=true
fi

print_rule() {
  local w1="$1" w2="$2" w3="$3" w4="$4"
  printf '+-%*s-+-%*s-+-%*s-+-%*s-+\n' "$w1" '' "$w2" '' "$w3" '' "$w4" '' | tr ' ' '-'
}

# Recebe o nome de um array com linhas TSV (nome, número, votos, situação).
print_table() {
  local -n table_rows="$1"
  local w1=${#name_header} w2=${#number_header} w3=${#votes_header} w4=${#status_header}
  local row name number votes status

  for row in "${table_rows[@]}"; do
    IFS=$'\t' read -r name number votes status <<<"$row"
    if (( ${#name} > w1 )); then w1=${#name}; fi
    if (( ${#number} > w2 )); then w2=${#number}; fi
    if (( ${#votes} > w3 )); then w3=${#votes}; fi
    if (( ${#status} > w4 )); then w4=${#status}; fi
  done

  print_rule "$w1" "$w2" "$w3" "$w4"
  printf '| %-*s | %*s | %*s | %-*s |\n' "$w1" "$name_header" "$w2" "$number_header" "$w3" "$votes_header" "$w4" "$status_header"
  print_rule "$w1" "$w2" "$w3" "$w4"
  for row in "${table_rows[@]}"; do
    IFS=$'\t' read -r name number votes status <<<"$row"
    if $use_color && [[ "$status" == ELEITO* ]]; then
      printf '\033[1;32m| %-*s | %*s | %*s | %-*s |\033[0m\n' "$w1" "$name" "$w2" "$number" "$w3" "$votes" "$w4" "$status"
    else
      printf '| %-*s | %*s | %*s | %-*s |\n' "$w1" "$name" "$w2" "$number" "$w3" "$votes" "$w4" "$status"
    fi
  done
  print_rule "$w1" "$w2" "$w3" "$w4"
}

readonly name_header="NOME" number_header="NÚMERO" votes_header="VOTOS" status_header="SITUAÇÃO"

# Código da eleição para (turno, cargo). Retorna 1 se o cargo não tem esse turno.
election_for() {
  case "$1:$2" in
    1:1)             printf '%s' "$FEDERAL_ELECTION_1T" ;;
    1:3|1:5|1:6|1:7) printf '%s' "$STATE_ELECTION_1T" ;;
    2:1)             printf '%s' "$FEDERAL_ELECTION_2T" ;;
    2:3)             printf '%s' "$STATE_ELECTION_2T" ;;
    *) return 1 ;;
  esac
}

fetch() {
  local url="$1" dest="$2"
  curl --fail --silent --show-error --location \
    --retry 3 --retry-all-errors --connect-timeout 10 --max-time 30 \
    --output "$dest" "$url" 2>"$tmp_dir/curl.err"
}

# Imprime "codigo<TAB>nome" para cada município a consultar.
list_municipios() {
  if [[ "$MUNICIPIO" != todos ]]; then
    tr ',' '\n' <<<"$MUNICIPIO" | awk '{ print $1 "\tmunicípio " $1 }'
    return 0
  fi

  local election_padded url file="$tmp_dir/municipios.json"
  printf -v election_padded '%06d' "$((10#$STATE_ELECTION_1T))"
  url="$BASE_URL/ele$YEAR/$STATE_ELECTION_1T/config/mun-e${election_padded}-cm.json"
  fetch "$url" "$file" \
    || die "não foi possível obter a lista de municípios ($url): $(tail -n 1 "$tmp_dir/curl.err"). Use --municipio com códigos específicos."

  jq -r --arg uf "$UF" '
    .abr[]
    | select(((.cd // .cdabr // "") | ascii_downcase) == $uf)
    | .mu[]
    | [(.cd | tostring), .nm] | @tsv
  ' "$file" | sort -t$'\t' -k2,2 \
    || die "resposta inválida na lista de municípios"
}

# Exibe a tabela de um cargo em um município/turno.
show_cargo() {
  local turno="$1" mun="$2" cargo="$3" election
  local file cargo_padded election_padded url cargo_name rows_file
  local -a rows

  election="$(election_for "$turno" "$cargo")"
  file="$tmp_dir/cargo-$turno-$mun-$cargo.json"
  printf -v cargo_padded '%04d' "$cargo"
  printf -v election_padded '%06d' "$election"
  url="$BASE_URL/ele$YEAR/$election/dados/$UF/${UF}${mun}-c${cargo_padded}-e${election_padded}-u.json"

  if ! fetch "$url" "$file"; then
    warn "sem dados para cargo $cargo em $mun (${turno}º turno): $(tail -n 1 "$tmp_dir/curl.err")"
    fail_count=$((fail_count + 1))
    return 0
  fi
  if ! jq -e '.carg | type == "array"' "$file" >/dev/null 2>&1; then
    warn "resposta inválida para cargo $cargo em $mun (${turno}º turno)"
    fail_count=$((fail_count + 1))
    return 0
  fi

  cargo_name="$(jq -r --arg cargo "$cargo" '.carg[] | select(.cd == $cargo) | .nmn' "$file" | head -n 1)"
  if [[ -z "$cargo_name" ]]; then
    warn "cargo $cargo ausente na resposta de $mun (${turno}º turno)"
    fail_count=$((fail_count + 1))
    return 0
  fi
  ok_count=$((ok_count + 1))
  printf '\n  %s (cargo %s)\n' "$cargo_name" "$cargo"
  rows_file="$tmp_dir/cargo-$turno-$mun-$cargo.tsv"
  jq -r --arg cargo "$cargo" --argjson limit "$LIMIT" --argjson only "$ONLY_ELECTED" '
    [
      .carg[] | select(.cd == $cargo)
      | .. | objects | .cand? // empty | .[]
      | select((.nmu // "") != "" and (.n // "") != "")
      | {
          nome: (.nmu | gsub("[[:cntrl:]]"; " ")),
          numero: .n,
          votos: ((.vap // "0") | tonumber),
          eleito: (((.e // "") | ascii_downcase) == "s"
                   or ((.st // "") | ascii_downcase | test("^eleito"))),
          segundo: ((.st // "") | ascii_downcase | test("2.{0,2}turno"))
        }
    ]
    | unique_by(.numero)
    | sort_by([-.votos, (.nome | ascii_downcase), .numero])
    | (.[:$limit] + (.[$limit:] | map(select(.eleito)))) as $lista
    | $lista[]
    | select(($only | not) or .eleito)
    | [.nome, .numero, (.votos | tostring),
       (if .eleito then "ELEITO" elif .segundo then "2º TURNO" else "-" end)]
    | @tsv
  ' "$file" >"$rows_file"
  mapfile -t rows <"$rows_file"
  if (( ${#rows[@]} == 0 )); then
    printf '  (nenhum candidato para exibir)\n'
  else
    print_table rows
  fi
}

case "$TURNO" in
  ambos) turnos=(1 2) ;;
  *)     turnos=("$TURNO") ;;
esac

mapfile -t municipios < <(list_municipios)
(( ${#municipios[@]} > 0 )) || die "nenhum município encontrado para a UF '$UF'"

for turno in "${turnos[@]}"; do
  cargos_ativos=()
  for cargo in "${CARGOS[@]}"; do
    if election="$(election_for "$turno" "$cargo")"; then
      if [[ -z "$election" ]]; then
        warn "código de eleição do ${turno}º turno não configurado para o cargo $cargo (veja --help)"
      else
        cargos_ativos+=("$cargo")
      fi
    fi
  done

  if (( ${#cargos_ativos[@]} == 0 )); then
    warn "nenhum cargo disponível para o ${turno}º turno; pulando"
    continue
  fi

  printf '\n==================== %sº TURNO ====================\n' "$turno"
  for linha in "${municipios[@]}"; do
    IFS=$'\t' read -r mun_cod mun_nome <<<"$linha"
    printf '\n### %s (%s) - %sº turno\n' "$mun_nome" "$mun_cod" "$turno"
    for cargo in "${cargos_ativos[@]}"; do
      show_cargo "$turno" "$mun_cod" "$cargo"
    done
  done
done

printf '\nConsultas concluídas: %d com sucesso, %d sem dados.\n' "$ok_count" "$fail_count" >&2
(( ok_count > 0 )) || die "nenhum resultado obtido"

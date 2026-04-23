#!/usr/bin/env bash
set -euo pipefail

echo "  ***   Script de workflow   ***  "

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
	echo "Error: No tienes token definido"
	echo "Haz: export GITHUB_TOKEN='tutoken'"
	exit 1
fi

echo "Token detectado. Cargando..."

if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
	echo "No estás dentro de una carpeta git"
	echo "Entra a la ruta de tu repo ;)"
	exit 1
fi

origin_url="$(git remote get-url origin 2>/dev/null || true)"

if [[ -z "$origin_url" ]]; then
	echo "Error. Este repo  no tiene remote 'origin'"
	exit 1
fi

repo_entero="$(echo "$origin_url" | sed -E 's#.*github\.com[:/]+##; s#\.git$##')"
usuario="${repo_entero%%/*}"
repo="${repo_entero##*/}"

echo "Repositorio: $usuario/$repo"

url_api="https://api.github.com/repos/$usuario/$repo/actions/workflows"

json="$(curl -S \
	-H "Accept: application/vnd.github+json" \
	-H "Authorization: Bearer $GITHUB_TOKEN" "$url_api")"


echo "---- Compobación de funcionamiento ----"
echo "$json" | head -n 20
echo "------------------------------------------"


# Convertimos el JSON en líneas: id<TAB>name


mapfile -t workflows < <(
  python3 -c '
import json,sys
data=json.load(sys.stdin)
for wf in data.get("workflows", []):
    wid=wf.get("id")
    name=wf.get("name")
    path=wf.get("path")
    if wid and name and path:
        print(f"{wid}\t{name}\t{path}")
' <<< "$json"
)


if [[ "${#workflows[@]}" -eq 0 ]]; then
	echo "No se encontraron workflows"
	echo "Posibles causas: repo sin workflows, token sin permisos, o API devolvió error."
	exit 1
fi


echo "Workflows disponibles:"
i=1
for line in "${workflows[@]}"; do
	id="$(echo "$line" | cut -f1)"
	name="$(echo "$line" | cut -f2)"
	echo "  [$i] $name (id=$id)"
	((i++))
done

read -r -p "Elige un número de workflow: " choice

#Validación simple
if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#workflows[@]} )); then
	echo "Opción inválida."
	exit 1
fi

elegido="${workflows[$((choice-1))]}"
workflow_id="$(echo "$elegido" | cut -f1)"
workflow_name="$(echo "$elegido" | cut -f2)"

echo "Elegido: $workflow_name (id=$workflow_id)"


#lanzar el workflow

read -r -p "Rama donde lanzar el workflow [main]: " ref
ref="${ref:-main}"

dispatch_url="https://api.github.com/repos/$usuario/$repo/actions/workflows/$workflow_id/dispatches"

echo "     ***    "
echo "Lanzando workflow..."
echo "Repo: $usuario/$repo :D"
echo "Workflow: $workflow_name"
echo "Ref: $ref"
echo "     ***    "

curl -sS -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"ref\":\"$ref\"}" \
  "$dispatch_url"

echo ""
echo "Workflow lanzado correctamente :D"

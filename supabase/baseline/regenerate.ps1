param(
  [Parameter(Mandatory = $true)]
  [string]$ProjectRef
)

$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$typesPath = Join-Path $PSScriptRoot 'database.types.ts'
$schemaPath = Join-Path $PSScriptRoot 'schema.sql'
$supabaseCli = 'supabase@2.108.0'

Push-Location $repo
try {
  npx $supabaseCli gen types typescript --project-id $ProjectRef --schema public |
    Set-Content -LiteralPath $typesPath -Encoding utf8

  # Requer `npx supabase link` previamente. O dump padrao e schema-only e
  # exclui schemas gerenciados pelo Supabase, como auth e storage.
  npx $supabaseCli db dump --linked --schema public,private --file $schemaPath
}
finally {
  Pop-Location
}

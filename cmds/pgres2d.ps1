# Auto-generated nuro command (inline original content)

function NuroUsage_Pgres2d {
  'nuro pgres2d <Arg1>'
}

function NuroCmd_Pgres2d {
  [CmdletBinding()]
  param(
      [parameter(mandatory)][String]$Arg1
  )

  $fileName = Split-Path $Arg1 -Leaf
  echo FilePath=$Arg1
  echo FileName=$fileName
  docker run --rm -d -p 5432:5432 -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -e POSTGRES_INITDB_ARGS="--encoding=UTF-8" -v "${Arg1}:/tmp/$fileName" --name tmp_db postgres
  echo ""
  echo しばらく待ってからEnterキーで続行してください。（5秒くらい？）
  echo リストアに失敗したら、以下のコマンドを直接発行してください。
  echo ""
  echo "docker exec tmp_db pg_restore -U postgres -v -c -d postgres /tmp/$fileName"
  echo ""
  Pause
  docker exec tmp_db pg_restore -U postgres -v -c -d postgres /tmp/$fileName
  echo fin.
}


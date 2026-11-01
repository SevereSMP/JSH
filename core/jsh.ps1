# jsh.ps1 - JSON toolkit for Windows cmd. Called by jsh.bat (don't need to run this directly).
# Works on the PowerShell that ships with Windows (5.1) and on PowerShell 7+.

$ErrorActionPreference = 'Stop'
$script:A   = @($args)          # keep the script's arguments (functions get their own $args)
$script:Inv = [Globalization.CultureInfo]::InvariantCulture

function Die([string]$msg, [int]$code = 2) { [Console]::Error.WriteLine("jsh: $msg"); exit $code }
function Out-Line([string]$s) { [Console]::Out.WriteLine($s) }

function Show-Usage {
  [Console]::Error.WriteLine(@'
jsh - JSON toolkit for cmd

usage: jsh <command> [args] [-f FILE | -s "JSON"]        (or pipe JSON in:  type x.json | jsh keys)
       jsh -tst                                          prints true (quick check that jsh runs)

read:
  get PATH [-d DEFAULT] [-c] [-j]   value at PATH (-c compact, -j keep JSON quoting)
  keys [PATH]                       keys of an object / indexes of an array
  values [PATH]                     child values, one per line
  length [PATH]                     child count (or string length)
  type [PATH]                       object|array|string|number|bool|null
  has PATH                          errorlevel 0 if PATH exists, 1 if not (no output)
  paths [PATH]                      every leaf as  path = value
  find KEY                          every place a key named KEY appears
  search TEXT                       every leaf whose value contains TEXT (case-insensitive)
  where ARRAY FIELD VALUE [OUT]     array items where FIELD == VALUE (prints OUT field if given)
  env [PATH] [--prefix P]           NAME=value lines for loading into cmd variables (see below)
  pretty | minify | valid           reformat the document / check that it parses

write (prints the new document; add -i with -f FILE to edit the file in place):
  set PATH VALUE [--str]            replace or add a value (auto-detects number/true/false/null)
  del PATH                          remove a key or array item

paths:  .a.b   a.b   .list[0]   .obj['odd key']   (. = root)
        In cmd, wrap a path in double quotes if it has spaces or special chars.

load everything into cmd variables with one call (fast):
  for /f "delims=" %%L in ('jsh env -f servers.json') do set "%%L"
  -> JSON_servers_0_host=...   JSON_servers__len=2   (values with ! or % are not supported here)
'@)
}

# ---------------------------------------------------------------------------
# argument parsing
# ---------------------------------------------------------------------------
$script:Cmd = ''
$script:Pos = New-Object System.Collections.ArrayList
$script:InFile = $null; $script:InText = $null
$script:HasDef = $false; $script:Def = $null
$script:Ind = 2; $script:RawJson = $false; $script:InPlace = $false; $script:ForceStr = $false
$script:Prefix = 'JSON_'

function Parse-Args {
  $a = $script:A
  if ($a -ccontains '-tst') { Out-Line 'true'; exit 0 }   # quick self-test: prints true
  if ($a.Count -eq 0) { Show-Usage; exit 0 }
  $script:Cmd = [string]$a[0]
  if ($script:Cmd -in @('help', '-h', '--help', '/?')) { Show-Usage; exit 0 }
  for ($i = 1; $i -lt $a.Count; $i++) {
    $x = [string]$a[$i]
    if ($x -ceq '-f' -or $x -ceq '--file') {
      $i++; if ($i -ge $a.Count) { Die "$x needs a value" }; $script:InFile = [string]$a[$i]
    } elseif ($x -ceq '-s' -or $x -ceq '--string') {
      $i++; if ($i -ge $a.Count) { Die "$x needs a value" }; $script:InText = [string]$a[$i]
    } elseif ($x -ceq '-d' -or $x -ceq '--default') {
      $i++; if ($i -ge $a.Count) { Die "$x needs a value" }; $script:Def = [string]$a[$i]; $script:HasDef = $true
    } elseif ($x -ceq '--prefix') {
      $i++; if ($i -ge $a.Count) { Die "$x needs a value" }; $script:Prefix = [string]$a[$i]
    } elseif ($x -ceq '-c' -or $x -ceq '--compact') { $script:Ind = 0
    } elseif ($x -ceq '-j' -or $x -ceq '--json')    { $script:RawJson = $true
    } elseif ($x -ceq '-i' -or $x -ceq '--in-place') { $script:InPlace = $true
    } elseif ($x -ceq '--str')                       { $script:ForceStr = $true
    } elseif ($x -ceq '-h' -or $x -ceq '--help')     { Show-Usage; exit 0
    } else { [void]$script:Pos.Add($x) }
  }
}

# ---------------------------------------------------------------------------
# loading
# ---------------------------------------------------------------------------
function Load-Doc {
  if ($null -ne $script:InText) { $t = $script:InText }
  elseif ($script:InFile) {
    if (-not (Test-Path -LiteralPath $script:InFile -PathType Leaf)) { Die "cannot read file: $($script:InFile)" }
    $t = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $script:InFile).ProviderPath)   # strips a UTF-8 BOM
  }
  elseif ([Console]::IsInputRedirected) { $t = [Console]::In.ReadToEnd() }
  else { Die 'no input: use -f FILE, -s "JSON", or pipe JSON in' }

  $t = $t.Trim([char]0xFEFF, [char]32, [char]9, [char]13, [char]10)
  if ($t.Length -eq 0) { Die 'parse error: empty input' }
  try {
    if ($t.StartsWith('{')) {
      $script:doc = ConvertFrom-Json -InputObject $t
    } else {
      # wrap arrays/scalars so Windows PowerShell 5.1 doesn't unroll or drop them
      $w = ConvertFrom-Json -InputObject ('{"r":' + $t + '}')
      if (@($w.PSObject.Properties).Count -ne 1) { throw 'unexpected data after JSON value' }
      $script:doc = $w.r
    }
  } catch { Die ('parse error: ' + $_.Exception.Message) }
}

# ---------------------------------------------------------------------------
# types, formatting
# ---------------------------------------------------------------------------
function Get-JType($v) {
  if ($null -eq $v) { return 'null' }
  if ($v -is [bool]) { return 'bool' }
  if ($v -is [string] -or $v -is [datetime]) { return 'string' }
  if ($v -is [System.Collections.IList]) { return 'array' }
  if ($v -is [pscustomobject]) { return 'object' }
  return 'number'
}
function Str($v) { if ($v -is [datetime]) { $v.ToString('yyyy-MM-ddTHH:mm:ssK') } else { [string]$v } }
function Fmt-Num($v) {
  if ($v -is [double] -or $v -is [single]) { return $v.ToString('R', $script:Inv) }
  return [string]::Format($script:Inv, '{0}', $v)
}
function Esc([string]$s) {
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append('"')
  foreach ($ch in $s.ToCharArray()) {
    $n = [int]$ch
    if     ($n -eq 34) { [void]$sb.Append('\"') }
    elseif ($n -eq 92) { [void]$sb.Append('\\') }
    elseif ($n -eq 10) { [void]$sb.Append('\n') }
    elseif ($n -eq 13) { [void]$sb.Append('\r') }
    elseif ($n -eq 9)  { [void]$sb.Append('\t') }
    elseif ($n -eq 8)  { [void]$sb.Append('\b') }
    elseif ($n -eq 12) { [void]$sb.Append('\f') }
    elseif ($n -lt 32) { [void]$sb.Append(('\u{0:x4}' -f $n)) }
    else               { [void]$sb.Append($ch) }
  }
  [void]$sb.Append('"')
  return $sb.ToString()
}
function Fmt-Scalar($v, [bool]$asJson) {
  $t = Get-JType $v
  if ($t -eq 'null') { return 'null' }
  if ($t -eq 'bool') { if ($v) { return 'true' } else { return 'false' } }
  if ($t -eq 'string') { $s = Str $v; if ($asJson) { return (Esc $s) } else { return $s } }
  return (Fmt-Num $v)
}
function Is-Container($v) { $t = Get-JType $v; return ($t -eq 'object' -or $t -eq 'array') }
function Count-Of($v) {
  $t = Get-JType $v
  if ($t -eq 'object') { return @($v.PSObject.Properties).Count }
  if ($t -eq 'array')  { return @($v).Count }
  return 0
}
function Child-List($v) {
  $list = New-Object System.Collections.ArrayList
  $t = Get-JType $v
  if ($t -eq 'object') { foreach ($pr in @($v.PSObject.Properties)) { [void]$list.Add($pr.Value) } }
  elseif ($t -eq 'array') { foreach ($e in $v) { [void]$list.Add($e) } }
  return ,$list
}
function To-Json($v, [int]$ind, [int]$depth) {
  $t = Get-JType $v
  if ($t -eq 'null')   { return 'null' }
  if ($t -eq 'bool')   { if ($v) { return 'true' } else { return 'false' } }
  if ($t -eq 'string') { return (Esc (Str $v)) }
  if ($t -eq 'number') { return (Fmt-Num $v) }
  if ($t -eq 'array') {
    $items = @($v)
    if ($items.Count -eq 0) { return '[]' }
    $parts = @(foreach ($x in $items) { To-Json $x $ind ($depth + 1) })
    if ($ind -le 0) { return '[' + ($parts -join ',') + ']' }
    $pad = ' ' * (($depth + 1) * $ind); $padc = ' ' * ($depth * $ind)
    return "[`n" + $pad + ($parts -join (",`n" + $pad)) + "`n" + $padc + ']'
  }
  $props = @($v.PSObject.Properties)
  if ($props.Count -eq 0) { return '{}' }
  $sep = if ($ind -gt 0) { ': ' } else { ':' }
  $parts = @(foreach ($pr in $props) { (Esc $pr.Name) + $sep + (To-Json $pr.Value $ind ($depth + 1)) })
  if ($ind -le 0) { return '{' + ($parts -join ',') + '}' }
  $pad = ' ' * (($depth + 1) * $ind); $padc = ' ' * ($depth * $ind)
  return "{`n" + $pad + ($parts -join (",`n" + $pad)) + "`n" + $padc + '}'
}
function Format-Value($v) {
  if (Is-Container $v) { return (To-Json $v $script:Ind 0) }
  return (Fmt-Scalar $v $script:RawJson)
}

# ---------------------------------------------------------------------------
# paths
# ---------------------------------------------------------------------------
function Seg($kind, $value) { [pscustomobject]@{ Kind = $kind; Value = $value } }
function Seg-Text($s) {
  if ($s.Kind -eq 'idx') { return '[' + $s.Value + ']' }
  if ($s.Value -match '^[A-Za-z_][A-Za-z0-9_-]*$') { return '.' + $s.Value }
  return '["' + $s.Value + '"]'
}
function Path-Text($segs) { $r = ''; foreach ($s in $segs) { $r += (Seg-Text $s) }; return $r }
function Show-Path($segs) { if ($segs.Count -eq 0) { return '.' }; return (Path-Text $segs) }

function Parse-Path([string]$p) {
  $segs = New-Object System.Collections.ArrayList
  if ($p -eq '' -or $p -eq '.') { return ,$segs }
  if ($p[0] -ne '.' -and $p[0] -ne '[') { $p = '.' + $p }
  $i = 0; $n = $p.Length
  while ($i -lt $n) {
    $c = [string]$p[$i]
    if ($c -eq '.') {
      $j = $i + 1
      while ($j -lt $n -and $p[$j] -ne '.' -and $p[$j] -ne '[') { $j++ }
      $name = $p.Substring($i + 1, $j - $i - 1)
      if ($name -eq '') { Die "bad path: $p" }
      [void]$segs.Add((Seg 'key' $name)); $i = $j
    } elseif ($c -eq '[') {
      if ($i + 1 -ge $n) { Die "bad path: $p" }
      $q = [string]$p[$i + 1]
      if ($q -eq '"' -or $q -eq "'") {
        $end = $p.IndexOf("$q]", $i + 2)
        if ($end -lt 0) { Die "bad path: $p" }
        [void]$segs.Add((Seg 'key' $p.Substring($i + 2, $end - $i - 2))); $i = $end + 2
      } else {
        $end = $p.IndexOf(']', $i)
        if ($end -lt 0) { Die "bad path: $p" }
        $num = $p.Substring($i + 1, $end - $i - 1)
        if ($num -notmatch '^[0-9]+$') { Die "bad index: [$num]" }
        [void]$segs.Add((Seg 'idx' ([int]$num))); $i = $end + 1
      }
    } else { Die "bad path: $p" }
  }
  return ,$segs
}

function Resolve-From($start, $segs) {
  $cur = $start
  foreach ($s in $segs) {
    if ($s.Kind -eq 'key') {
      if ($cur -isnot [pscustomobject]) { return @{ Found = $false } }
      $pr = $cur.PSObject.Properties[$s.Value]
      if ($null -eq $pr) { return @{ Found = $false } }
      $cur = $pr.Value
    } else {
      if ($cur -isnot [System.Collections.IList]) { return @{ Found = $false } }
      if ($s.Value -ge @($cur).Count) { return @{ Found = $false } }
      $cur = $cur[$s.Value]
    }
  }
  return @{ Found = $true; Value = $cur }
}
function Need-Node($segs) {
  $r = Resolve-From $script:doc $segs
  if (-not $r.Found) { Die ('path not found: ' + (Show-Path $segs)) 1 }
  return $r
}

# ---------------------------------------------------------------------------
# walking
# ---------------------------------------------------------------------------
function Visit($v, [string]$path, $key, $ptype, $cb) {
  & $cb $path $v $key $ptype
  $t = Get-JType $v
  if ($t -eq 'object') {
    foreach ($pr in @($v.PSObject.Properties)) {
      Visit $pr.Value ($path + (Seg-Text (Seg 'key' $pr.Name))) $pr.Name 'object' $cb
    }
  } elseif ($t -eq 'array') {
    $items = @($v)
    for ($i = 0; $i -lt $items.Count; $i++) { Visit $items[$i] ($path + '[' + $i + ']') $i 'array' $cb }
  }
}
function Is-Leaf($v) { return (-not (Is-Container $v)) -or ((Count-Of $v) -eq 0) }
function Disp([string]$path) { if ($path -eq '') { return '.' }; return $path }

function Env-Name([string]$prefix, [string]$path) {
  $n = ($path.TrimStart('.') -replace '[^A-Za-z0-9]+', '_').Trim('_')
  return $prefix + $n
}

# ---------------------------------------------------------------------------
# modifying
# ---------------------------------------------------------------------------
function Auto-Value([string]$t, [bool]$forceStr) {
  if ($forceStr) { return ,$t }
  if ($t -cmatch '^-?(0|[1-9][0-9]*)$') { $l = 0L; if ([long]::TryParse($t, [ref]$l)) { return ,$l } }
  if ($t -cmatch '^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$') { return ,([double]::Parse($t, $script:Inv)) }
  if ($t -ceq 'true')  { return ,$true }
  if ($t -ceq 'false') { return ,$false }
  if ($t -ceq 'null')  { return ,$null }
  return ,$t
}

function Set-At($node, $segs, [int]$i, $val, [bool]$del) {
  if ($i -ge $segs.Count) { return ,$val }
  $s = $segs[$i]; $last = ($i -eq $segs.Count - 1)
  if ($s.Kind -eq 'key') {
    if ($node -isnot [pscustomobject]) { Die ('path not found: ' + (Show-Path $segs)) 1 }
    $pr = $node.PSObject.Properties[$s.Value]
    if ($last -and $del) {
      if ($null -eq $pr) { Die ('path not found: ' + (Show-Path $segs)) 1 }
      [void]$node.PSObject.Properties.Remove($s.Value)
      return ,$node
    }
    if ($null -eq $pr) {
      if (-not $last) { Die ('path not found: ' + (Show-Path $segs)) 1 }
      Add-Member -InputObject $node -NotePropertyName $s.Value -NotePropertyValue $val
      return ,$node
    }
    if ($last) { $pr.Value = $val } else { $pr.Value = (Set-At $pr.Value $segs ($i + 1) $val $del) }
    return ,$node
  }
  if ($node -isnot [System.Collections.IList]) { Die ('path not found: ' + (Show-Path $segs)) 1 }
  $arr = New-Object System.Collections.ArrayList
  foreach ($e in $node) { [void]$arr.Add($e) }
  $idx = [int]$s.Value
  if ($last -and $del) {
    if ($idx -ge $arr.Count) { Die ('path not found: ' + (Show-Path $segs)) 1 }
    $arr.RemoveAt($idx)
  } elseif ($last -and $idx -eq $arr.Count) { [void]$arr.Add($val) }
  elseif ($idx -ge $arr.Count) { Die ('path not found: ' + (Show-Path $segs)) 1 }
  elseif ($last) { $arr[$idx] = $val }
  else { $arr[$idx] = (Set-At $arr[$idx] $segs ($i + 1) $val $del) }
  return ,([object[]]$arr.ToArray())
}

function Emit-Doc {
  $txt = To-Json $script:doc $script:Ind 0
  if ($script:InPlace) {
    if (-not $script:InFile) { Die '-i needs -f FILE' }
    $full = (Resolve-Path -LiteralPath $script:InFile).ProviderPath
    [IO.File]::WriteAllText($full, $txt + "`r`n", (New-Object System.Text.UTF8Encoding $false))
  } else { Out-Line $txt }
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
function Main {
  Parse-Args
  $known = @('get','keys','values','length','len','type','has','paths','find','search','where','env','set','del','pretty','minify','valid')
  if ($script:Cmd -notin $known) { [Console]::Error.WriteLine("jsh: unknown command: $($script:Cmd)"); Show-Usage; exit 2 }
  $pos = $script:Pos
  Load-Doc
  $first = if ($pos.Count -ge 1) { [string]$pos[0] } else { '' }
  $segs = Parse-Path $first

  switch ($script:Cmd) {
    'get' {
      $r = Resolve-From $script:doc $segs
      if (-not $r.Found) {
        if ($script:HasDef) { Out-Line $script:Def; exit 0 }
        Die ('path not found: ' + (Show-Path $segs)) 1
      }
      Out-Line (Format-Value $r.Value)
    }
    'type'   { $r = Need-Node $segs; Out-Line (Get-JType $r.Value) }
    'has'    { $r = Resolve-From $script:doc $segs; if ($r.Found) { exit 0 } else { exit 1 } }
    { $_ -eq 'length' -or $_ -eq 'len' } {
      $r = Need-Node $segs; $t = Get-JType $r.Value
      if (Is-Container $r.Value) { Out-Line ([string](Count-Of $r.Value)) }
      elseif ($t -eq 'string') { Out-Line ([string](Str $r.Value).Length) }
      else { Die "value of type $t has no length" 3 }
    }
    'keys' {
      $r = Need-Node $segs; $v = $r.Value; $t = Get-JType $v
      if ($t -eq 'object') { foreach ($pr in @($v.PSObject.Properties)) { Out-Line $pr.Name } }
      elseif ($t -eq 'array') { for ($i = 0; $i -lt @($v).Count; $i++) { Out-Line ([string]$i) } }
      else { Die 'not an object or array' 3 }
    }
    'values' {
      $r = Need-Node $segs
      if (-not (Is-Container $r.Value)) { Die 'not an object or array' 3 }
      $script:Ind = 0
      foreach ($c in (Child-List $r.Value)) { Out-Line (Format-Value $c) }
    }
    'paths' {
      $r = Need-Node $segs
      Visit $r.Value (Path-Text $segs) $null $null {
        param($path, $v, $key, $pt)
        if (Is-Leaf $v) { Out-Line ((Disp $path) + ' = ' + (To-Json $v 0 0)) }
      }
    }
    'find' {
      if ($pos.Count -lt 1) { Show-Usage; exit 2 }
      $script:Needle = [string]$pos[0]
      Visit $script:doc '' $null $null {
        param($path, $v, $key, $pt)
        if ($pt -eq 'object' -and $key -ceq $script:Needle) { Out-Line ($path + ' = ' + (To-Json $v 0 0)) }
      }
    }
    'search' {
      if ($pos.Count -lt 1) { Show-Usage; exit 2 }
      $script:Needle = [string]$pos[0]
      Visit $script:doc '' $null $null {
        param($path, $v, $key, $pt)
        if (-not (Is-Container $v)) {
          $txt = Fmt-Scalar $v $false
          if ($txt.IndexOf($script:Needle, [StringComparison]::OrdinalIgnoreCase) -ge 0) { Out-Line ((Disp $path) + ' = ' + (To-Json $v 0 0)) }
        }
      }
    }
    'where' {
      if ($pos.Count -lt 3) { Show-Usage; exit 2 }
      $r = Need-Node $segs
      if (-not (Is-Container $r.Value)) { Die 'not an object or array' 3 }
      $fseg = Parse-Path ([string]$pos[1]); $want = [string]$pos[2]
      $oseg = $null; if ($pos.Count -ge 4) { $oseg = Parse-Path ([string]$pos[3]) }
      foreach ($c in (Child-List $r.Value)) {
        $fr = Resolve-From $c $fseg
        if (-not $fr.Found -or (Is-Container $fr.Value)) { continue }
        if ((Fmt-Scalar $fr.Value $false) -cne $want) { continue }
        if ($null -ne $oseg) {
          $orr = Resolve-From $c $oseg
          if ($orr.Found) { Out-Line (Format-Value $orr.Value) }
        } else { Out-Line (To-Json $c 0 0) }
      }
    }
    'env' {
      $r = Need-Node $segs
      Visit $r.Value (Path-Text $segs) $null $null {
        param($path, $v, $key, $pt)
        $name = Env-Name $script:Prefix $path
        if (Is-Container $v) { Out-Line ($name.TrimEnd('_') + '__len=' + (Count-Of $v)) }
        if ((Is-Leaf $v) -and -not (Is-Container $v)) {
          Out-Line ($name + '=' + ((Fmt-Scalar $v $false) -replace '[\r\n]+', ' '))
        }
      }
    }
    'set' {
      if ($pos.Count -lt 2) { Show-Usage; exit 2 }
      $new = Auto-Value ([string]$pos[1]) $script:ForceStr
      $script:doc = (Set-At $script:doc $segs 0 $new $false)
      Emit-Doc
    }
    'del' {
      if ($pos.Count -lt 1) { Show-Usage; exit 2 }
      if ($segs.Count -eq 0) { Die 'cannot delete the root' 3 }
      $script:doc = (Set-At $script:doc $segs 0 $null $true)
      Emit-Doc
    }
    'pretty' { Out-Line (To-Json $script:doc 2 0) }
    'minify' { Out-Line (To-Json $script:doc 0 0) }
    'valid'  { }
  }
}

try { Main } catch { Die $_.Exception.Message 2 }
exit 0

#!/bin/bash
# Stop hook: block the stop (exit 2) when the final assistant message has a
# URL directly followed by a non-whitespace character, or is not in Japanese.
# Passes through on missing transcript, stop-hook continuation, or no finding.

set -uo pipefail

INPUT=$(cat)

# Loop guard: never re-block within a stop-hook-triggered continuation.
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
[ "$STOP_ACTIVE" = "true" ] && exit 0

TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then exit 0; fi
command -v perl >/dev/null 2>&1 || exit 0

# Final assistant message only, as in verify-completion-claims.sh.
LAST_MSG=$(tail -n 400 "$TRANSCRIPT" 2>/dev/null \
  | jq -Rc 'fromjson? | select(.type == "assistant") | [(.message.content // [])[]? | select(.type == "text") | .text] | join("\n") | select(length > 0)' 2>/dev/null \
  | tail -n 1 \
  | jq -r '.' 2>/dev/null)

[ -z "$LAST_MSG" ] && exit 0

# perl -CSD + use utf8: grep's multibyte character ranges are unreliable on macOS.
FINDINGS=$(printf '%s' "$LAST_MSG" | perl -CSD -e '
  use utf8;
  local $/;
  my $t = <STDIN>;

  $t =~ s/```.*?```//gs;
  $t =~ s/~~~.*?~~~//gs;
  $t =~ s/`[^`\n]*`//g;
  $t =~ s/\[[^\]\n]*\]\([^)\n]*\)//g;
  $t =~ s/<https?:\/\/[^>\s]*>//g;

  # ASCII-only URL: a Japanese tail would otherwise be reported as part of it.
  my @bad;
  while ($t =~ /(https?:\/\/[^\s<>"\x27`()\P{ASCII}]+)(.?)/g) {
    my ($url, $next) = ($1, $2);
    push @bad, $url if $url =~ /[.,:;!?]$/ || ($next ne "" && $next !~ /\s/);
  }
  if (@bad) {
    my %seen;
    my @u = grep { !$seen{$_}++ } @bad;
    print "URL\t", join("\t", @u[0 .. ($#u < 2 ? $#u : 2)]), "\n";
  }

  # Identifiers, URLs and paths are not prose.
  my $u = $t;
  $u =~ s/\S*\/\S*//g;
  $u =~ s/\b\w+(?:\.\w+)+\b//g;
  my $ja = () = $u =~ /[\p{Han}\p{Hiragana}\p{Katakana}ー]/g;
  my $la = () = $u =~ /[A-Za-z]/g;
  my $total = $ja + $la;
  if ($total >= 80 && $ja / $total < 0.15) {
    printf "LANG\t%d\n", int(100 * $ja / $total);
  }
')

[ -z "$FINDINGS" ] && exit 0

REASON="応答の形式チェックに失敗しました。"
while IFS=$'\t' read -r kind rest; do
  case "$kind" in
    URL)
      REASON="$REASON
- URL の直後に空白以外が続いています: ${rest//$'\t'/ , }
  → URL の直前・直後は半角スペースか改行にし、補足は URL の前に書いてください"
      ;;
    LANG)
      REASON="$REASON
- 応答が日本語ではありません(日本語の割合 ${rest}%)
  → 日本語で書き直してください。英文のまま必要な部分(コミットメッセージ案・引用・英文草稿)はコードブロックに入れてください"
      ;;
  esac
done <<< "$FINDINGS"

# Exit 2 blocks the stop; JSON on stdout would halt the session instead.
echo "$REASON" >&2
exit 2

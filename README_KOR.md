# dipstick

*[English README](README.md)*

AI 코딩 구독에 얼마나 남았는지, 그리고 지금 어떤 구독을 쓰고 있는지 확인해 주는 도구.

Claude Code, Codex, Antigravity는 각각 이동 기간 기준으로 사용량을 계산하고, 남은 사용량도 저마다 다른 곳에 표시합니다. 게다가 긴 작업을 시작하기 전에 정말 알고 싶은 것, 즉 *충분히 남았는지, 부족하다면 언제 다시 회복되는지*는 제대로 알려주지 않습니다. dipstick은 이 세 가지를 한곳에서 읽어 메뉴 막대에 보여줍니다.

```text
Claude Max                         MAIN   you@example.com
    5-hour window   76%   resets in 2h 47m
    7-day window    28%   resets in 2h 29m   ◂ binds
Codex Pro                                 you@example.com
    7-day window    82%   resets in 4d 22h
```

**프롬프트를 모델에 보내지 않습니다.** 모델에게 “얼마나 남았어?”라고 묻는 순간 새 사용 제한 기간이 열릴 수 있습니다. 계기판이 해야 할 일과는 정반대죠. 그래서 모든 측정값은 수동적인 파일 읽기이거나, 쿼터를 소모하지 않는 사용량 확인 엔드포인트를 통해 가져옵니다.

## 읽어오는 정보

| 구독 | 출처 | 비용 |
|---|---|---|
| Codex | 세션 rollout 파일에 기록된 `rate_limits` | 없음: 로컬 파일 |
| Claude Code | CLI 자체가 사용하는 엔드포인트인 `GET /api/oauth/usage` | 없음: 사용량 확인만 |
| Antigravity (`agy`) | 실행 중인 에이전트의 로컬 RPC에 있는 `RetrieveUserQuotaSummary` | 없음: localhost |

Codex rollout 파일은 몇 GB까지 커질 수 있으므로, 파싱 결과는 inode 기준으로 캐시합니다. 첫 실행 이후에는 새로고침이 약 1초 정도 걸립니다.

## 필요한 것

macOS 13+ 와 Python 3.9+(시스템 기본이면 충분). 패키지·데몬·오케스트레이터 전부 불필요 —
dipstick 은 설치돼 있는 것만 읽고 없는 것은 건너뜁니다:

| 쓰는 것 | dipstick 이 읽는 곳 | 없으면 |
|---|---|---|
| Claude Code | OAuth 사용량 엔드포인트(로그인 키체인) | 카드가 안 뜰 뿐 |
| Codex CLI | `~/.codex` 세션 롤아웃 | 〃 |
| Antigravity | 실행 중인 에이전트의 로컬 RPC | 〃 |

셋 중 하나만 있어도 됩니다. 다계정 래퍼 홈(Orca 식 `codex-accounts/*/home`, 또는 직접 만든
`~/.codex-profiles/*/home`)은 있으면 자동 감지 — 보너스일 뿐 요구사항이 아닙니다.

## 설치

macOS 13 이상과 Python 3.9 이상이 필요합니다. 시스템 Python이면 충분합니다. 별도 패키지는 없습니다.

```sh
git clone https://github.com/blkpark/dipstick.git && cd dipstick
install -m 755 tools/dipstick ~/.local/bin/dipstick     # CLI
./scripts/bundle.sh && cp -R build/Dipstick.app /Applications/   # 메뉴 막대 앱
./scripts/install-login.sh    # 선택 사항: 로그인 시 시작 (--remove로 해제)
```

Claude 수치를 읽으려면 OAuth 토큰이 필요합니다. 이 토큰은 로그인 키체인에 있으므로, 첫 실행 시 macOS 접근 허용 창이 뜹니다. 토큰은 Anthropic의 자체 사용량 엔드포인트를 호출하는 데만 사용되며, 저장되거나 다른 곳으로 전송되지 않습니다. 토큰이 만료되면 dipstick이 CLI와 같은 OAuth refresh 흐름으로 갱신하고, 결과를 같은 키체인 항목에 통째로 다시 써 둡니다 — 항목의 다른 내용은 보존되고, 모든 리더가 같은 토큰을 쓰게 되어 회전 경합이 없습니다. 사람 손이 필요한 것은 *로그아웃* 상태뿐입니다: `claude auth login`으로 복구됩니다.

## 사용법

```sh
dipstick                    # 텍스트 리포트
dipstick --serve            # 127.0.0.1:8787에서 웹 UI 실행, 클릭해서 main 설정
dipstick --html out.html    # 서버 없는 독립 HTML 페이지
dipstick --json             # 기계가 읽을 수 있는 스냅샷
dipstick --set-main claude-max   # --json에 나오는 아무 키나, 또는 "auto"
dipstick --main-cmd         # 지금 main인 항목의 실행 접두어
dipstick --lang ko|en       # 한국어 또는 영어 (웹 UI에는 전환 버튼 있음)
```

`--main-cmd`가 “main” 설정의 핵심입니다. 구독을 한 번 선택해 두면, 실행 명령에 특정 구독을 하드코딩하지 않아도 어떤 것을 쓸지 물어보게 할 수 있습니다.

```sh
$(dipstick --main-cmd) "$(cat prompt.txt)"
# -> env CODEX_HOME="…/codex-accounts/…/home" codex "$(cat prompt.txt)"
```

## 무엇을 문제로 판단하는가

**원시 퍼센트가 아니라 회복까지 걸리는 시간**을 봅니다. 5시간 기간에서 30%가 남은 것과 7일 기간에서 30%가 남은 것은 전혀 다른 문제입니다. 전자는 점심시간쯤이면 풀리지만, 후자는 며칠 동안 영향을 줍니다. 1시간 안에 리셋되는 기간은 *recovering*으로 표시되고 전체 판정에는 더 이상 영향을 주지 않습니다. 새 작업을 실제로 제한하는 기간은 *binds*로 표시됩니다.

단계는 `GO`(60% 이상), `TIGHT`(30-60%), `LOW`(30% 미만), `BLOCKED`입니다. 이 값들은 출발점일 뿐, 절대 법칙은 아닙니다. 실행 비용은 코드베이스와 작업에 따라 크게 달라집니다. dipstick은 모든 측정값을 기록하므로, 하루나 이틀 정도 기록이 쌓이면 기본값보다 실제 소모 속도가 더 좋은 기준이 됩니다.

## 설정

아래 설정은 모두 선택 사항입니다. 파일 위치는 `~/.config/dipstick/config.json`입니다.

```json
{
  "reserve": { "Claude": 30 },
  "policy": {
    "Codex Pro": ["2nd", "when the smaller plan runs short"]
  },
  "imminent_minutes": 60
}
```

**`reserve`**는 특정 구독의 일정 비율을 개인 사용분으로 남겨 둡니다. 에이전트가 도는 플랜과 같은 플랜으로 Claude 채팅도 한다면, 하한선을 두어 백그라운드 작업이 현재 대화를 잡아먹지 않게 할 수 있습니다. 하한선 아래로 내려간 구독은 보류됩니다. 단, 그 구독을 main으로 지정하면 명시적 override로 간주되어 하한선을 뚫고 사용하며, 페이지에도 그렇게 표시됩니다.

**`policy`**는 구독별로 남겨 두는 개인 메모입니다. 순위든 규칙이든, 본인이 일하는 순서든 상관없습니다. dipstick은 이를 표시만 하고, 그에 따라 동작하지는 않습니다.

## 속도, 그리고 실행 대상 선택 방식

모든 측정값은 **pace surplus**도 함께 보여줍니다. 이는 완전히 균등하게 사용한다고 가정했을 때의 기준에서 얼마나 떨어져 있는지를 뜻합니다. 예를 들어 `94% (+4)`는 기간이 막 리셋되어 94%가 정상 페이스라는 의미이지, 여유가 많다는 뜻은 아닙니다. 반대로 리셋 하루 전 40%는 충분히 넉넉할 수 있습니다. 판정은 고정 퍼센트가 아니라 이 surplus를 기준으로 매겨집니다.

`--main-cmd`는 새 실행이 어떤 구독을 태울지 두 가지 모드 중 하나로 선택합니다. 모드는 `--main-mode` 또는 웹 헤더의 토글로 정합니다.

- **weighted**(기본값): 사용할 수 있는 구독 중 페이스가 가장 좋은 것을 고릅니다. main에는 10%p의 유지 가중치를 주어, 아주 작은 차이 때문에 하루 중간에 계정이 바뀌지 않게 합니다. `reserve` 하한선이 있는 풀은 *자체 사용분으로 보존*되며, 직접 main으로 지정하지 않는 한 선택 대상에 들어가지 않습니다. 직접 main으로 지정하는 것이 opt-in입니다.
- **pinned**: dispatch에는 절대적입니다. 익명 선택은 전부 main으로 가며, 페이스 계산과 reserve 하한선까지 무시합니다. 사용량을 한곳에 몰아주는 것이 이 모드의 목적이기 때문입니다. 단 하나 넘지 않는 것이 있는데, 직접 입력한 `--vendor`입니다. 도구는 이미 사람이 골랐고, 다른 벤더의 CLI로 답하는 것은 사용량 집중이 아니라 명령 대체이기 때문입니다.

어느 쪽이든 답하는 것은 “지금 어느 것인가”뿐입니다. 실제로 무언가를 실행하지는 않습니다.

```sh
dipstick --bar-window binds|5h|7d   # 메뉴 바가 앞세울 창
```

메뉴 바는 구독당 수치 하나를 보여주며, 기본값은 실제로 작업을 막는 창입니다 — 5시간 수치 옆에
7일 수치가 오는 상황이 생깁니다. `5h` 나 `7d` 로 고정하면 모든 열이 같은 지평이라 바로 비교됩니다.
해당 길이의 창이 없는 구독(Codex 는 7일 창만 계측)은 바에서 사라지는 대신 제약 창으로 폴백합니다.
패널에도 같은 컨트롤이 있습니다.

`--vendor codex`는 **도구**를 고정하되, 계정은 여전히 선택 로직을 따르게 합니다. main이 다른 벤더에 pin되어 있어도 선택은 요청한 벤더 안에 머뭅니다 — 입력한 명령이 이깁니다. 덕분에 평범한 `codex` / `claude`를 셸 함수로 라우팅할 수 있습니다.

```sh
_dipstick_run() {
  local want="$1"; shift
  local pre
  if pre="$(command dipstick --main-cmd --vendor "$want" 2>/dev/null)" \
     && [[ "$pre" == *"$want"* ]]; then
    eval "$pre" '"$@"'
  else
    command "$want" "$@"    # 벤더가 다르거나 dipstick이 없어도 명령은 깨지 않음
  fi
}
codex()  { _dipstick_run codex  "$@" }
claude() { _dipstick_run claude "$@" }
```

`$pre == *$want*` 검사는 이중 방어입니다. CLI 자체가 입력한 벤더를 유지하므로 이 가드는
구버전 dipstick이 답할 때만 의미가 있습니다 — 접두어는 요청한 벤더를 담고 있을 때만 쓰고,
아니면 원래 바이너리를 그대로 실행합니다.

입력한 벤더는 reserve 하한선 제외 규칙도 우회합니다. 하한선은 백그라운드 작업으로부터 해당 도구의 개인 사용분을 보호하기 위한 것이고, 사용자가 직접 명령을 입력하는 행위 자체가 바로 그 보호 대상 사용이기 때문입니다. 익명 선택, 즉 `--vendor` 없이 고르는 경우에는 main으로 지정된 구독이 아닌 한 reserved 풀을 계속 제외합니다.

## 하지 않는 것

dipstick은 아무것도 실행하지 않고, 큐에 넣지 않고, 구독을 대신 전환하지도 않습니다. 보고하고, 사용자가 무엇을 골랐는지 기억할 뿐입니다. 결정은 사용자의 몫이며, 작업을 dispatch하는 방식은 지금 쓰고 있는 그대로 두면 됩니다.

## 라이선스

MIT. 자세한 내용은 [LICENSE](LICENSE)를 참고하세요.

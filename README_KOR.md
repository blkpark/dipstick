<img src="assets/logo.svg" width="72" align="right" alt="">

# dipstick

*[English README](README.md)*

AI 코딩 구독에 얼마나 남았는지, 지금 어느 걸 쓰고 있는지 보여주는 메뉴바 계기다.

Claude Code, Codex, Antigravity 는 각자 다른 창(window)으로 사용량을 재고, 각자 다른 데
표시하고, 정작 긴 작업을 걸기 전에 알고 싶은 것 — *지금 남은 걸로 되나, 안 되면 언제
돌아오나* — 은 아무도 알려주지 않는다. dipstick 은 셋을 한 자리에서 읽는다.

<img src="assets/screenshot.png" width="620" alt="메뉴바에 구독 3개, 클릭하면 열리는 상세 패널">

계정 3개에 걸친 구독 3개를 한 번에 읽은 화면이다. Codex 두 요금제와 Claude Max 가 각각
다른 로그인이다. 메뉴바에는 구독마다 숫자 하나씩, 클릭하면 창별 잔량과 페이스, 예비 하한,
다음 발사가 탈 풀까지 패널에 펼친다.

**모델에 프롬프트를 보내지 않는다.** "얼마 남았어?" 를 모델에게 물으면 그 순간 새 창이
열린다 — 계기가 할 짓이 아니다. 그래서 모든 값은 파일을 그대로 읽거나, 사용량만 알려주고
쿼터를 쓰지 않는 엔드포인트에서 온다.

## 어디서 읽나

| 구독 | 출처 | 비용 |
|---|---|---|
| Codex | 세션 rollout 파일에 기록된 `rate_limits` | 없음 — 로컬 파일 |
| Claude Code | `GET /api/oauth/usage` — CLI 가 쓰는 그 엔드포인트 | 없음 — 사용량 조회만 |
| Antigravity (`agy`) | 실행 중인 agent 의 로컬 RPC `RetrieveUserQuotaSummary` | 없음 — localhost |

Codex rollout 은 수 GB 까지 커지므로 파싱 결과를 inode 기준으로 캐시한다. 첫 실행 뒤
새로고침은 1초쯤 걸린다.

## 뭐가 있어야 하나

macOS 13 이상, Python 3.9 이상(시스템에 딸린 것으로 충분). 패키지도, 데몬도, 오케스트레이터도
필요 없다. 설치돼 있는 것만 읽고 나머지는 건너뛴다.

| 쓰는 것 | dipstick 이 읽는 것 | 없으면 |
|---|---|---|
| Claude Code | OAuth 사용량 엔드포인트 (로그인 keychain) | 카드가 안 뜰 뿐 |
| Codex CLI | `~/.codex` 세션 rollout | 〃 |
| Antigravity | 실행 중 agent 의 로컬 RPC | 〃 |

셋 중 하나만 있어도 된다.

## 같은 도구를 계정 여러 개로 쓸 때

dipstick 이 진짜 필요한 경우다 — 같은 벤더 구독 둘, 계기는 하나, 발사는 여유 있는 쪽으로.
두 CLI 모두 프로필 전환 기능이 없다. 대신 환경변수로 지정한 홈 디렉터리 아래에 전부
보관하므로, **계정을 하나 더 쓴다는 건 디렉터리를 하나 더 만든다는 뜻**이다.

**Codex** — `CODEX_HOME` 에 로그인·설정·세션 rollout 이 함께 들어간다.

```sh
mkdir -p ~/.codex-profiles/work/home
CODEX_HOME=~/.codex-profiles/work/home codex login     # 다른 계정으로 로그인
alias codex-work='CODEX_HOME=~/.codex-profiles/work/home codex'
```

**Claude Code** — `CLAUDE_CONFIG_DIR` 이 같은 역할을 한다. 로그인은 디렉터리가 아니라 로그인
keychain 에 들어가는데, 그 항목 이름이 디렉터리에서 나온다
(`Claude Code-credentials-<절대경로 sha256 앞 8자리>`). 그래서 config 디렉터리마다 세션이
따로 잡히고, 새로 로그인해도 앞 계정을 덮어쓰지 않는다.

```sh
CLAUDE_CONFIG_DIR=~/.claude-work claude          # 첫 실행에서 로그인 요구
alias claude-work='CLAUDE_CONFIG_DIR=~/.claude-work claude'
```

dipstick 은 이걸 알아서 찾는다. Codex 는 `~/.codex`, `~/.codex-profiles/*/home`, Orca 식
`codex-accounts/*/home` 을, Claude 는 `~/.claude` 와 형제 격인 `~/.claude-*` 를 훑는다.
다른 데 둔 홈은 설정 파일에 적어주면 되고, 그 외에 바꿀 건 없다.

```json
{ "claude_homes": ["~/work/claude-config"] }
```

그러면 계정마다 카드가 따로 서고, `--main-cmd` 도 고른 계정의 홈을 접두사에 실어 답한다.

### Orca 같은 다계정 래퍼와 함께 쓸 때

dipstick 은 오케스트레이터가 없어도 돌아간다 — 그런데 이미 쓰고 있다면 둘은 깔끔하게
맞물린다. 역할이 반대편이기 때문이다. 래퍼는 여러 계정으로 *발사하는* 쪽을, dipstick 은
그 계정들을 *계량하는* 쪽을 맡는다.

Orca 가 이 도구가 옆에서 만들어진 경우다. Orca 는 Codex 계정을 각자의 홈
(`codex-accounts/*/home`)에, Claude 로그인을 자기 관리 keychain 항목에 두는데 — dipstick
은 둘 다 알아서 읽는다. Orca 가 발사할 수 있는 계정은 설정 없이 전부 카드로 선다. 반대
방향으로는 `$(dipstick --main-cmd)` 를 Orca 든 맨 셸이든 실행 명령 앞에 끼우면, 래퍼가
계기가 여유 있다고 말한 계정으로 발사한다. 다른 래퍼도 같은 모양이다. `claude_homes` 나
`~/.codex-profiles/*/home` 심볼릭 링크를 그 래퍼가 계정을 두는 곳으로 향하게 하면 된다.

## 설치

```sh
git clone https://github.com/blkpark/dipstick.git && cd dipstick
install -m 755 tools/dipstick ~/.local/bin/dipstick     # CLI
./scripts/bundle.sh && cp -R build/Dipstick.app /Applications/   # 메뉴바 앱
./scripts/install-login.sh    # 선택: 로그인 시 자동 실행 (--remove 로 해제)
```

Claude 값을 읽으려면 OAuth 토큰이 필요하고 그건 로그인 keychain 에 있으므로, 첫 실행에서
macOS 접근 허용 창이 한 번 뜬다. 토큰은 Anthropic 자체 사용량 엔드포인트를 호출하는 데만
쓰고 어디에도 저장하거나 보내지 않는다. 토큰이 만료되면 CLI 와 같은 OAuth refresh 흐름으로
갱신해서 **같은 keychain 항목에 문서 전체를 통째로** 되쓴다 — 그래야 거기 같이 들어 있는
다른 값이 날아가지 않고, 여러 프로세스가 회전한 토큰을 두고 다투지 않는다. 사람 손이 필요한
건 *로그아웃* 이라고 뜰 때뿐이고, `claude auth login` 이면 복구된다.

## 사용

```sh
dipstick                    # 텍스트 리포트
dipstick --serve            # 선택: 127.0.0.1:8787 웹 UI, 클릭으로 메인 지정
dipstick --html out.html    # 서버 없이 열리는 단일 파일 페이지
dipstick --json             # 기계용 스냅샷
dipstick --set-main claude-max   # --json 의 key 중 하나, 또는 "auto"
dipstick --main-cmd         # 지금 메인인 구독의 실행 접두사
dipstick --lang ko|en       # 한국어/영어 (웹 UI 에는 전환 버튼)
dipstick --statusline       # 셸 프롬프트·tmux 바용 한 줄
```

`--statusline` 은 한 줄만 낸다. 구독별로 메뉴바가 앞세우는 창, 메인에 별표, 색은 LOW·BLOCKED
에서만, 값이 낡았으면 `%?`:

```
ProLite* 100% | Max 47% | Pro 97%
```

한 번 실행에 1초쯤 걸리므로(계기를 새로 읽는다) 블로킹하는 자리 말고 주기적으로 부르는
자리에 건다 — tmux 라면 `status-interval 15`, 프롬프트라면 비동기 세그먼트. 파이프로 넘기면
색은 알아서 빠진다(`--no-color` 로 강제 가능).

`--main-cmd` 가 "메인" 설정의 존재 이유다. 구독을 한 번 정해두고, 실행 명령이 그때그때
물어보게 한다 — 명령마다 계정을 박아두지 않는다.

```sh
$(dipstick --main-cmd) "$(cat prompt.txt)"
# -> env CODEX_HOME="…/codex-accounts/…/home" codex "$(cat prompt.txt)"
```

## 알림

구독의 제약 창이 LOW·BLOCKED 로 **넘어갈 때**, 그리고 사람들이 정작 기다리는 쪽 — 다시
회복될 때 macOS 알림을 띄운다. 전이에서만 울린다. 이미 낮은 상태로 앱을 켜면 조용하고,
같은 나쁜 소식을 다섯 번 읽어도 알림은 하나다. 패널 아래에서 끄고 켠다. 낡은 값은 어느
쪽으로도 알림을 만들지 않는다.

## MCP — 에이전트가 계기를 직접 읽게

`mcp/dipstick-mcp` 는 같은 CLI 를 감싼 MCP stdio 서버다. MCP 를 쓰는 에이전트(Claude Code,
Codex, Cursor…)면 긴 작업을 걸기 전에 스스로 물어볼 수 있다.

```sh
install -m 755 mcp/dipstick-mcp ~/.local/bin/dipstick-mcp

# Claude Code
claude mcp add --scope user dipstick -- ~/.local/bin/dipstick-mcp

# Codex
codex mcp add dipstick -- ~/.local/bin/dipstick-mcp

# Antigravity (및 다른 Gemini 계열 CLI) — ~/.gemini/config/mcp_config.json:
#   { "mcpServers": { "dipstick": { "command": "~/.local/bin/dipstick-mcp", "args": [] } } }
```

다른 MCP 클라이언트도 등록 방법은 같다. `~/.local/bin/dipstick-mcp` 를 stdio 서버로,
인자 없이, 환경변수 없이.

도구는 셋이고 전부 읽기 전용이다. `quota_status`(전체 — 페이스와 예비 상태 포함),
`can_i_start(minutes, model?)`(GO / WAIT + 회복 시각 / NO_DATA — **더 낮은 모델을 권하지
않는다**. `model` 을 주면 그 모델 전용 창과 그 모델이 같이 깎는 공용 창만 본다),
`which_subscription`(익명 발사가 탈 구독 — 이름만, 명령줄은 주지 않는다). 도구 설명문에
읽는 규칙을 같이 실어놨으므로, 그걸 인용하는 에이전트는 페이스·임박·낡음 규칙을 스스로
다시 만들어내다 틀리는 대신 그대로 물려받는다. 발사는 원래 쓰던 도구가 계속 맡는다 —
이 서버에는 무언가를 실행하는 도구가 없다.

## 토큰

대시보드는 이 기계가 실제로 쓴 양도 보여준다. 같은 로컬 로그에서 읽은, 현재 창의 시간대별
토큰을 출력·신규 입력·캐시 읽기로 나누고 캐시 적중률까지 붙인다.

모델별로 쪼개서 보여준다. 모델마다 창을 깎는 속도가 다르고, 요금제에 따라 공용 한도와 별개로
모델 전용 한도가 붙기도 하기 때문이다.

남은 양도 같은 방식으로만 말한다 — 그것도 믿을 만할 때만. 얼마 남았는지는 다음에 뭘 돌리냐에
달렸으므로, 패널은 모델별로 답한다: 그 모델만으로 창을 끝까지 쓰면 얼마인지. 섞어 쓰면 그
사이 어딘가다. 가중치는 시간대별 소모량을 모델별 사용량에 대해 비음수 적합해서 얻고,
창을 설명해낼 때만(R² ≥ 0.7) 남긴다. 안 되면 통합 구간 하나로 물러나되 R² ≥ 0.4 는 요구하고,
그것도 안 되면 안 된다고 쓴다.

대부분의 자리에서 "남은 토큰 몇 개" 라는 숫자까지는 일부러 가지 않는다. 창의 용량이 어떻게
소모되는지 두 벤더 모두 공개하지 않으므로, 정직한 환산은 끝난 창들에서 적합한 것뿐이고,
dipstick 은 그 창들이 서로 얼마나 어긋나는지부터 재고 나서 인용한다. 충분히 일치하면
그 편차를 달아 구간으로 보여주고, 아니면 그렇다고 쓰고 정확한 값인 퍼센트로 돌려보낸다.
여기서 잰 값으로 7일 창은 ±60%, 5시간 창은 ±200% 근처라 짧은 창은 사용량만 보여주고
추정은 하지 않는다.

이유는 숫자에 그대로 보인다. 캐시 읽기가 토큰 수의 97% 쯤인데 한도는 거의 깎지 않고,
그 비중이 창마다 움직인다.

## 문제 여부를 어떻게 판단하나

**퍼센트가 아니라 회복까지 걸리는 시간으로 본다.** 5시간 창의 30% 와 7일 창의 30% 는 다른
문제다. 앞의 것은 점심 먹는 동안 풀리고 뒤의 것은 며칠 간다. 한 시간 안에 리셋되는 창은
*회복 중* 으로 표시하고 판정에서 뺀다. 실제로 새 작업을 막는 창에 *제약* 을 붙인다.

등급은 `GO`(60% 이상), `TIGHT`(30~60%), `LOW`(30% 미만), `BLOCKED` 이다. 물리 법칙이 아니라
출발점이다 — 한 번 돌릴 때 드는 값은 코드베이스와 작업에 따라 엄청나게 다르다. dipstick 은
읽은 값을 전부 기록하므로, 하루 이틀 쌓이면 기본값보다 거기서 나온 소모 속도가 낫다.

## 설정

전부 선택 사항이다 — `~/.config/dipstick/config.json`:

```json
{
  "reserve": { "Claude": 30 },
  "policy": {
    "Codex Pro": ["2순위", "ProLite 가 부족할 때"]
  },
  "imminent_minutes": 60
}
```

**`reserve`** 는 구독의 일정 비율을 사람 몫으로 남긴다. 에이전트가 돌리는 요금제로 본인도
대화한다면, 하한이 있어야 백그라운드 작업이 지금 하고 있는 대화를 먹어치우지 않는다.
하한 아래로 내려간 구독은 보류된다 — 단, 메인으로 지정하면 그건 명시적 override 라
그대로 태우고 화면에 그렇게 적는다.

**`policy`** 는 구독마다 적어두는 본인 메모다(순위든 규칙이든, 본인이 일하는 순서). dipstick
은 표시만 하고 그에 따라 행동하지 않는다.

## 페이스, 그리고 발사 대상 선정

모든 값에는 **페이스 여유폭**이 같이 붙는다. 완벽히 균등하게 썼을 때의 선에서 얼마나 떨어져
있는지다(`94% (+4)` — 창이 막 리셋됐으니 94% 는 여유가 아니라 정상 페이스다. 리셋 하루 전의
40% 는 넉넉하다). 판정은 고정 퍼센트가 아니라 이 여유폭으로 매긴다.

`--main-cmd` 는 새 발사가 태울 구독을 두 모드 중 하나로 고른다(`--main-mode`, 또는 웹 헤더
토글).

- **weighted**(기본) — 태워도 되는 구독 중 페이스가 가장 좋은 쪽. 메인에는 10%p 관성을 줘서
  근소한 차이로 하루 중간에 계정이 뒤집히지 않게 한다. `reserve` 하한이 있는 풀은 *사람 몫*
  이므로 메인으로 지정하지 않는 한 후보에 들어오지 않는다 — 그 지정이 곧 opt-in 이다.
- **pinned** — 발사에 대해서는 절대적이다. 익명 선택은 전부 메인이 가져가고 페이스 계산도
  예비 하한도 무시한다. 소모를 한 곳에 몰아주는 게 이 모드의 목적이다. 딱 하나 넘지 않는
  것이 사람이 직접 친 `--vendor` 다 — 도구는 이미 사람이 골랐고, 거기에 다른 벤더의 CLI 로
  답하면 소모를 몰아주는 게 아니라 명령을 바꿔치기하는 것이다.

어느 쪽이든 답하는 건 "지금은 어느 것" 뿐이고, 실행은 여전히 하지 않는다.

```sh
dipstick --bar-window binds|5h|7d   # 메뉴바가 앞세울 창
```

메뉴바는 구독당 숫자 하나를 보여주는데, 기본값은 실제로 작업을 막는 창이다. 그러다 보니
5시간 값과 7일 값이 나란히 서기도 한다. `5h` 나 `7d` 로 고정하면 같은 지평으로 줄을 맞춰
바로 비교된다. 그 길이의 창이 없는 구독(Codex 는 7일 창만 잰다)은 바에서 사라지는 대신
자기 제약 창으로 돌아간다. 패널에도 같은 스위치가 있다.

`--vendor codex` 는 **도구**를 고정하고 계정은 계속 선택에 맡긴다. 메인이 다른 벤더로
고정돼 있어도 선택은 지정한 벤더 안에서 이뤄진다 — 사람이 친 쪽이 이긴다. 덕분에 그냥
`codex` / `claude` 를 셸 함수로 태울 수 있다.

```sh
_dipstick_run() {
  local want="$1"; shift
  local pre
  if pre="$(command dipstick --main-cmd --vendor "$want" 2>/dev/null)" \
     && [[ "$pre" == *"$want"* ]]; then
    eval "$pre" '"$@"'
  else
    command "$want" "$@"    # 벤더가 다르거나 dipstick 이 없으면 — 명령은 절대 망가뜨리지 않는다
  fi
}
codex()  { _dipstick_run codex  "$@" }
claude() { _dipstick_run claude "$@" }
```

`$pre == *$want*` 검사는 이중 방어다. CLI 가 이미 사람이 친 벤더를 지키므로, 이 가드가
의미를 갖는 건 옛 버전 dipstick 이 답할 때뿐이다 — 요청한 벤더를 접두사가 실제로 지목할
때만 쓰고, 아니면 맨 바이너리를 그대로 실행한다.

직접 친 벤더는 예비 하한 배제도 통과한다. 하한은 그 도구를 본인이 쓸 몫을 백그라운드
작업에서 지키려고 있는 것이고, 사람이 직접 명령을 친 것 자체가 바로 그 보호받는 사용이기
때문이다. 익명 선택(`--vendor` 없음)은 여전히 메인이 아닌 한 예비 풀을 뺀다.

## 하지 않는 것

무언가를 실행하거나, 큐에 넣거나, 대신 구독을 바꾸지 않는다. 읽어서 보여주고, 어느 걸
골랐는지 기억한다. 판단은 사람 몫이고, 일을 실제로 던지는 건 이미 쓰고 있던 것이 계속
맡는다.

## 라이선스

MIT — [LICENSE](LICENSE) 참고.
